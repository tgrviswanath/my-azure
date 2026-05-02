# Lab 07 — Azure Cosmos DB: Create, Query & Optimize

## Objective
Create a Cosmos DB account, design a data model, perform CRUD operations, configure indexing, and explore consistency levels.

## Prerequisites
- Azure CLI installed and logged in
- Python 3.8+ installed
- Estimated time: 60 minutes
- Estimated cost: ~$0.00 (free tier — 1000 RU/s + 25GB free)

---

## Step 1: Create Cosmos DB Account

```bash
RG="rg-lab07-cosmosdb-dev"
LOCATION="eastus"
COSMOS_ACCOUNT="cosmos-lab07-$RANDOM"
DATABASE="ecommerce"
CONTAINER="orders"

# Create resource group
az group create --name $RG --location $LOCATION

# Create Cosmos DB account (SQL API, free tier)
az cosmosdb create \
  --name $COSMOS_ACCOUNT \
  --resource-group $RG \
  --locations regionName=$LOCATION failoverPriority=0 isZoneRedundant=false \
  --default-consistency-level Session \
  --enable-free-tier true \
  --enable-automatic-failover false \
  --kind GlobalDocumentDB

echo "Cosmos DB account: $COSMOS_ACCOUNT"
echo "Waiting for account to be ready..."
az cosmosdb show \
  --name $COSMOS_ACCOUNT \
  --resource-group $RG \
  --query "documentEndpoint" \
  --output tsv
```

**Expected output**: Cosmos DB endpoint URL

---

## Step 2: Create Database and Container

```bash
# Create database with shared throughput (400 RU/s shared)
az cosmosdb sql database create \
  --account-name $COSMOS_ACCOUNT \
  --resource-group $RG \
  --name $DATABASE \
  --throughput 400

# Create orders container with partition key
az cosmosdb sql container create \
  --account-name $COSMOS_ACCOUNT \
  --resource-group $RG \
  --database-name $DATABASE \
  --name $CONTAINER \
  --partition-key-path "/customerId" \
  --throughput 400 \
  --idx '{
    "indexingMode": "consistent",
    "automatic": true,
    "includedPaths": [{"path": "/*"}],
    "excludedPaths": [
      {"path": "/description/?"},
      {"path": "/_etag/?"}
    ],
    "compositeIndexes": [
      [
        {"path": "/customerId", "order": "ascending"},
        {"path": "/createdAt", "order": "descending"}
      ]
    ]
  }'

# Create products container (dedicated throughput)
az cosmosdb sql container create \
  --account-name $COSMOS_ACCOUNT \
  --resource-group $RG \
  --database-name $DATABASE \
  --name products \
  --partition-key-path "/category" \
  --throughput 400

echo "Database and containers created"
```

---

## Step 3: Python SDK — CRUD Operations

```bash
# Install SDK
pip install azure-cosmos azure-identity

# Get connection string
COSMOS_KEY=$(az cosmosdb keys list \
  --name $COSMOS_ACCOUNT \
  --resource-group $RG \
  --query primaryMasterKey \
  --output tsv)

COSMOS_ENDPOINT=$(az cosmosdb show \
  --name $COSMOS_ACCOUNT \
  --resource-group $RG \
  --query documentEndpoint \
  --output tsv)

echo "Endpoint: $COSMOS_ENDPOINT"
```

```python
# cosmos_lab.py
import os
import json
import time
import uuid
from azure.cosmos import CosmosClient, PartitionKey, exceptions

# Connection
ENDPOINT = os.environ.get('COSMOS_ENDPOINT', 'YOUR_ENDPOINT')
KEY = os.environ.get('COSMOS_KEY', 'YOUR_KEY')

client = CosmosClient(ENDPOINT, KEY)
database = client.get_database_client('ecommerce')
container = database.get_container_client('orders')

# ── CREATE ────────────────────────────────────────────────────────────────────
def create_order(customer_id: str, items: list) -> dict:
    order = {
        'id': str(uuid.uuid4()),
        'customerId': customer_id,  # partition key
        'items': items,
        'total': sum(i['price'] * i['quantity'] for i in items),
        'status': 'PENDING',
        'createdAt': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'updatedAt': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    }
    result = container.create_item(body=order)
    print(f"Created order: {result['id']} (RU charge: {container.client_connection.last_response_headers.get('x-ms-request-charge', 'N/A')})")
    return result

# ── READ ──────────────────────────────────────────────────────────────────────
def get_order(order_id: str, customer_id: str) -> dict:
    """Point read — most efficient, 1 RU"""
    try:
        item = container.read_item(item=order_id, partition_key=customer_id)
        print(f"Read order: {item['id']}")
        return item
    except exceptions.CosmosResourceNotFoundError:
        return None

# ── QUERY ─────────────────────────────────────────────────────────────────────
def get_customer_orders(customer_id: str, status: str = None) -> list:
    """Query within partition — efficient"""
    query = "SELECT * FROM c WHERE c.customerId = @customerId"
    params = [{"name": "@customerId", "value": customer_id}]

    if status:
        query += " AND c.status = @status"
        params.append({"name": "@status", "value": status})

    query += " ORDER BY c.createdAt DESC"

    items = list(container.query_items(
        query=query,
        parameters=params,
        partition_key=customer_id  # Scoped to partition — efficient!
    ))
    print(f"Found {len(items)} orders for customer {customer_id}")
    return items

def get_orders_by_status(status: str) -> list:
    """Cross-partition query — less efficient, avoid if possible"""
    query = "SELECT c.id, c.customerId, c.total, c.createdAt FROM c WHERE c.status = @status"
    items = list(container.query_items(
        query=query,
        parameters=[{"name": "@status", "value": status}],
        enable_cross_partition_query=True  # Required for cross-partition
    ))
    print(f"Found {len(items)} {status} orders (cross-partition query)")
    return items

# ── UPDATE ────────────────────────────────────────────────────────────────────
def update_order_status(order_id: str, customer_id: str, new_status: str) -> dict:
    """Patch — update specific fields without replacing entire document"""
    operations = [
        {"op": "replace", "path": "/status", "value": new_status},
        {"op": "replace", "path": "/updatedAt", "value": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}
    ]
    result = container.patch_item(
        item=order_id,
        partition_key=customer_id,
        patch_operations=operations
    )
    print(f"Updated order {order_id} status to {new_status}")
    return result

# ── DELETE ────────────────────────────────────────────────────────────────────
def delete_order(order_id: str, customer_id: str):
    container.delete_item(item=order_id, partition_key=customer_id)
    print(f"Deleted order: {order_id}")

# ── TRANSACTIONS (Transactional Batch) ───────────────────────────────────────
def create_order_with_inventory_update(customer_id: str, items: list):
    """Atomic batch within a single partition"""
    order_id = str(uuid.uuid4())
    now = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())

    # All operations must be in the same partition
    batch_operations = [
        ("create", {
            'id': order_id,
            'customerId': customer_id,
            'items': items,
            'total': sum(i['price'] * i['quantity'] for i in items),
            'status': 'CONFIRMED',
            'createdAt': now
        }, {}),
        ("patch", order_id, {
            "patch_operations": [
                {"op": "replace", "path": "/status", "value": "PROCESSING"}
            ]
        })
    ]

    try:
        results = container.execute_item_batch(
            batch_operations=batch_operations,
            partition_key=customer_id
        )
        print(f"Batch transaction succeeded: {len(results)} operations")
        return order_id
    except exceptions.CosmosBatchOperationError as e:
        print(f"Batch failed at operation {e.error_index}: {e.message}")
        raise

# ── DEMO ──────────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    print("=== Cosmos DB Lab ===\n")

    # Create orders
    order1 = create_order('cust-001', [
        {'productId': 'prod-1', 'name': 'Laptop', 'price': 999.99, 'quantity': 1},
        {'productId': 'prod-2', 'name': 'Mouse', 'price': 29.99, 'quantity': 2}
    ])

    order2 = create_order('cust-001', [
        {'productId': 'prod-3', 'name': 'Keyboard', 'price': 79.99, 'quantity': 1}
    ])

    order3 = create_order('cust-002', [
        {'productId': 'prod-1', 'name': 'Laptop', 'price': 999.99, 'quantity': 2}
    ])

    # Read
    fetched = get_order(order1['id'], 'cust-001')
    print(f"Fetched: {fetched['id']}, Total: ${fetched['total']}")

    # Query
    cust_orders = get_customer_orders('cust-001')
    print(f"Customer orders: {[o['id'] for o in cust_orders]}")

    # Update
    update_order_status(order1['id'], 'cust-001', 'SHIPPED')

    # Cross-partition query
    pending = get_orders_by_status('PENDING')

    print("\n=== Lab Complete ===")
```

```bash
# Run the lab
export COSMOS_ENDPOINT=$COSMOS_ENDPOINT
export COSMOS_KEY=$COSMOS_KEY
python cosmos_lab.py
```

---

## Step 4: Explore Consistency Levels

```bash
# Change consistency level
az cosmosdb update \
  --name $COSMOS_ACCOUNT \
  --resource-group $RG \
  --default-consistency-level Eventual

# Available levels (strongest to weakest):
# Strong → Bounded Staleness → Session → Consistent Prefix → Eventual

# Per-request consistency override (Python SDK)
# from azure.cosmos import ConsistencyLevel
# item = container.read_item(
#     item=order_id,
#     partition_key=customer_id,
#     consistency_level=ConsistencyLevel.Strong
# )
```

---

## Step 5: Monitor RU Consumption

```bash
# Enable diagnostic settings
az monitor diagnostic-settings create \
  --name diag-cosmos \
  --resource $(az cosmosdb show \
    --name $COSMOS_ACCOUNT \
    --resource-group $RG \
    --query id --output tsv) \
  --workspace $(az monitor log-analytics workspace show \
    --workspace-name law-lab07 \
    --resource-group $RG \
    --query id --output tsv 2>/dev/null || echo "CREATE_LAW_FIRST") \
  --logs '[{"category":"DataPlaneRequests","enabled":true}]' \
  --metrics '[{"category":"Requests","enabled":true}]'

# KQL query to find expensive operations
# CDBDataPlaneRequests
# | where TimeGenerated > ago(1h)
# | summarize TotalRU = sum(RequestCharge), Count = count()
#   by OperationType, CollectionName
# | order by TotalRU desc
```

---

## Step 6: Cleanup

```bash
az group delete --name $RG --yes --no-wait
echo "Resource group deletion initiated"
```

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| 429 Too Many Requests | RU/s exceeded | Increase throughput or optimize queries |
| Cross-partition query slow | No partition filter | Add partition key to WHERE clause |
| Item not found | Wrong partition key | Verify partition key value matches |
| Batch fails | Items in different partitions | All batch items must share partition key |
| High RU for reads | Using query instead of point read | Use `read_item()` with id + partition key |

---

## What You Learned

✅ Create Cosmos DB account with free tier
✅ Design containers with appropriate partition keys
✅ Perform efficient point reads vs cross-partition queries
✅ Use patch operations for partial updates
✅ Execute transactional batches within a partition
✅ Understand RU consumption and monitoring
✅ Configure indexing policies for performance

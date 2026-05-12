# Steps — Project 9.3: Azure Event Hubs + Stream Analytics

## Phase 1: Create Event Hubs Namespace + Hub

```bash
# Variables
RG="rg-eventhubs-lab"
LOCATION="eastus"
EH_NAMESPACE="eh-orders-$(date +%s | tail -c 8)"
EH_HUB="orders-hub"
STORAGE_NAME="stehoutput$(date +%s | tail -c 6)"

# Create resource group
az group create --name $RG --location $LOCATION --tags project=event-hubs stage=09

# Create Event Hubs Namespace (Standard tier for consumer groups)
az eventhubs namespace create \
  --resource-group $RG \
  --name $EH_NAMESPACE \
  --location $LOCATION \
  --sku Standard \
  --capacity 1 \
  --enable-auto-inflate false

# Create Event Hub with 4 partitions
az eventhubs eventhub create \
  --resource-group $RG \
  --namespace-name $EH_NAMESPACE \
  --name $EH_HUB \
  --partition-count 4 \
  --message-retention 1

# Create consumer group for Stream Analytics
az eventhubs eventhub consumer-group create \
  --resource-group $RG \
  --namespace-name $EH_NAMESPACE \
  --eventhub-name $EH_HUB \
  --name "analytics-cg"

# Create consumer group for your application
az eventhubs eventhub consumer-group create \
  --resource-group $RG \
  --namespace-name $EH_NAMESPACE \
  --eventhub-name $EH_HUB \
  --name "app-cg"

# Get connection string for producer
EH_CONNECTION_STRING=$(az eventhubs namespace authorization-rule keys list \
  --resource-group $RG \
  --namespace-name $EH_NAMESPACE \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString -o tsv)

echo "Event Hub Connection String: $EH_CONNECTION_STRING"
echo "Save this for the producer script!"

# Create output storage account
az storage account create \
  --name $STORAGE_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2

az storage container create \
  --name output \
  --account-name $STORAGE_NAME
```

## Phase 2: Create Stream Analytics Job

```bash
# Create Stream Analytics job
az stream-analytics job create \
  --resource-group $RG \
  --job-name "asa-orders-aggregator" \
  --location $LOCATION \
  --output-error-policy Drop \
  --events-outoforder-policy Adjust \
  --events-outoforder-max-delay-in-seconds 5 \
  --events-late-arrival-max-delay-in-seconds 16 \
  --data-locale "en-US" \
  --compatibility-level "1.2" \
  --streaming-units 1

# Create input (Event Hub)
az stream-analytics input create \
  --resource-group $RG \
  --job-name "asa-orders-aggregator" \
  --input-name "orders-input" \
  --properties '{
    "type": "Stream",
    "datasource": {
      "type": "Microsoft.ServiceBus/EventHub",
      "properties": {
        "eventHubName": "'"$EH_HUB"'",
        "serviceBusNamespace": "'"$EH_NAMESPACE"'",
        "sharedAccessPolicyName": "RootManageSharedAccessKey",
        "sharedAccessPolicyKey": "'"$(az eventhubs namespace authorization-rule keys list --resource-group $RG --namespace-name $EH_NAMESPACE --name RootManageSharedAccessKey --query primaryKey -o tsv)"'",
        "consumerGroupName": "analytics-cg"
      }
    },
    "serialization": {
      "type": "Json",
      "properties": {"encoding": "UTF8"}
    }
  }'

# Create output (ADLS Gen2 / Blob Storage)
STORAGE_KEY=$(az storage account keys list \
  --account-name $STORAGE_NAME \
  --resource-group $RG \
  --query "[0].value" -o tsv)

az stream-analytics output create \
  --resource-group $RG \
  --job-name "asa-orders-aggregator" \
  --output-name "adls-output" \
  --datasource '{
    "type": "Microsoft.Storage/Blob",
    "properties": {
      "storageAccounts": [{"accountName": "'"$STORAGE_NAME"'", "accountKey": "'"$STORAGE_KEY"'"}],
      "container": "output",
      "pathPattern": "aggregated/{date}/{time}",
      "dateFormat": "yyyy/MM/dd",
      "timeFormat": "HH"
    }
  }' \
  --serialization '{"type": "Json", "properties": {"encoding": "UTF8", "format": "LineSeparated"}}'

# Create the transformation query
az stream-analytics transformation create \
  --resource-group $RG \
  --job-name "asa-orders-aggregator" \
  --transformation-name "main-query" \
  --streaming-units 1 \
  --saql "
    SELECT
        product,
        COUNT(*) AS order_count,
        SUM(CAST(amount AS float)) AS total_revenue,
        AVG(CAST(amount AS float)) AS avg_order_value,
        MIN(CAST(amount AS float)) AS min_order,
        MAX(CAST(amount AS float)) AS max_order,
        System.Timestamp() AS window_end
    INTO [adls-output]
    FROM [orders-input] TIMESTAMP BY event_time
    GROUP BY
        product,
        TumblingWindow(Duration(minute, 1))
  "

echo "Stream Analytics job configured."
```

## Phase 3: Run Producer

```bash
# Set environment variables for producer
export EVENT_HUB_CONNECTION_STRING="$EH_CONNECTION_STRING"
export EVENT_HUB_NAME="$EH_HUB"

# Start Stream Analytics job first
az stream-analytics job start \
  --resource-group $RG \
  --job-name "asa-orders-aggregator" \
  --output-start-mode JobStartTime

echo "Stream Analytics job starting (takes ~1 minute)..."
sleep 60

# Run the producer
cd code
pip install azure-eventhub
python producer.py

# Monitor Event Hub metrics
az monitor metrics list \
  --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.EventHub/namespaces/$EH_NAMESPACE" \
  --metric "IncomingMessages,OutgoingMessages,IncomingBytes" \
  --interval PT1M \
  --output table
```

## Phase 4: Verify Output in ADLS

```bash
# Wait for Stream Analytics to process (1-2 minutes after producer finishes)
sleep 120

# List output files
az storage blob list \
  --account-name $STORAGE_NAME \
  --container-name output \
  --output table

# Download and view output
az storage blob download \
  --account-name $STORAGE_NAME \
  --container-name output \
  --name "aggregated/$(date +%Y/%m/%d)/$(date +%H)/0_0.json" \
  --file /tmp/asa_output.json

cat /tmp/asa_output.json | python -m json.tool

# Check Stream Analytics job metrics
az stream-analytics job show \
  --resource-group $RG \
  --job-name "asa-orders-aggregator" \
  --query "{Status:jobState, LastOutput:lastOutputEventTime}" \
  --output table
```

## Phase 5: Query Results

```bash
# Query results using az storage blob
az storage blob list \
  --account-name $STORAGE_NAME \
  --container-name output \
  --prefix "aggregated/" \
  --query "[].{Name:name, Size:properties.contentLength, Modified:properties.lastModified}" \
  --output table

# Download all output files and aggregate
for blob in $(az storage blob list \
  --account-name $STORAGE_NAME \
  --container-name output \
  --prefix "aggregated/" \
  --query "[].name" -o tsv); do
  az storage blob download \
    --account-name $STORAGE_NAME \
    --container-name output \
    --name "$blob" \
    --file "/tmp/$(basename $blob)"
done

# Aggregate results with Python
python3 << 'EOF'
import json, glob

results = []
for f in glob.glob("/tmp/*.json"):
    with open(f) as fp:
        for line in fp:
            line = line.strip()
            if line:
                results.append(json.loads(line))

print(f"\nTotal windows processed: {len(results)}")
print(f"\nProduct Revenue Summary:")
print(f"{'Product':<20} {'Orders':>8} {'Revenue':>12} {'Avg Order':>12}")
print("-" * 55)

by_product = {}
for r in results:
    p = r.get("product", "Unknown")
    if p not in by_product:
        by_product[p] = {"orders": 0, "revenue": 0.0}
    by_product[p]["orders"] += r.get("order_count", 0)
    by_product[p]["revenue"] += r.get("total_revenue", 0.0)

for product, stats in sorted(by_product.items(), key=lambda x: -x[1]["revenue"]):
    avg = stats["revenue"] / stats["orders"] if stats["orders"] > 0 else 0
    print(f"{product:<20} {stats['orders']:>8} ${stats['revenue']:>11.2f} ${avg:>11.2f}")
EOF

# Stop Stream Analytics job to save cost
az stream-analytics job stop \
  --resource-group $RG \
  --job-name "asa-orders-aggregator"

# Cleanup
az group delete --name $RG --yes --no-wait
```

# Cosmos DB — Deep Dive: Partitioning, Consistency & Performance

## Cosmos DB Internals

```
Cosmos DB Architecture:
├── Account (global endpoint)
│   └── Database
│       └── Container (collection/table)
│           ├── Logical Partitions (same partition key)
│           └── Physical Partitions (up to 50GB, 10K RU/s each)

Request Units (RU):
  1 RU = cost to read a 1KB item
  Write ≈ 5x read cost
  Complex queries cost more RUs
  Provision RU/s or use serverless (pay per RU)

Indexing:
  All properties indexed by default
  Composite indexes for ORDER BY on multiple fields
  Spatial indexes for geospatial queries
  Exclude paths to reduce RU cost and storage
```

## Partition Key Design

```javascript
// GOOD partition keys:
// - High cardinality (many distinct values)
// - Even distribution (no hot partitions)
// - Used in most queries (avoid cross-partition)
// - Immutable (can't change after creation)

// Examples:
// userId    — good for user data
// tenantId  — good for multi-tenant SaaS
// productId — good for product catalog
// orderId   — good for orders

// BAD partition keys:
// status    — low cardinality (pending/active/done)
// country   — uneven (US has 10x more data)
// timestamp — sequential, creates hot partition

// Synthetic partition key (combine fields)
const item = {
  id: "order-123",
  partitionKey: `${userId}-${month}`,  // distribute by user + month
  userId: "user-456",
  month: "2024-01",
  amount: 99.99,
};

// Hierarchical partition keys (Cosmos DB for NoSQL)
// Allows up to 3 levels: /tenantId/userId/sessionId
```

## Consistency Levels in Practice

```javascript
const { CosmosClient } = require('@azure/cosmos');

const client = new CosmosClient({
  endpoint: process.env.COSMOS_ENDPOINT,
  key: process.env.COSMOS_KEY,
  consistencyLevel: 'Session',  // default
});

// Override per-request
const { resource } = await container.item(id, partitionKey).read({
  consistencyLevel: 'Strong',  // for financial reads
});

// Session consistency token (maintain read-your-writes)
const { resource: created, headers } = await container.items.create(item);
const sessionToken = headers['x-ms-session-token'];

// Use token in subsequent reads
const { resource: read } = await container.item(created.id, created.partitionKey).read({
  sessionToken,  // guarantees reading your own write
});
```

## Performance Optimization

```javascript
// 1. Point reads (cheapest — 1 RU for 1KB)
const { resource } = await container.item(id, partitionKey).read();

// 2. Queries with partition key (efficient)
const { resources } = await container.items.query({
  query: 'SELECT * FROM c WHERE c.userId = @userId AND c.status = @status',
  parameters: [
    { name: '@userId', value: userId },
    { name: '@status', value: 'active' },
  ],
}, {
  partitionKey: userId,  // single partition query
}).fetchAll();

// 3. Cross-partition query (expensive — avoid)
const { resources } = await container.items.query(
  'SELECT * FROM c WHERE c.status = "active"'
  // No partitionKey — scans all partitions
).fetchAll();

// 4. Bulk operations (efficient for large writes)
const { BulkOperationType } = require('@azure/cosmos');
const operations = items.map(item => ({
  operationType: BulkOperationType.Create,
  resourceBody: item,
}));
const results = await container.items.bulk(operations);

// 5. Change feed (react to changes efficiently)
const changeFeedIterator = container.items.getChangeFeedIterator({
  changeFeedStartFrom: ChangeFeedStartFrom.Beginning(),
  maxItemCount: 100,
});

while (changeFeedIterator.hasMoreResults) {
  const { result: changes } = await changeFeedIterator.readNext();
  for (const change of changes) {
    await processChange(change);
  }
}

// 6. Indexing policy optimization
const indexingPolicy = {
  indexingMode: 'consistent',
  automatic: true,
  includedPaths: [
    { path: '/userId/?', indexes: [{ kind: 'Range', dataType: 'String' }] },
    { path: '/createdAt/?', indexes: [{ kind: 'Range', dataType: 'Number' }] },
  ],
  excludedPaths: [
    { path: '/largeBlob/*' },  // exclude large fields not queried
    { path: '/_etag/?' },
  ],
  compositeIndexes: [
    [
      { path: '/userId', order: 'ascending' },
      { path: '/createdAt', order: 'descending' },
    ],
  ],
};
```

## Multi-Region Configuration

```bash
# Add read region
az cosmosdb update \
  --name cosmos-myapp-prod \
  --resource-group $RG \
  --locations regionName=eastus failoverPriority=0 isZoneRedundant=true \
  --locations regionName=westeurope failoverPriority=1 isZoneRedundant=true \
  --locations regionName=southeastasia failoverPriority=2 isZoneRedundant=false

# Enable multi-region writes (active-active)
az cosmosdb update \
  --name cosmos-myapp-prod \
  --resource-group $RG \
  --enable-multiple-write-locations true

# Configure automatic failover
az cosmosdb update \
  --name cosmos-myapp-prod \
  --resource-group $RG \
  --enable-automatic-failover true

# Manual failover (for testing)
az cosmosdb failover-priority-change \
  --name cosmos-myapp-prod \
  --resource-group $RG \
  --failover-policies eastus=0 westeurope=1
```

## Cosmos DB APIs

```
SQL (Core) API:    JSON documents, SQL-like queries. Most features.
MongoDB API:       MongoDB wire protocol. Migrate MongoDB apps.
Cassandra API:     CQL (Cassandra Query Language). Migrate Cassandra.
Gremlin API:       Graph database. Vertices and edges.
Table API:         Azure Table Storage compatible. Simple key-value.

Choose based on:
  New app:          SQL API (most features, best tooling)
  MongoDB migration: MongoDB API (minimal code changes)
  Cassandra migration: Cassandra API
  Graph data:       Gremlin API
  Simple key-value: Table API
```

## Interview Questions

### Q1: How do you choose a partition key for Cosmos DB?
**Answer:**
Good partition key has:
1. **High cardinality**: many distinct values (userId, orderId — not status, country)
2. **Even distribution**: avoid hot partitions (don't use timestamp alone)
3. **Used in queries**: include in WHERE clauses to avoid cross-partition queries
4. **Immutable**: can't change after item creation

For multi-tenant SaaS: `/tenantId` — each tenant gets own partition(s)
For user data: `/userId` — all user's data in same partition
For time-series: `/deviceId` — all device data together, query by device

### Q2: What happens when a Cosmos DB partition is full?
**Answer:**
Each logical partition has a 20GB limit. When full, you get a 413 error. Solutions:
1. Choose a better partition key with higher cardinality
2. Use synthetic partition key (combine fields)
3. Use hierarchical partition keys (up to 3 levels)
4. Archive old data to cheaper storage

### Q3: When would you use Cosmos DB Serverless vs Provisioned Throughput?
**Answer:**
- **Serverless**: Pay per RU consumed. No minimum cost. Best for: dev/test, sporadic workloads, new apps with unknown traffic.
- **Provisioned**: Reserve RU/s. Predictable performance. Best for: production, steady traffic, SLA requirements.
- **Autoscale**: Automatically scales between 10% and 100% of max RU/s. Best for: variable but predictable traffic patterns.

### Q4: How does Cosmos DB handle conflicts in multi-region write scenarios?
**Answer:**
With multi-region writes, concurrent writes to same item in different regions can conflict. Resolution policies:
1. **Last-Write-Wins (LWW)**: Default. Uses `_ts` (timestamp) or custom property. Highest value wins.
2. **Custom conflict resolution**: Write a stored procedure to handle conflicts programmatically.
3. **Manual**: Conflicts stored in conflict feed for application to resolve.
Best practice: design to avoid conflicts (partition by region, use append-only patterns).

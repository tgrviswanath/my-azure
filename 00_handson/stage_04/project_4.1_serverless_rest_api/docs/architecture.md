# Architecture — Project 4.1 Serverless REST API

## Diagram

```
Client
  │
  ▼
API Management (optional — rate limiting, auth, caching)
  │
  ▼
Azure Function App (Consumption Plan — scales to zero)
  ├── GET  /api/items       → list_items()
  ├── GET  /api/items/{id}  → get_item()
  ├── POST /api/items       → create_item()
  └── DELETE /api/items/{id}→ delete_item()
        │
        ▼
  Cosmos DB (Serverless)
    database: appdb
    container: items (partition key: /id)
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Consumption plan | Pay per execution, scales to zero |
| HTTP trigger | Function invoked by HTTP request |
| Cosmos DB Serverless | Pay per RU consumed, no provisioned throughput |
| Partition key | Distributes data across Cosmos DB partitions |

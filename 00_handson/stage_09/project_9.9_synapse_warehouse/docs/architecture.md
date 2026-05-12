# Architecture — Project 9.9 Synapse Data Warehouse

## Diagram

```
ADLS Gen2 (processed/orders/*.parquet)
    │ COPY INTO (Managed Identity auth)
    ▼
Synapse Dedicated SQL Pool (DW100c)
    │
    ├── fact_orders
    │     Distribution: HASH(order_id) — 60 distributions
    │     Index: CLUSTERED COLUMNSTORE
    │     Partitioned by: order_date
    │
    ├── dim_product
    │     Distribution: REPLICATE (small table)
    │     Index: CLUSTERED COLUMNSTORE
    │
    └── dim_date
          Distribution: REPLICATE
          Index: HEAP (small lookup table)
                │
                ▼
    Analytical Queries (MPP — massively parallel)
                │
                ▼
    Power BI / Synapse Studio / Azure Analysis Services
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Dedicated SQL Pool | Provisioned MPP data warehouse |
| DWU (Data Warehouse Units) | Scale compute up/down — DW100c to DW30000c |
| HASH distribution | Distribute rows by column value — avoids data movement |
| REPLICATE | Copy small tables to all nodes — avoids shuffle joins |
| CLUSTERED COLUMNSTORE | Default index — best for analytical queries |
| COPY INTO | Fast bulk load from ADLS/Blob — preferred over BCP |
| Pause/Resume | Stop billing when not in use |

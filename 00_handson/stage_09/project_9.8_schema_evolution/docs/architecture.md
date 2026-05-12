# Architecture — Project 9.8 Schema Evolution & Partitioning

## Diagram

```
Producer v1 (order_id, product, amount)
    │ write to Delta table
    ▼
Delta Lake (ADLS Gen2)
    ├── _delta_log/ (transaction log)
    │     ├── 00000000000000000000.json (v1 schema)
    │     └── 00000000000000000001.json (v2 schema — added customer_tier)
    │
    ├── product=Widget A/
    │     └── part-00000.parquet
    ├── product=Widget B/
    │     └── part-00000.parquet
    └── product=Widget C/
          └── part-00000.parquet

Producer v2 (order_id, product, amount, customer_tier)
    │ write with mergeSchema=True
    ▼
Delta Lake (schema evolved — customer_tier added)
    │
    ▼
Consumer (reads both v1 and v2 rows)
    ├── v1 rows: customer_tier = null
    └── v2 rows: customer_tier = "gold" / "silver"
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| mergeSchema | Allow adding new columns on write |
| Partition pruning | Skip partitions that don't match filter |
| OPTIMIZE | Compact small files into larger ones |
| ZORDER | Co-locate related data for faster queries |
| Time travel | Read previous versions with VERSION AS OF |
| Transaction log | `_delta_log/` records every change |

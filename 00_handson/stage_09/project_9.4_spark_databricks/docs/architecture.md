# Architecture — Project 9.4: Spark Processing on Azure Databricks

## ASCII Diagram

```
                    DATABRICKS SPARK ARCHITECTURE
                    ==============================

  STORAGE                   DATABRICKS WORKSPACE              OUTPUT
  ┌──────────────┐          ┌──────────────────────────┐     ┌──────────────┐
  │ ADLS Gen2    │          │                          │     │ ADLS Gen2    │
  │ raw/         │          │  Cluster (2 workers)     │     │ delta/       │
  │              │──mount──▶│  ┌────────────────────┐  │     │              │
  │ orders/      │          │  │ Driver Node        │  │     │ orders_delta/│
  │ 2024/01/     │          │  │ (Standard_DS3_v2)  │  │────▶│ _delta_log/  │
  │ *.csv        │          │  └────────────────────┘  │     │ year=2024/   │
  └──────────────┘          │  ┌──────┐  ┌──────┐      │     │   month=1/   │
                            │  │Work  │  │Work  │      │     │   *.parquet  │
  ┌──────────────┐          │  │er 1  │  │er 2  │      │     └──────────────┘
  │ Key Vault    │──secrets▶│  └──────┘  └──────┘      │
  │              │          │                          │     ┌──────────────┐
  │ sp-client-id │          │  PySpark Job:            │     │ Databricks   │
  │ sp-secret    │          │  1. Read CSV             │     │ SQL          │
  │ tenant-id    │          │  2. dropna(customer_id)  │────▶│              │
  └──────────────┘          │  3. cast(amount→decimal) │     │ SELECT *     │
                            │  4. agg daily revenue    │     │ FROM orders  │
                            │  5. write.delta()        │     │ VERSION AS   │
                            │  6. MERGE upsert         │     │ OF 0         │
                            │  7. OPTIMIZE + ZORDER    │     └──────────────┘
                            └──────────────────────────┘

  DELTA LAKE STRUCTURE
  ┌──────────────────────────────────────────────────────────────┐
  │ /mnt/delta/orders_delta/                                     │
  │ ├── _delta_log/                                              │
  │ │   ├── 00000000000000000000.json  (version 0 — initial)    │
  │ │   ├── 00000000000000000001.json  (version 1 — MERGE)      │
  │ │   └── 00000000000000000002.json  (version 2 — OPTIMIZE)   │
  │ ├── year=2024/                                               │
  │ │   ├── month=1/                                             │
  │ │   │   ├── part-00000-abc123.snappy.parquet                 │
  │ │   │   └── part-00001-def456.snappy.parquet                 │
  │ │   └── month=2/                                             │
  │ │       └── part-00000-ghi789.snappy.parquet                 │
  │ └── year=2023/                                               │
  │     └── month=12/                                            │
  │         └── part-00000-jkl012.snappy.parquet                 │
  └──────────────────────────────────────────────────────────────┘
```

## Key Concepts

| Concept | Description | Benefit |
|---|---|---|
| **Delta Lake** | Open-source storage layer with ACID transactions | No partial writes, consistent reads |
| **Delta Log** | JSON transaction log in `_delta_log/` | Tracks every change, enables time travel |
| **Partitioning** | Physical file organization by column values | Partition pruning = faster queries |
| **MERGE (Upsert)** | Insert new rows, update existing rows in one operation | Efficient incremental loads |
| **Time Travel** | Query historical versions with `VERSION AS OF n` | Audit, rollback, reproducibility |
| **OPTIMIZE** | Compact small files into larger ones | Faster reads (fewer file opens) |
| **ZORDER** | Co-locate related data in same files | Faster filtered queries |
| **Schema Evolution** | Add columns without breaking existing readers | `mergeSchema=True` option |
| **Auto Loader** | Incremental file ingestion from cloud storage | Efficient streaming ingestion |

## PySpark Transformation Pipeline

```
Read CSV (raw/orders/2024/01/*.csv)
    │
    ▼
Schema Inference / Explicit Schema
    │
    ▼
Data Cleaning:
  • dropna(subset=['order_id', 'customer_id'])  — remove rows with null keys
  • fillna({'status': 'unknown', 'region': 'unknown'})
  • filter(col('amount') > 0)  — remove invalid amounts
    │
    ▼
Type Casting:
  • amount: StringType → DecimalType(10, 2)
  • order_date: StringType → DateType
  • quantity: StringType → IntegerType
    │
    ▼
Feature Engineering:
  • total_amount = amount × quantity
  • year = year(order_date)
  • month = month(order_date)
    │
    ▼
Aggregation (daily revenue by product):
  • groupBy(order_date, product)
  • agg(sum(total_amount), count(*), avg(amount))
    │
    ▼
Write Delta Table:
  • format("delta")
  • mode("overwrite")  or  mode("append")
  • partitionBy("year", "month")
  • option("mergeSchema", "true")
    │
    ▼
MERGE (Upsert):
  • Match on order_id
  • Update if changed
  • Insert if new
    │
    ▼
OPTIMIZE + ZORDER BY (order_date, product)
```

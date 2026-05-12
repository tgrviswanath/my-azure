# Project 9.8 — Schema Evolution with Delta Lake on Databricks

## What This Does

Demonstrates how Delta Lake handles schema changes without breaking existing pipelines. Creates a Delta table with v1 schema, adds a new column (backward compatible), tests `mergeSchema=True` for automatic schema evolution, demonstrates partition pruning for performance, and shows OPTIMIZE + ZORDER for file compaction. Includes Delta time travel to query historical versions.

## Services Used

| Service | Purpose | SKU |
|---|---|---|
| Azure Databricks | Spark + Delta Lake runtime | Standard |
| ADLS Gen2 | Delta table storage | Standard LRS |
| Delta Lake | Schema evolution, time travel, ACID | Open source (included) |

## Architecture

```
SCHEMA EVOLUTION FLOW
======================

  Producer v1                    Delta Lake                    Consumer
  ┌──────────────┐               ┌──────────────────────┐     ┌──────────────┐
  │ order_id     │──write v1────▶│ Version 0            │────▶│ Reads v1     │
  │ amount       │               │ Schema:              │     │ schema fine  │
  │ product      │               │ order_id, amount,    │     └──────────────┘
  └──────────────┘               │ product              │
                                 └──────────────────────┘
  Producer v2                    ┌──────────────────────┐     ┌──────────────┐
  ┌──────────────┐               │ Version 1            │     │ Reads v2     │
  │ order_id     │──mergeSchema─▶│ Schema:              │────▶│ schema fine  │
  │ amount       │               │ order_id, amount,    │     │ (new col     │
  │ product      │               │ product,             │     │  nullable)   │
  │ customer_tier│               │ customer_tier (NEW)  │     └──────────────┘
  └──────────────┘               └──────────────────────┘
```

## How to Run

```bash
# Deploy Databricks workspace
cd terraform
terraform init
terraform apply -auto-approve

# Upload and run the PySpark script in Databricks
databricks workspace import code/schema_evolution_demo.py /Shared/schema_evolution --language PYTHON
databricks jobs run-now --job-id <job-id>
```

## Lessons Learned

- **mergeSchema is safe**: Adding a new nullable column with `mergeSchema=True` is backward compatible. Old readers see NULL for the new column.
- **Removing columns is breaking**: Delta doesn't support column removal by default. Use `overwriteSchema=True` to force it (destructive).
- **Partition pruning requires filter**: `WHERE year=2024` only prunes if `year` is a partition column. Filtering on non-partition columns still scans all files.
- **OPTIMIZE is not automatic**: Run OPTIMIZE periodically (weekly) to compact small files. Small files = slow queries.
- **ZORDER is not a sort**: ZORDER co-locates related data in the same files. It doesn't sort the entire table — it's a locality optimization.

## Code

See `code/schema_evolution_demo.py` — complete PySpark demo with v1 table creation, v2 column addition with mergeSchema, partition pruning, OPTIMIZE + ZORDER, and time travel.

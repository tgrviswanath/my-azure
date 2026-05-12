# Project 9.4 — Spark Processing on Azure Databricks

## What This Does

Processes large datasets using Apache Spark on Azure Databricks. Reads raw CSV data from ADLS Gen2, applies PySpark transformations (null cleaning, type casting, aggregations), writes Delta tables with year/month partitioning, and demonstrates Delta Lake's MERGE (upsert) capability for incremental loads. Includes a Delta time travel example to query historical versions.

## Services Used

| Service | Purpose | SKU |
|---|---|---|
| Azure Databricks Workspace | Managed Spark environment | Standard |
| Databricks Cluster | Spark compute (2 workers) | Standard_DS3_v2 |
| ADLS Gen2 | Raw data source + Delta table storage | Standard LRS |
| Azure Key Vault | Service principal credentials for ADLS mount | Standard |
| Delta Lake | ACID transactions, schema evolution, time travel | Open source (included) |

## Architecture

```
ADLS Gen2 (raw/)          DATABRICKS                    ADLS Gen2 (delta/)
┌──────────────┐          ┌──────────────────────┐      ┌──────────────────┐
│ orders/      │          │ PySpark Notebook      │      │ orders_delta/    │
│ 2024/01/     │──mount──▶│                       │─────▶│ _delta_log/      │
│ *.csv        │          │ 1. Read CSV           │      │ year=2024/       │
└──────────────┘          │ 2. Clean nulls        │      │   month=01/      │
                          │ 3. Cast types         │      │   *.parquet      │
                          │ 4. Aggregate daily    │      └──────────────────┘
                          │    revenue            │
                          │ 5. Write Delta        │      ┌──────────────────┐
                          │ 6. MERGE upsert       │─────▶│ Databricks SQL   │
                          │ 7. Time travel        │      │ SELECT * FROM    │
                          └──────────────────────┘      │ orders_delta     │
                                                         │ VERSION AS OF 0  │
                                                         └──────────────────┘
```

## How to Run

### Prerequisites
```bash
az login
export RG="rg-databricks-lab"
export LOCATION="eastus"
```

### Deploy
```bash
cd terraform
terraform init
terraform apply -auto-approve

# Upload sample data to ADLS
az storage blob upload-batch \
  --account-name <storage-name> \
  --destination raw/orders/2024/01 \
  --source ./sample_data/

# In Databricks workspace:
# 1. Create cluster (2 workers, Standard_DS3_v2)
# 2. Upload spark_job.py as notebook
# 3. Run notebook
```

### Run PySpark Job
```bash
# Via Databricks CLI
databricks workspace import code/spark_job.py /Shared/spark_job --language PYTHON
databricks jobs create --json @job_config.json
databricks jobs run-now --job-id <job-id>
```

## Lessons Learned

- **Delta Lake is worth it**: ACID transactions prevent partial writes. If your Spark job fails halfway, the Delta log ensures readers see a consistent state.
- **Partition pruning**: Partitioning by year/month means queries with `WHERE year=2024 AND month=1` only scan relevant files — 10x faster on large datasets.
- **MERGE is powerful**: Delta's MERGE handles upserts in one operation. Without it, you'd need to read, deduplicate, and rewrite entire partitions.
- **ADLS mount vs direct access**: Mounting with service principal is convenient but requires Key Vault. For production, use Unity Catalog with managed identities instead.
- **Cluster auto-termination**: Always set `autotermination_minutes` to avoid idle cluster costs.

## Code

See `code/spark_job.py` — complete PySpark script with CSV read, null cleaning, type casting, daily revenue aggregation, Delta write with partitioning, MERGE upsert, and time travel query.

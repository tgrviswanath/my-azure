# Project 9.2 — Azure Data Factory ETL Pipeline

## What This Does

Builds a production-grade ETL pipeline using Azure Data Factory. Copies raw CSV files from ADLS Gen2, applies transformations using Mapping Data Flows (type casting, deduplication, aggregation), and loads the results into a Synapse Analytics dedicated SQL pool. Demonstrates linked services, datasets, pipeline triggers, and monitoring via the ADF SDK.

## Services Used

| Service | Purpose | Tier |
|---|---|---|
| Azure Data Factory | ETL orchestration and data movement | Standard |
| ADLS Gen2 | Source (raw CSV) and sink (processed Parquet) | Standard LRS |
| Synapse Analytics | Target data warehouse | Dedicated SQL Pool DW100c |
| Azure SQL Database | Optional staging database | General Purpose |
| Azure Key Vault | Store linked service credentials | Standard |
| Azure Monitor | Pipeline run alerts and metrics | Included |

## Architecture

```
ADLS Gen2 (raw/)
    │
    │  CSV files
    ▼
┌─────────────────────────────────────────────────────────┐
│              Azure Data Factory Pipeline                │
│                                                         │
│  ┌─────────────┐    ┌──────────────────┐               │
│  │  Copy       │    │  Mapping Data    │               │
│  │  Activity   │───▶│  Flow            │               │
│  │  (CSV→lake) │    │  - Cast types    │               │
│  └─────────────┘    │  - Deduplicate   │               │
│                     │  - Aggregate     │               │
│                     │  - Filter nulls  │               │
│                     └────────┬─────────┘               │
└──────────────────────────────┼──────────────────────── ┘
                               │
               ┌───────────────┴───────────────┐
               ▼                               ▼
    ADLS Gen2 (processed/)          Synapse SQL Pool
    Parquet, partitioned            Fact/Dim tables
    by year/month                   (COPY INTO)
```

## How to Run

```bash
# 1. Navigate to project
cd D:\1.projects\AI\my-azure\00_handson\stage_09\project_9.2_adf_etl

# 2. Deploy infrastructure
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 3. Install Python dependencies
pip install azure-mgmt-datafactory azure-identity azure-mgmt-resource

# 4. Set environment variables
set AZURE_SUBSCRIPTION_ID=<your-subscription-id>
set AZURE_RESOURCE_GROUP=rg-adf-etl-dev
set AZURE_DATA_FACTORY_NAME=<adf-name-from-terraform-output>
set AZURE_TENANT_ID=<your-tenant-id>
set AZURE_CLIENT_ID=<your-client-id>
set AZURE_CLIENT_SECRET=<your-client-secret>
set ADLS_ACCOUNT_NAME=<storage-account-name>
set SYNAPSE_SERVER=<synapse-server>.sql.azuresynapse.net
set SYNAPSE_DATABASE=sqldw

# 5. Trigger the pipeline
cd ../code
python adf_trigger.py

# 6. Monitor in ADF Studio
# https://adf.azure.com → Monitor → Pipeline Runs

# 7. Cleanup
cd ../terraform
terraform destroy
```

## Lessons Learned

- Mapping Data Flows run on a Spark cluster that ADF spins up on demand. Cold start takes 3–5 minutes. Use debug mode in ADF Studio to keep the cluster warm during development.
- Linked services should reference Key Vault secrets rather than embedding credentials. Use ADF's managed identity to access Key Vault — no secrets in ARM templates.
- Pipeline parameters make pipelines reusable. Pass `source_path`, `sink_path`, and `run_date` as parameters rather than hardcoding paths.
- Use `Copy Activity` for simple data movement (no transformation). Use `Data Flow` only when you need transformation logic — Data Flows are significantly more expensive.
- Trigger types: Schedule (cron), Tumbling Window (backfill-friendly), Event (blob created), Manual. Use Tumbling Window for daily ETL — it handles late-arriving data and backfill naturally.
- Monitor pipeline runs via `azure-mgmt-datafactory` SDK to build custom alerting beyond what ADF Monitor provides.
- Data Flow partitioning: set partition count to match your data volume. Default 128 partitions is wasteful for small datasets — use 8–16 for dev.

## Code

See `code/adf_trigger.py` for the full Python implementation using `azure-mgmt-datafactory`.

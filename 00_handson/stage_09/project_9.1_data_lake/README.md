# Project 9.1 — Azure Data Lake Storage Gen2

## What This Does

Provisions an Azure Data Lake Storage Gen2 account with hierarchical namespace (HNS) enabled. Creates a structured zone-based layout (raw, processed, curated, archive) for a medallion architecture. Integrates with Azure Purview for data cataloging and Synapse Analytics for querying. Demonstrates ACL-based access control at the directory level.

## Services Used

| Service | Purpose | Tier |
|---|---|---|
| ADLS Gen2 | Primary data lake storage with HNS | Standard LRS |
| Azure Purview | Data catalog and lineage tracking | Standard |
| Synapse Analytics | Serverless SQL queries over lake | Serverless |
| Azure Data Factory | ETL orchestration | Standard |
| Azure Active Directory | Identity and ACL management | Included |

## Architecture

```
Data Sources
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│              ADLS Gen2 (HNS Enabled)                    │
│                                                         │
│  ┌──────────┐  ┌───────────┐  ┌─────────┐  ┌────────┐ │
│  │  raw/    │  │processed/ │  │curated/ │  │archive/│ │
│  │ (Bronze) │  │ (Silver)  │  │ (Gold)  │  │        │ │
│  └──────────┘  └───────────┘  └─────────┘  └────────┘ │
└─────────────────────────────────────────────────────────┘
         │               │              │
         ▼               ▼              ▼
    ADF ETL         ADF ETL        Synapse SQL
    (ingest)      (transform)      (analytics)
         │               │              │
         └───────────────┴──────────────┘
                         │
                         ▼
                  Azure Purview
               (catalog + lineage)
```

## How to Run

```bash
# 1. Clone and navigate
cd D:\1.projects\AI\my-azure\00_handson\stage_09\project_9.1_data_lake

# 2. Login to Azure
az login
az account set --subscription "<your-subscription-id>"

# 3. Deploy infrastructure
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 4. Install Python dependencies
pip install azure-storage-file-datalake azure-identity azure-mgmt-storage

# 5. Set environment variables
set AZURE_STORAGE_ACCOUNT_NAME=<your-storage-account>
set AZURE_TENANT_ID=<your-tenant-id>
set AZURE_CLIENT_ID=<your-client-id>
set AZURE_CLIENT_SECRET=<your-client-secret>

# 6. Run the data lake setup script
cd ../code
python data_lake_setup.py

# 7. Verify structure in Azure Portal
# Storage Account → Containers → raw, processed, curated, archive

# 8. Cleanup
cd ../terraform
terraform destroy
```

## Lessons Learned

- HNS (Hierarchical Namespace) must be enabled at account creation — it cannot be toggled after the fact. Plan your storage account architecture before provisioning.
- POSIX-style ACLs on ADLS Gen2 directories allow fine-grained access control per service principal, unlike flat blob storage which only supports container-level RBAC.
- The medallion architecture (raw → processed → curated) maps naturally to ADLS Gen2 zones. Keep raw data immutable — never overwrite source files.
- Purview scanning requires a managed identity with `Storage Blob Data Reader` on the ADLS account. Grant this before triggering a scan.
- Synapse serverless SQL can query Parquet files in ADLS directly using `OPENROWSET` — no data movement needed for ad-hoc analytics.
- LRS (Locally Redundant Storage) is sufficient for dev/test. Use ZRS or GRS for production workloads.

## Code

See `code/data_lake_setup.py` for the full Python implementation using `azure-storage-file-datalake`.

# Architecture — Project 9.1 Azure Data Lake Storage Gen2

## Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         DATA SOURCES                                    │
│                                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                 │
│  │  On-Premises │  │  SaaS Apps   │  │  IoT Devices │                 │
│  │  Databases   │  │  (Salesforce)│  │  (Telemetry) │                 │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘                 │
└─────────┼─────────────────┼─────────────────┼───────────────────────── ┘
          │                 │                 │
          └─────────────────┼─────────────────┘
                            │  ADF / Event Hubs / SFTP
                            ▼
┌─────────────────────────────────────────────────────────────────────────┐
│              ADLS Gen2 — Hierarchical Namespace Enabled                 │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  raw/  (Bronze Zone — Immutable Source of Truth)                │   │
│  │  ├── orders/year=2024/month=01/orders_20240101.csv              │   │
│  │  ├── customers/year=2024/month=01/customers_20240101.csv        │   │
│  │  └── products/year=2024/month=01/products_20240101.json         │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                            │                                            │
│                     ADF Data Flow                                       │
│                     (cleanse, dedupe)                                   │
│                            │                                            │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  processed/  (Silver Zone — Cleaned, Typed, Partitioned)        │   │
│  │  ├── orders/year=2024/month=01/part-00001.parquet               │   │
│  │  ├── customers/year=2024/month=01/part-00001.parquet            │   │
│  │  └── products/year=2024/month=01/part-00001.parquet             │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                            │                                            │
│                     Databricks / Synapse                                │
│                     (aggregate, join)                                   │
│                            │                                            │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  curated/  (Gold Zone — Business-Ready Aggregates)              │   │
│  │  ├── daily_revenue/year=2024/month=01/revenue.parquet           │   │
│  │  └── customer_segments/segment=premium/customers.parquet        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  archive/  (Cold Storage — Data > 90 days)                      │   │
│  │  └── orders/year=2023/...                                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
          │                 │                 │
          ▼                 ▼                 ▼
  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
  │Azure Purview │  │   Synapse    │  │  Databricks  │
  │(catalog +    │  │  Serverless  │  │  (PySpark    │
  │ lineage)     │  │  SQL Pool    │  │   jobs)      │
  └──────────────┘  └──────────────┘  └──────────────┘
                            │
                            ▼
                    ┌──────────────┐
                    │   Power BI   │
                    │  Dashboards  │
                    └──────────────┘
```

## Key Concepts

| Concept | Description | Why It Matters |
|---|---|---|
| Hierarchical Namespace (HNS) | Enables true directory semantics with atomic rename operations | Required for POSIX ACLs and efficient directory operations at scale |
| Medallion Architecture | Bronze (raw) → Silver (processed) → Gold (curated) zones | Separates concerns, enables reprocessing from source, improves data quality progressively |
| POSIX ACLs | File/directory-level permissions using user, group, other model | Fine-grained access control without needing separate storage accounts per team |
| Atomic Rename | Directory rename is O(1) regardless of file count | Critical for ETL patterns that write to temp directory then rename to final path |
| Partition Pruning | Organize data by year/month/day in directory structure | Synapse and Databricks skip irrelevant partitions, reducing query cost by 10–100x |
| Lifecycle Management | Automatically tier data from Hot → Cool → Archive | Reduces storage cost for aging data without manual intervention |
| Managed Identity | Azure AD identity for services (no credentials in code) | Eliminates secret management; Purview and Synapse use MI to access ADLS |
| Data Lineage | Purview tracks data flow from source to consumption | Enables impact analysis — know which reports break if a source table changes |
| Zone Isolation | Each zone has separate ACLs and lifecycle policies | Prevents raw data corruption; processed zone can be rebuilt from raw at any time |
| Soft Delete | Retain deleted files for configurable retention period | Recovery from accidental deletes without backup infrastructure |

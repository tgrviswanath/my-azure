# Architecture — Project 9.2: Azure Data Factory ETL Pipeline

## ASCII Diagram

```
                    ADF ETL PIPELINE ARCHITECTURE
                    ==============================

  SOURCE                    TRANSFORM                    SINK
  ┌──────────────┐          ┌──────────────────────┐    ┌──────────────────┐
  │ ADLS Gen2    │          │ Azure Data Factory   │    │ ADLS Gen2        │
  │ raw/         │          │                      │    │ processed/       │
  │              │          │  ┌────────────────┐  │    │                  │
  │ orders/      │──Copy───▶│  │ Copy Activity  │──┼───▶│ orders/          │
  │ 2024/01/     │  Activity│  │ CSV → Parquet  │  │    │ (Parquet/Snappy) │
  │ *.csv        │          │  └────────────────┘  │    └──────────────────┘
  └──────────────┘          │                      │
                            │  ┌────────────────┐  │    ┌──────────────────┐
                            │  │ Data Flow      │  │    │ Synapse SQL Pool │
                            │  │ (Spark-based)  │──┼───▶│                  │
                            │  │                │  │    │ dbo.orders_fact  │
                            │  │ 1. Filter      │  │    │ dbo.daily_rev    │
                            │  │    completed   │  │    └──────────────────┘
                            │  │ 2. Cast types  │  │
                            │  │ 3. Aggregate   │  │
                            │  │    by product  │  │
                            │  └────────────────┘  │
                            │                      │
                            │  ┌────────────────┐  │
                            │  │ Schedule       │  │
                            │  │ Trigger        │  │
                            │  │ Daily 02:00 UTC│  │
                            │  └────────────────┘  │
                            └──────────────────────┘

  MONITORING
  ┌──────────────────────────────────────────────────────────────┐
  │ ADF Monitor → Pipeline Runs → Activity Runs → Data Preview  │
  │ Azure Monitor → Alerts on pipeline failure                  │
  │ Log Analytics → ADF diagnostic logs                         │
  └──────────────────────────────────────────────────────────────┘

  LINKED SERVICES
  ┌──────────────────────────────────────────────────────────────┐
  │ ls_adls_source    → ADLS Gen2 (connection string / MSI)     │
  │ ls_synapse_sink   → Synapse SQL Pool (SQL auth / MSI)       │
  │ ls_keyvault       → Key Vault (for secrets)                 │
  └──────────────────────────────────────────────────────────────┘
```

## Key Concepts

| Concept | Description | When to Use |
|---|---|---|
| **Copy Activity** | Moves data between stores with optional schema mapping | Simple CSV → Parquet, no transformation needed |
| **Data Flow** | Visual Spark-based transformation (filter, join, aggregate) | Complex transformations, type casting, deduplication |
| **Linked Service** | Connection definition (credentials + endpoint) | One per data store |
| **Dataset** | Schema + location definition pointing to a Linked Service | One per table/file/container |
| **Pipeline** | Orchestration of activities with control flow | Sequence of Copy + Data Flow + stored procedures |
| **Trigger** | Schedule or event that starts a pipeline | Daily schedule, blob arrival event, tumbling window |
| **Integration Runtime** | Compute that executes activities | Azure IR (cloud), Self-hosted IR (on-prem), SSIS IR |
| **DIU** | Data Integration Unit — parallel copy compute unit | More DIUs = faster copy, higher cost |
| **Mapping Data Flow** | Visual ETL with Spark execution | Filter, join, aggregate, pivot, window functions |

## Data Flow Transformation Logic

```
Source (CSV)
    │
    ▼
Filter: status == 'completed'
    │
    ▼
DerivedColumn:
  amount_usd = toDecimal(amount, 10, 2)
  order_year  = year(toDate(order_date, 'yyyy-MM-dd'))
  order_month = month(toDate(order_date, 'yyyy-MM-dd'))
    │
    ▼
Aggregate (group by product, order_year, order_month):
  total_revenue = sum(amount_usd)
  order_count   = count()
  avg_order     = avg(amount_usd)
    │
    ▼
Sink (Parquet, partitioned by order_year/order_month)
```

## Pipeline Run States

```
Queued → InProgress → Succeeded
                    → Failed → (retry logic)
                    → Cancelled
```

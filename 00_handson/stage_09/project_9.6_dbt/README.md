# Project 9.6 — dbt Transformation Pipeline on Azure Synapse

## What This Does

Implements a full dbt (data build tool) transformation pipeline on Azure Synapse Analytics. Transforms raw order data through three layers: staging (clean and rename raw tables), intermediate (enrich with business logic), and mart (aggregated fact tables for BI). Includes dbt tests for data quality and `dbt docs generate` for auto-generated data documentation.

## Services Used

| Service | Purpose | SKU |
|---|---|---|
| Azure Synapse Analytics | SQL transformation engine | Dedicated SQL Pool DW100c |
| ADLS Gen2 | Raw data source | Standard LRS |
| dbt-synapse | dbt adapter for Synapse | Open source |
| dbt Core | Transformation framework | Open source (free) |

## Architecture

```
RAW TABLES                STAGING              INTERMEDIATE           MART
(Synapse external         (dbt models)         (dbt models)           (dbt models)
 or COPY INTO)
┌──────────────┐         ┌──────────────┐     ┌──────────────────┐   ┌──────────────────┐
│ raw.orders   │────────▶│ stg_orders   │────▶│ int_orders_      │──▶│ fct_daily_       │
│              │         │              │     │ enriched         │   │ revenue          │
│ order_id     │         │ order_id     │     │                  │   │                  │
│ cust_id      │         │ customer_id  │     │ + customer_tier  │   │ order_date       │
│ prod         │         │ product_name │     │ + revenue_band   │   │ product_name     │
│ amt          │         │ amount_usd   │     │ + days_to_ship   │   │ total_revenue    │
│ ord_dt       │         │ order_date   │     │ + is_repeat_cust │   │ order_count      │
│ stat         │         │ status       │     │                  │   │ avg_order_value  │
└──────────────┘         └──────────────┘     └──────────────────┘   └──────────────────┘
```

## How to Run

### Prerequisites
```bash
pip install dbt-synapse
az login
```

### Deploy
```bash
cd terraform
terraform init
terraform apply -auto-approve

# Configure dbt
cd dbt_project
dbt debug  # Test connection

# Run models
dbt run
dbt test
dbt docs generate
dbt docs serve  # Open http://localhost:8080
```

## Lessons Learned

- **dbt is SQL-first**: If your team knows SQL, they can write dbt models. No Python required for transformations.
- **Materialization matters**: Use `view` for staging (no storage cost), `table` for marts (fast queries), `incremental` for large fact tables.
- **Tests are free**: `dbt test` runs SQL assertions. Add `not_null`, `unique`, `accepted_values` to every model — it's just YAML config.
- **Synapse DW100c is slow**: The smallest Synapse pool is not fast. Pause it when not in use — it charges by the hour.
- **dbt docs are excellent**: `dbt docs generate` creates a full data catalog with lineage graph. Share with stakeholders.

## Code

See `dbt_project/` — complete dbt project with staging, intermediate, and mart models, plus `dbt_project.yml` configuration.

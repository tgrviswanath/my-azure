# Architecture — Project 9.6: dbt Transformation Pipeline on Azure Synapse

## ASCII Diagram

```
                    DBT TRANSFORMATION ARCHITECTURE
                    ================================

  SOURCE                  STAGING              INTERMEDIATE           MART
  ┌──────────────┐        ┌──────────────┐     ┌──────────────────┐   ┌──────────────────┐
  │ raw.orders   │        │ stg_orders   │     │ int_orders_      │   │ fct_daily_       │
  │ (Synapse     │──ref──▶│ (VIEW)       │────▶│ enriched         │──▶│ revenue          │
  │  external    │        │              │     │ (TABLE)          │   │ (TABLE)          │
  │  table or    │        │ Renames cols │     │                  │   │                  │
  │  COPY INTO)  │        │ Casts types  │     │ Adds:            │   │ Aggregates:      │
  └──────────────┘        │ Filters bad  │     │ customer_tier    │   │ daily_revenue    │
                          │ data         │     │ revenue_band     │   │ order_count      │
  ┌──────────────┐        └──────────────┘     │ is_repeat_cust   │   │ avg_order_value  │
  │ raw.customers│                             │ days_since_first │   │ unique_customers │
  │ (optional    │──ref──▶                     └──────────────────┘   └──────────────────┘
  │  join)       │
  └──────────────┘

  DBT PROJECT STRUCTURE
  ┌──────────────────────────────────────────────────────────────┐
  │ dbt_project/                                                 │
  │ ├── dbt_project.yml          (project config)               │
  │ ├── profiles.yml             (connection config, in ~/.dbt/) │
  │ ├── packages.yml             (dbt-utils, dbt-expectations)   │
  │ ├── models/                                                  │
  │ │   ├── sources/                                             │
  │ │   │   └── sources.yml      (source definitions + tests)   │
  │ │   ├── staging/                                             │
  │ │   │   ├── stg_orders.sql   (VIEW — clean raw data)        │
  │ │   │   └── schema.yml       (column tests + descriptions)  │
  │ │   ├── intermediate/                                        │
  │ │   │   └── int_orders_enriched.sql  (TABLE — business logic)│
  │ │   └── marts/                                               │
  │ │       ├── fct_daily_revenue.sql    (TABLE — aggregated)   │
  │ │       └── schema.yml                                       │
  │ ├── tests/                   (custom SQL tests)              │
  │ ├── macros/                  (reusable SQL macros)           │
  │ └── target/                  (compiled SQL, run artifacts)   │
  └──────────────────────────────────────────────────────────────┘

  LINEAGE GRAPH (dbt docs)
  ┌──────────────────────────────────────────────────────────────┐
  │                                                              │
  │  [source: raw.orders] ──▶ [stg_orders] ──▶ [int_orders_    │
  │                                              enriched]       │
  │                                                  │           │
  │                                                  ▼           │
  │                                          [fct_daily_revenue] │
  │                                                              │
  └──────────────────────────────────────────────────────────────┘
```

## Key Concepts

| Concept | Description | Example |
|---|---|---|
| **Model** | A SQL SELECT statement saved as a `.sql` file | `stg_orders.sql` |
| **Materialization** | How dbt persists the model (view, table, incremental) | `{{ config(materialized='table') }}` |
| **ref()** | Reference another model (builds dependency graph) | `FROM {{ ref('stg_orders') }}` |
| **source()** | Reference a raw source table | `FROM {{ source('raw', 'orders') }}` |
| **Test** | SQL assertion that validates data | `not_null`, `unique`, `accepted_values` |
| **Schema YAML** | Column descriptions and test definitions | `schema.yml` |
| **Macro** | Reusable Jinja SQL function | `{{ dbt_utils.date_spine(...) }}` |
| **Incremental** | Only process new/changed rows | `WHERE updated_at > '{{ max_loaded_at }}'` |
| **Snapshot** | Track slowly changing dimensions (SCD Type 2) | `dbt snapshot` |
| **Seed** | Load CSV files as tables | `dbt seed` |

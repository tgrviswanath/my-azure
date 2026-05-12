# Project 9.9 — Synapse Data Warehouse

## What This Does
Builds a data warehouse using Azure Synapse Analytics Dedicated SQL Pool. Loads Parquet data from ADLS Gen2 using COPY INTO, then runs analytical queries.

## Services Used
| Service | Purpose |
|---------|---------|
| Synapse Analytics | Workspace + Dedicated SQL Pool |
| ADLS Gen2 | Source data (Parquet files) |
| Synapse Pipelines | Orchestrate data loading |
| Power BI | Visualization (optional) |

## Architecture
```
ADLS Gen2 (Parquet, partitioned)
    │ COPY INTO (PolyBase)
    ▼
Synapse Dedicated SQL Pool (DW100c)
    ├── Fact table: fact_orders (hash distributed)
    ├── Dimension: dim_date (replicated)
    └── Dimension: dim_product (replicated)
          │ analytical queries
          ▼
    Power BI / Synapse Studio
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve
# IMPORTANT: Pause pool when not in use!
az synapse sql pool pause --name sqldw --workspace-name synapse-handson --resource-group rg-synapse
python code/synapse_operations.py
```

## Lessons Learned
- DW100c = 1 compute node, 60 distributions — cheapest tier
- PAUSE the pool when not in use — saves ~$1.20/hour
- COPY INTO is faster than PolyBase external tables for one-time loads
- Hash distribution on high-cardinality column (order_id) avoids data skew
- Replicated tables for small dimensions — avoids shuffle joins

## Code

### `code/synapse_operations.py` — Connect, load, and query Synapse

```bash
pip install pyodbc
export SYNAPSE_SERVER=synapse-handson.sql.azuresynapse.net
export SYNAPSE_DB=sqldw
export SYNAPSE_USER=sqladmin
export SYNAPSE_PASS=YourPass123!
python code/synapse_operations.py
```

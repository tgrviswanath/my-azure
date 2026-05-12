# Steps — Project 9.9 Synapse Data Warehouse

## Phase 1 — Create Synapse Workspace + SQL Pool

```bash
cd terraform && terraform init && terraform apply -auto-approve

# Get connection details
terraform output synapse_sql_endpoint
```

---

## Phase 2 — Create Tables

```sql
-- Connect via Synapse Studio or sqlcmd
-- Create fact table (hash distributed on order_id)
CREATE TABLE fact_orders (
    order_id     NVARCHAR(50)   NOT NULL,
    product      NVARCHAR(100)  NOT NULL,
    customer_id  NVARCHAR(50),
    amount       DECIMAL(10,2)  NOT NULL,
    order_date   DATE           NOT NULL,
    year         INT,
    month        INT
)
WITH (
    DISTRIBUTION = HASH(order_id),
    CLUSTERED COLUMNSTORE INDEX
);

-- Create dimension table (replicated — small table)
CREATE TABLE dim_product (
    product_id   INT IDENTITY(1,1),
    product_name NVARCHAR(100),
    category     NVARCHAR(50),
    unit_price   DECIMAL(10,2)
)
WITH (DISTRIBUTION = REPLICATE);
```

---

## Phase 3 — COPY INTO from ADLS

```sql
-- Load data from ADLS Gen2 Parquet files
COPY INTO fact_orders
FROM 'https://stadlhandson001.dfs.core.windows.net/processed/orders/*.parquet'
WITH (
    FILE_TYPE = 'PARQUET',
    CREDENTIAL = (IDENTITY = 'Managed Identity')
);

SELECT COUNT(*) FROM fact_orders;
```

---

## Phase 4 — Run Analytical Queries

```sql
-- Daily revenue trend
SELECT order_date, SUM(amount) AS daily_revenue
FROM fact_orders
GROUP BY order_date
ORDER BY order_date;

-- Top 10 products by revenue
SELECT product, SUM(amount) AS total_revenue, COUNT(*) AS order_count
FROM fact_orders
GROUP BY product
ORDER BY total_revenue DESC;
```

---

## Phase 5 — Pause Pool to Save Cost

```bash
# IMPORTANT: Pause when not in use (~$1.20/hour savings)
az synapse sql pool pause \
  --name sqldw \
  --workspace-name synapse-handson-001 \
  --resource-group rg-synapse

# Resume when needed
az synapse sql pool resume \
  --name sqldw \
  --workspace-name synapse-handson-001 \
  --resource-group rg-synapse
```

---

## Screenshots to Take
- [ ] Synapse workspace created
- [ ] SQL Pool in Online state
- [ ] COPY INTO completed with row count
- [ ] Analytical query results
- [ ] Pool paused to save cost

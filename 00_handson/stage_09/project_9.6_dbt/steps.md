# Steps — Project 9.6: dbt Transformation Pipeline on Azure Synapse

## Phase 1: Install dbt-synapse

```bash
# Create virtual environment
python -m venv dbt-env
source dbt-env/bin/activate  # Linux/Mac
# dbt-env\Scripts\activate   # Windows

# Install dbt with Synapse adapter
pip install dbt-synapse

# Verify installation
dbt --version
# dbt Core: 1.7.x
# Installed adapters: synapse

# Install additional packages
pip install dbt-utils dbt-expectations

# Create dbt project
dbt init dbt_project
cd dbt_project
```

## Phase 2: Configure profiles.yml

```bash
# Create ~/.dbt/profiles.yml
mkdir -p ~/.dbt
cat > ~/.dbt/profiles.yml << 'EOF'
orders_pipeline:
  target: dev
  outputs:
    dev:
      type: synapse
      driver: 'ODBC Driver 18 for SQL Server'
      server: "synapse-dbt-lab.sql.azuresynapse.net"
      port: 1433
      database: "sqldw"
      schema: "dbt_dev"
      user: "sqladmin"
      password: "{{ env_var('DBT_SYNAPSE_PASSWORD') }}"
      authentication: SqlPassword
      encrypt: true
      trust_cert: false
      retries: 3

    prod:
      type: synapse
      driver: 'ODBC Driver 18 for SQL Server'
      server: "synapse-dbt-lab.sql.azuresynapse.net"
      port: 1433
      database: "sqldw"
      schema: "dbt_prod"
      user: "sqladmin"
      password: "{{ env_var('DBT_SYNAPSE_PASSWORD') }}"
      authentication: SqlPassword
      encrypt: true
      trust_cert: false
      retries: 3
EOF

# Set password environment variable
export DBT_SYNAPSE_PASSWORD="P@ssw0rd1234!"

# Test connection
cd dbt_project
dbt debug

# Expected output:
# Connection test: OK connection ok
```

## Phase 3: Create Staging Models

```bash
# Create directory structure
mkdir -p models/staging
mkdir -p models/intermediate
mkdir -p models/marts
mkdir -p models/sources

# Create source definition
cat > models/sources/sources.yml << 'EOF'
version: 2

sources:
  - name: raw
    database: sqldw
    schema: raw
    tables:
      - name: orders
        description: "Raw orders from ADLS COPY INTO"
        columns:
          - name: order_id
            description: "Unique order identifier"
            tests:
              - not_null
              - unique
          - name: customer_id
            tests: [not_null]
          - name: amount
            tests: [not_null]
EOF

# The actual SQL models are in dbt_project/models/ (see code section)
# Run dbt compile to verify SQL
dbt compile --select staging.stg_orders

# View compiled SQL
cat target/compiled/orders_pipeline/models/staging/stg_orders.sql
```

## Phase 4: dbt run

```bash
# Run all models in dependency order
dbt run

# Expected output:
# 1 of 3 START sql view model dbt_dev.stg_orders ................. [RUN]
# 1 of 3 OK created sql view model dbt_dev.stg_orders ............ [OK in 2.34s]
# 2 of 3 START sql table model dbt_dev.int_orders_enriched ........ [RUN]
# 2 of 3 OK created sql table model dbt_dev.int_orders_enriched ... [OK in 5.12s]
# 3 of 3 START sql table model dbt_dev.fct_daily_revenue .......... [RUN]
# 3 of 3 OK created sql table model dbt_dev.fct_daily_revenue ..... [OK in 3.89s]
# Finished running 3 models in 11.35s.
# Completed successfully

# Run specific model and its dependencies
dbt run --select +fct_daily_revenue  # + means include upstream

# Run with full refresh (recreate tables)
dbt run --full-refresh

# Run incremental model
dbt run --select fct_daily_revenue --vars '{"execution_date": "2024-01-15"}'
```

## Phase 5: dbt test + docs generate

```bash
# Run all tests
dbt test

# Expected output:
# 1 of 6 START test not_null_stg_orders_order_id .................. [RUN]
# 1 of 6 PASS not_null_stg_orders_order_id ........................ [PASS in 1.23s]
# 2 of 6 START test unique_stg_orders_order_id .................... [RUN]
# 2 of 6 PASS unique_stg_orders_order_id .......................... [PASS in 0.98s]
# ...
# Finished running 6 tests in 8.45s.
# Completed successfully

# Run tests for specific model
dbt test --select stg_orders

# Generate documentation
dbt docs generate

# Serve documentation locally
dbt docs serve --port 8080
# Open http://localhost:8080 to see:
# - Model lineage graph
# - Column descriptions
# - Test results
# - Source freshness

# Check source freshness
dbt source freshness

# Cleanup
az group delete --name rg-dbt-lab --yes --no-wait
```

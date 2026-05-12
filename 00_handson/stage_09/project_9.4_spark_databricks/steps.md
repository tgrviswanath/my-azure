# Steps — Project 9.4: Spark Processing on Azure Databricks

## Phase 1: Create Databricks Workspace

```bash
# Variables
RG="rg-databricks-lab"
LOCATION="eastus"
WORKSPACE_NAME="dbw-spark-lab"
STORAGE_NAME="stadatabricks$(date +%s | tail -c 6)"

# Create resource group
az group create --name $RG --location $LOCATION --tags project=databricks stage=09

# Create ADLS Gen2 storage
az storage account create \
  --name $STORAGE_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2 \
  --hierarchical-namespace true

# Create containers
az storage container create --name raw   --account-name $STORAGE_NAME
az storage container create --name delta --account-name $STORAGE_NAME

# Upload sample data
cat > /tmp/orders_2024_01.csv << 'EOF'
order_id,customer_id,product,amount,quantity,order_date,status,region
1001,C001,Widget A,29.99,2,2024-01-15,completed,us-east
1002,C002,Widget B,49.99,1,2024-01-15,completed,us-west
1003,C003,Widget A,29.99,3,2024-01-16,pending,eu-west
1004,C001,Widget C,99.99,1,2024-01-16,completed,us-east
1005,C004,Widget B,49.99,2,2024-01-17,cancelled,ap-southeast
1006,,Widget A,29.99,1,2024-01-17,completed,us-east
1007,C005,Widget C,,1,2024-01-18,completed,us-west
1008,C006,Widget B,49.99,3,2024-01-18,completed,eu-west
EOF

az storage blob upload \
  --account-name $STORAGE_NAME \
  --container-name raw \
  --name orders/2024/01/orders.csv \
  --file /tmp/orders_2024_01.csv

# Deploy Databricks workspace via Terraform
cd terraform
terraform init
terraform apply -auto-approve

echo "Databricks workspace URL:"
terraform output databricks_workspace_url
```

## Phase 2: Create Cluster (2 Workers)

```bash
# Install Databricks CLI
pip install databricks-cli

# Configure CLI with workspace URL and token
WORKSPACE_URL=$(terraform output -raw databricks_workspace_url)
databricks configure --token --host $WORKSPACE_URL
# Enter your personal access token when prompted
# (Generate in Databricks: User Settings → Access Tokens → Generate New Token)

# Create cluster via CLI
databricks clusters create --json '{
  "cluster_name": "spark-lab-cluster",
  "spark_version": "13.3.x-scala2.12",
  "node_type_id": "Standard_DS3_v2",
  "num_workers": 2,
  "autotermination_minutes": 30,
  "spark_conf": {
    "spark.databricks.delta.preview.enabled": "true",
    "spark.sql.extensions": "io.delta.sql.DeltaSparkSessionExtension",
    "spark.sql.catalog.spark_catalog": "org.apache.spark.sql.delta.catalog.DeltaCatalog"
  },
  "azure_attributes": {
    "availability": "ON_DEMAND_AZURE",
    "first_on_demand": 1,
    "spot_bid_max_price": -1
  }
}'

# Get cluster ID
CLUSTER_ID=$(databricks clusters list --output JSON | python -c "
import json, sys
clusters = json.load(sys.stdin)['clusters']
for c in clusters:
    if c['cluster_name'] == 'spark-lab-cluster':
        print(c['cluster_id'])
        break
")

echo "Cluster ID: $CLUSTER_ID"

# Wait for cluster to start
databricks clusters get --cluster-id $CLUSTER_ID --output JSON | python -c "
import json, sys
c = json.load(sys.stdin)
print(f'State: {c[\"state\"]}')
"
```

## Phase 3: Mount ADLS with Service Principal

```bash
# Create service principal for ADLS access
SP_NAME="sp-databricks-adls"
SP_OUTPUT=$(az ad sp create-for-rbac --name $SP_NAME --skip-assignment)
SP_APP_ID=$(echo $SP_OUTPUT | python -c "import json,sys; print(json.load(sys.stdin)['appId'])")
SP_SECRET=$(echo $SP_OUTPUT | python -c "import json,sys; print(json.load(sys.stdin)['password'])")
TENANT_ID=$(az account show --query tenantId -o tsv)

# Grant SP access to ADLS
az role assignment create \
  --assignee $SP_APP_ID \
  --role "Storage Blob Data Contributor" \
  --scope $(az storage account show --name $STORAGE_NAME --resource-group $RG --query id -o tsv)

# Store credentials in Key Vault
KV_NAME="kv-databricks-$(date +%s | tail -c 6)"
az keyvault create --name $KV_NAME --resource-group $RG --location $LOCATION

az keyvault secret set --vault-name $KV_NAME --name "sp-client-id"     --value $SP_APP_ID
az keyvault secret set --vault-name $KV_NAME --name "sp-client-secret" --value $SP_SECRET
az keyvault secret set --vault-name $KV_NAME --name "sp-tenant-id"     --value $TENANT_ID
az keyvault secret set --vault-name $KV_NAME --name "storage-name"     --value $STORAGE_NAME

# In Databricks notebook, mount ADLS:
cat << 'NOTEBOOK'
# Mount ADLS Gen2 using service principal
configs = {
  "fs.azure.account.auth.type": "OAuth",
  "fs.azure.account.oauth.provider.type": "org.apache.hadoop.fs.azurebfs.oauth2.ClientCredsTokenProvider",
  "fs.azure.account.oauth2.client.id": dbutils.secrets.get(scope="kv-scope", key="sp-client-id"),
  "fs.azure.account.oauth2.client.secret": dbutils.secrets.get(scope="kv-scope", key="sp-client-secret"),
  "fs.azure.account.oauth2.client.endpoint": f"https://login.microsoftonline.com/{dbutils.secrets.get(scope='kv-scope', key='sp-tenant-id')}/oauth2/token"
}

storage_name = dbutils.secrets.get(scope="kv-scope", key="storage-name")

dbutils.fs.mount(
  source=f"abfss://raw@{storage_name}.dfs.core.windows.net/",
  mount_point="/mnt/raw",
  extra_configs=configs
)

dbutils.fs.mount(
  source=f"abfss://delta@{storage_name}.dfs.core.windows.net/",
  mount_point="/mnt/delta",
  extra_configs=configs
)

print("Mounts created:")
display(dbutils.fs.mounts())
NOTEBOOK
```

## Phase 4: Run PySpark Notebook

```bash
# Upload spark_job.py to Databricks workspace
databricks workspace import \
  code/spark_job.py \
  /Shared/spark_job \
  --language PYTHON \
  --overwrite

# Create a job to run the notebook
JOB_ID=$(databricks jobs create --json '{
  "name": "spark-orders-etl",
  "existing_cluster_id": "'"$CLUSTER_ID"'",
  "notebook_task": {
    "notebook_path": "/Shared/spark_job",
    "base_parameters": {
      "storage_name": "'"$STORAGE_NAME"'"
    }
  }
}' | python -c "import json,sys; print(json.load(sys.stdin)['job_id'])")

# Run the job
RUN_ID=$(databricks jobs run-now --job-id $JOB_ID | python -c "import json,sys; print(json.load(sys.stdin)['run_id'])")
echo "Job run ID: $RUN_ID"

# Monitor job
databricks runs get --run-id $RUN_ID --output JSON | python -c "
import json, sys
r = json.load(sys.stdin)
print(f'State: {r[\"state\"][\"life_cycle_state\"]}')
print(f'Result: {r[\"state\"].get(\"result_state\", \"N/A\")}')
"
```

## Phase 5: Query Delta Table with SQL

```bash
# In Databricks SQL or notebook:
cat << 'SQL'
-- Query the Delta table
SELECT * FROM delta.`/mnt/delta/orders_delta/` LIMIT 10;

-- Daily revenue
SELECT
    order_date,
    product,
    SUM(total_amount) AS daily_revenue,
    COUNT(*) AS order_count
FROM delta.`/mnt/delta/orders_delta/`
WHERE status = 'completed'
GROUP BY order_date, product
ORDER BY order_date, daily_revenue DESC;

-- Time travel: see version 0 (before MERGE)
SELECT COUNT(*) AS row_count_v0
FROM delta.`/mnt/delta/orders_delta/`
VERSION AS OF 0;

-- Current version
SELECT COUNT(*) AS row_count_current
FROM delta.`/mnt/delta/orders_delta/`;

-- Delta table history
DESCRIBE HISTORY delta.`/mnt/delta/orders_delta/`;

-- Partition pruning (only scans year=2024/month=1)
SELECT SUM(total_amount)
FROM delta.`/mnt/delta/orders_delta/`
WHERE year = 2024 AND month = 1;
SQL

# Cleanup
az group delete --name $RG --yes --no-wait
```

# Project 9.5 — Apache Airflow on Azure (AKS)

## What This Does

Deploys Apache Airflow on Azure Kubernetes Service (AKS) using the official Helm chart. Creates a production-grade DAG that orchestrates the full data pipeline: triggers an ADF pipeline, runs a Databricks job, executes dbt transformations, and sends failure alerts via email. Demonstrates retry logic, task dependencies, and Azure-native operators.

## Services Used

| Service | Purpose | SKU |
|---|---|---|
| Azure Kubernetes Service (AKS) | Airflow deployment platform | Standard B2s nodes |
| Azure Container Registry | Airflow custom image (optional) | Basic |
| Azure Database for PostgreSQL | Airflow metadata database | Flexible Server B1ms |
| Azure Data Factory | Orchestrated pipeline | Standard |
| Azure Databricks | Orchestrated Spark job | Standard |
| Azure Monitor | AKS metrics and logs | Free tier |

## Architecture

```
AIRFLOW DAG: orders_daily_pipeline
===========================================

  Schedule: @daily (00:00 UTC)

  [START]
     │
     ▼
  ┌─────────────────────────────────┐
  │ adf_copy_raw_orders             │
  │ AzureDataFactoryRunPipeline     │
  │ Operator                        │
  │ pipeline: pl_copy_orders        │
  │ timeout: 30min                  │
  └──────────────┬──────────────────┘
                 │ success
                 ▼
  ┌─────────────────────────────────┐
  │ databricks_transform            │
  │ DatabricksRunNowOperator        │
  │ job_id: spark-orders-etl        │
  │ timeout: 60min                  │
  └──────────────┬──────────────────┘
                 │ success
                 ▼
  ┌─────────────────────────────────┐
  │ dbt_run_models                  │
  │ BashOperator                    │
  │ cmd: dbt run --profiles-dir ... │
  └──────────────┬──────────────────┘
                 │ success
                 ▼
  ┌─────────────────────────────────┐
  │ dbt_test                        │
  │ BashOperator                    │
  │ cmd: dbt test                   │
  └──────────────┬──────────────────┘
                 │ success
                 ▼
  [END — pipeline complete]

  On any failure → EmailOperator (alert@company.com)
```

## How to Run

### Prerequisites
```bash
az login
kubectl version --client
helm version
export RG="rg-airflow-lab"
```

### Deploy
```bash
cd terraform
terraform init
terraform apply -auto-approve

# Get AKS credentials
az aks get-credentials --resource-group $RG --name aks-airflow

# Install Airflow via Helm
helm repo add apache-airflow https://airflow.apache.org
helm install airflow apache-airflow/airflow \
  --namespace airflow \
  --create-namespace \
  --values helm/values.yaml

# Access Airflow UI
kubectl port-forward svc/airflow-webserver 8080:8080 -n airflow
# Open http://localhost:8080 (admin/admin)

# Deploy DAG
kubectl cp code/orders_dag.py airflow/airflow-scheduler-xxx:/opt/airflow/dags/
```

## Lessons Learned

- **Airflow on AKS is complex**: Use the KubernetesExecutor for true scalability. CeleryExecutor needs Redis, which adds cost and complexity.
- **Connection management**: Store Azure credentials in Airflow Connections (not environment variables). Use `airflow connections add` or the UI.
- **DAG versioning**: Store DAGs in a Git repo and use the GitSync sidecar to auto-sync. Don't manually copy files.
- **Retry logic**: Always set `retries=2` and `retry_delay=timedelta(minutes=5)`. ADF and Databricks can have transient failures.
- **Sensor vs Operator**: Use `AzureDataFactoryPipelineRunStatusSensor` to wait for long-running pipelines instead of blocking the operator.

## Code

See `code/orders_dag.py` — complete Airflow DAG with ADF, Databricks, dbt operators, retry logic, and email failure callback.

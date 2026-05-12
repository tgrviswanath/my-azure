# Steps — Project 9.5: Apache Airflow on Azure AKS

## Phase 1: Deploy AKS

```bash
# Variables
RG="rg-airflow-lab"
LOCATION="eastus"
AKS_NAME="aks-airflow"
NODE_COUNT=2
NODE_SIZE="Standard_D2s_v3"

# Create resource group
az group create --name $RG --location $LOCATION --tags project=airflow stage=09

# Deploy AKS via Terraform
cd terraform
terraform init
terraform apply -auto-approve

# Get AKS credentials
az aks get-credentials \
  --resource-group $RG \
  --name $AKS_NAME \
  --overwrite-existing

# Verify cluster
kubectl get nodes
kubectl get namespaces

# Create airflow namespace
kubectl create namespace airflow
```

## Phase 2: Install Airflow via Helm

```bash
# Add Airflow Helm repo
helm repo add apache-airflow https://airflow.apache.org
helm repo update

# Create Airflow values file
cat > /tmp/airflow-values.yaml << 'EOF'
executor: KubernetesExecutor

webserver:
  replicas: 1
  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "1Gi"
      cpu: "500m"

scheduler:
  replicas: 1
  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"

workers:
  replicas: 0  # KubernetesExecutor creates workers on demand

postgresql:
  enabled: true
  auth:
    password: "AirflowP@ss123!"

redis:
  enabled: false  # Not needed for KubernetesExecutor

dags:
  persistence:
    enabled: true
    size: 1Gi
  gitSync:
    enabled: false  # Enable and point to your DAG repo in production

env:
  - name: AIRFLOW__CORE__LOAD_EXAMPLES
    value: "False"
  - name: AIRFLOW__WEBSERVER__EXPOSE_CONFIG
    value: "True"

defaultAirflowUsername: admin
defaultAirflowPassword: admin
EOF

# Install Airflow
helm install airflow apache-airflow/airflow \
  --namespace airflow \
  --values /tmp/airflow-values.yaml \
  --timeout 10m \
  --wait

# Check pods
kubectl get pods -n airflow

# Wait for webserver to be ready
kubectl wait --for=condition=ready pod \
  -l component=webserver \
  -n airflow \
  --timeout=300s
```

## Phase 3: Configure Azure Connections

```bash
# Port-forward to access Airflow UI
kubectl port-forward svc/airflow-webserver 8080:8080 -n airflow &
echo "Airflow UI: http://localhost:8080 (admin/admin)"

# Get scheduler pod name
SCHEDULER_POD=$(kubectl get pods -n airflow -l component=scheduler -o jsonpath='{.items[0].metadata.name}')

# Add Azure Data Factory connection
kubectl exec -n airflow $SCHEDULER_POD -- airflow connections add \
  'azure_data_factory_default' \
  --conn-type 'azure_data_factory' \
  --conn-extra '{
    "subscriptionId": "YOUR_SUBSCRIPTION_ID",
    "resourceGroup": "rg-adf-etl-lab",
    "factory": "adf-etl-lab",
    "tenantId": "YOUR_TENANT_ID",
    "clientId": "YOUR_SP_CLIENT_ID",
    "clientSecret": "YOUR_SP_SECRET"
  }'

# Add Databricks connection
kubectl exec -n airflow $SCHEDULER_POD -- airflow connections add \
  'databricks_default' \
  --conn-type 'databricks' \
  --conn-host 'https://adb-XXXXXXXXXXXXXXXX.X.azuredatabricks.net' \
  --conn-extra '{"token": "YOUR_DATABRICKS_PAT"}'

# Add email connection (SMTP)
kubectl exec -n airflow $SCHEDULER_POD -- airflow connections add \
  'smtp_default' \
  --conn-type 'smtp' \
  --conn-host 'smtp.office365.com' \
  --conn-port '587' \
  --conn-login 'airflow@yourdomain.com' \
  --conn-password 'YOUR_EMAIL_PASSWORD' \
  --conn-extra '{"starttls": true}'

# Verify connections
kubectl exec -n airflow $SCHEDULER_POD -- airflow connections list
```

## Phase 4: Create DAG

```bash
# Copy DAG to scheduler pod
kubectl cp code/orders_dag.py airflow/$SCHEDULER_POD:/opt/airflow/dags/orders_dag.py

# Verify DAG is loaded
kubectl exec -n airflow $SCHEDULER_POD -- airflow dags list | grep orders

# Check DAG for errors
kubectl exec -n airflow $SCHEDULER_POD -- airflow dags show orders_daily_pipeline

# Trigger DAG manually for testing
kubectl exec -n airflow $SCHEDULER_POD -- airflow dags trigger orders_daily_pipeline

# Monitor DAG run
kubectl exec -n airflow $SCHEDULER_POD -- airflow dags list-runs \
  --dag-id orders_daily_pipeline \
  --output table

# Check task status
kubectl exec -n airflow $SCHEDULER_POD -- airflow tasks states-for-dag-run \
  orders_daily_pipeline \
  $(date +%Y-%m-%dT%H:%M:%S+00:00)
```

## Phase 5: Schedule Daily

```bash
# The DAG is already scheduled with schedule_interval='@daily'
# Verify the schedule
kubectl exec -n airflow $SCHEDULER_POD -- airflow dags show orders_daily_pipeline

# Unpause the DAG (paused by default on first load)
kubectl exec -n airflow $SCHEDULER_POD -- airflow dags unpause orders_daily_pipeline

# Check next scheduled run
kubectl exec -n airflow $SCHEDULER_POD -- airflow dags next-execution orders_daily_pipeline

# Monitor via Airflow UI
echo "Open http://localhost:8080 → DAGs → orders_daily_pipeline → Graph View"

# View logs for a specific task
kubectl exec -n airflow $SCHEDULER_POD -- airflow tasks logs \
  orders_daily_pipeline \
  adf_copy_raw_orders \
  $(date +%Y-%m-%dT00:00:00+00:00)

# Cleanup
helm uninstall airflow -n airflow
az group delete --name $RG --yes --no-wait
```

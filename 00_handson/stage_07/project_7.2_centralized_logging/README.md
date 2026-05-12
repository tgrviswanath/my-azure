# Project 7.2 — Centralized Logging

## What This Does

Builds a centralized logging platform that aggregates logs from all Azure resources into a single Log Analytics Workspace, then visualizes them in Azure Managed Grafana. Uses Diagnostic Settings to route logs from VMs, storage accounts, and networking. Includes a custom log shipper that sends structured application logs via the Logs Ingestion API.

## Services Used

| Service | Purpose |
|---|---|
| Log Analytics Workspace | Central log store — receives logs from all resources |
| Azure Monitor | Platform for metrics and log routing |
| Azure Managed Grafana | Visualization layer — dashboards over Log Analytics data |
| Diagnostic Settings | Route resource logs to Log Analytics per resource |
| Data Collection Endpoint (DCE) | HTTP endpoint for custom log ingestion |
| Data Collection Rule (DCR) | Defines schema and destination for custom logs |

## Architecture

```
Azure Resources (VM, Storage, App Service, NSG)
        │
        ▼ (Diagnostic Settings — per resource)
┌───────────────────────────────────────────┐
│         Log Analytics Workspace           │
│         law-logging-demo                  │
│                                           │
│  Tables:                                  │
│  - AzureActivity (subscription events)   │
│  - Perf (CPU, memory from VMs)            │
│  - Syslog (Linux system logs)             │
│  - AzureDiagnostics (resource logs)       │
│  - AppLogs_CL (custom application logs)   │
└──────────────────────┬────────────────────┘
                       │
                       ▼ (Azure Monitor data source)
┌───────────────────────────────────────────┐
│         Azure Managed Grafana             │
│         grafana-logging-demo              │
│                                           │
│  Dashboards:                              │
│  - Resource Health Overview               │
│  - Application Error Rate                 │
│  - Security Events                        │
│  - Custom App Logs                        │
└───────────────────────────────────────────┘
        ▲
        │ (Logs Ingestion API)
┌───────────────────────────────────────────┐
│  log_shipper.py                           │
│  Sends structured JSON logs via DCE/DCR   │
└───────────────────────────────────────────┘
```

## How to Run

```bash
# 1. Login
az login
az account set --subscription "your-subscription-id"

# 2. Create resource group
az group create --name rg-logging-demo --location eastus

# 3. Deploy infrastructure
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 4. Get DCE and DCR details from Terraform output
terraform output -json

# 5. Install Python dependencies
cd ../code
pip install azure-identity azure-monitor-ingestion azure-mgmt-monitor

# 6. Set environment variables
export AZURE_SUBSCRIPTION_ID="your-sub-id"
export DCE_ENDPOINT=$(cd ../terraform && terraform output -raw dce_endpoint)
export DCR_IMMUTABLE_ID=$(cd ../terraform && terraform output -raw dcr_immutable_id)
export DCR_STREAM_NAME="Custom-AppLogs_CL"

# 7. Run log shipper
python log_shipper.py

# 8. Query logs in Log Analytics (wait 5 minutes for ingestion)
az monitor log-analytics query \
  --workspace "$(cd ../terraform && terraform output -raw law_workspace_id)" \
  --analytics-query "AppLogs_CL | order by TimeGenerated desc | take 20" \
  --output table

# 9. Open Grafana
echo "Grafana URL: $(cd ../terraform && terraform output -raw grafana_endpoint)"

# 10. Clean up
terraform destroy
```

## Lessons Learned

- Diagnostic Settings must be enabled per resource — there is no global "enable all" switch.
- The Logs Ingestion API (DCE + DCR) replaces the old HTTP Data Collector API — use it for custom logs.
- DCR stream names must match the table name in Log Analytics (e.g., `Custom-AppLogs_CL`).
- Managed Grafana automatically gets the Azure Monitor data source configured — no manual setup needed.
- Log Analytics ingestion has a ~5-minute latency — don't expect real-time data.
- Use `_CL` suffix for custom log tables (CL = Custom Log).
- Grafana dashboards can be imported from grafana.com using dashboard IDs — Azure has official ones.
- For high-volume logging, use Event Hub as a buffer between resources and Log Analytics to avoid ingestion throttling.

## Code

See `code/log_shipper.py` for the Python script that creates a DCE, DCR, and sends structured log events via the Logs Ingestion API.

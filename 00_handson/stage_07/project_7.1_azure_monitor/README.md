# Project 7.1 — Azure Monitor

## What This Does

Sets up Azure Monitor to collect metrics and logs from Azure resources (VMs, storage, networking), creates alert rules that fire when CPU or memory thresholds are breached, configures action groups to notify via email/SMS/webhook, and builds a dashboard to visualize resource health in real time.

## Services Used

| Service | Purpose |
|---|---|
| Azure Monitor | Collect metrics and logs from all Azure resources |
| Log Analytics Workspace | Store and query logs using KQL |
| Action Groups | Define notification channels (email, SMS, webhook, ITSM) |
| Alert Rules (Metric) | Trigger alerts when metric thresholds are crossed |
| Azure Dashboards | Visualize metrics and alert status |

## Architecture

```
Azure Resources (VM, Storage, Network)
        │
        ▼
Azure Monitor (Platform Metrics — auto-collected)
        │
        ├──► Log Analytics Workspace (diagnostic logs)
        │
        ▼
Alert Rules (CPU > 80%, Memory > 90%, Disk > 85%)
        │
        ▼
Action Group
        ├──► Email notification
        ├──► SMS notification
        └──► Webhook (Teams / PagerDuty / Slack)
        │
        ▼
Azure Dashboard (pinned charts, alert tiles)
```

## How to Run

```bash
# 1. Login and set subscription
az login
az account set --subscription "your-subscription-id"

# 2. Create resource group
az group create --name rg-monitor-demo --location eastus

# 3. Deploy Terraform
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 4. Run Python setup script
cd ../code
pip install azure-identity azure-mgmt-monitor azure-mgmt-resource
python monitor_setup.py

# 5. Verify alerts in portal
az monitor metrics alert list --resource-group rg-monitor-demo --output table

# 6. Trigger a test alert (stress CPU on VM)
az vm run-command invoke \
  --resource-group rg-monitor-demo \
  --name vm-monitor-demo \
  --command-id RunShellScript \
  --scripts "stress --cpu 4 --timeout 300"

# 7. Check action group was triggered
az monitor activity-log list \
  --resource-group rg-monitor-demo \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --output table

# 8. Clean up
terraform destroy
```

## Lessons Learned

- Azure Monitor collects platform metrics automatically — no agent needed for basic CPU/memory/disk on VMs.
- Log Analytics Workspace is the backbone: almost every Azure service can ship diagnostic logs there.
- Action Groups are reusable — one group can be shared across many alert rules.
- Alert rules evaluate on a cadence (e.g., every 5 minutes over a 15-minute window) — tune window size to avoid flapping.
- Custom metrics require the Azure Monitor Agent (AMA) or the Metrics API — the old MMA agent is deprecated.
- Dashboard tiles are JSON-based and can be exported/imported via ARM templates.
- Use dynamic thresholds (ML-based) for metrics with seasonal patterns instead of static thresholds.

## Code

See `code/monitor_setup.py` for the Python automation script that creates alert rules, action groups, and prints a monitoring report.

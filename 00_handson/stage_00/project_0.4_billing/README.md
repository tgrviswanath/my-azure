# Project 0.4 — Azure Cost Management & Billing

## What This Does
Sets up Azure Cost Management with budget alerts, cost anomaly detection, and a resource tagging strategy. Teaches you to monitor and control Azure spending before it becomes a problem.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure Cost Management | Monitor and analyze spending |
| Azure Budgets | Set spending limits with email alerts |
| Cost Anomaly Alerts | Detect unexpected spending spikes |
| Azure Monitor Action Groups | Route alerts to email/SMS/webhook |
| Resource Tags | Categorize resources for cost allocation |

## How to Deploy
```bash
cd terraform
terraform init
terraform apply -auto-approve

# Run billing monitor
pip install azure-mgmt-costmanagement azure-identity
python code/billing_monitor.py
```

## Folder Structure
```
project_0.4_billing/
├── README.md
├── steps.md
├── cost_estimate.md
├── docs/
│   └── architecture.md
├── terraform/
│   └── main.tf
└── code/
    └── billing_monitor.py
```

## Lessons Learned
- Set a budget alert BEFORE deploying any resources — not after
- Cost anomaly alerts catch runaway costs within 24-48 hours
- Tagging strategy: always tag `environment`, `project`, `owner`, `cost-center`
- `az consumption budget list` shows all budgets in a subscription
- Cost Management data has a 24-48 hour delay — not real-time
- Free tier: Cost Management is free for Azure customers
- Use `az cost management query` for programmatic cost analysis

## Tagging Strategy
| Tag Key | Example Values |
|---------|---------------|
| `environment` | dev, staging, prod |
| `project` | azure-lab, my-app |
| `owner` | team-name or email |
| `cost-center` | engineering, marketing |
| `auto-shutdown` | true/false |

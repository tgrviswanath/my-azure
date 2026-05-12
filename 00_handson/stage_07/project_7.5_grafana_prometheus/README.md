# Project 7.5 — Grafana + Prometheus Monitoring

## What This Does
Deploys the modern observability stack on AKS using Azure Managed Prometheus and Azure Managed Grafana. Prometheus scrapes metrics from pods, Grafana visualizes them with RED method dashboards.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure Managed Prometheus | Fully managed Prometheus (Azure Monitor workspace) |
| Azure Managed Grafana | Fully managed Grafana with Azure AD SSO |
| AKS | Kubernetes cluster running workloads |
| Data Collection Rules | Define what metrics to scrape |

## Architecture
```
AKS Pods (/metrics endpoint)
    │ Prometheus scrape every 15s
    ▼
Azure Monitor Workspace (Managed Prometheus)
    │ PromQL query API
    ▼
Azure Managed Grafana
    ├── Data source: Azure Monitor (Prometheus)
    ├── Data source: Azure Monitor (CloudWatch-style)
    └── Dashboards + Alerts → Email/Teams
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve
# Get Grafana endpoint from output
terraform output grafana_endpoint
```

## Lessons Learned
- Azure Managed Prometheus: no server to manage, auto-scales, 18-month retention
- Azure Managed Grafana: Azure AD SSO built-in, no password management
- Use kube-prometheus-stack Helm chart for full Kubernetes monitoring
- RED method: Rate, Errors, Duration — the three golden signals for services

## Code

### `code/metrics_exporter.py` — Flask app with Prometheus /metrics endpoint

```bash
pip install flask prometheus-client
python code/metrics_exporter.py
curl http://localhost:8080/metrics
```

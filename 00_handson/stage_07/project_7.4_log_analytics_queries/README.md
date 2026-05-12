# Project 7.4 — Log Analytics Query Lab

## What This Does
Uses KQL (Kusto Query Language) to analyze NSG flow logs, Azure Activity logs, and application logs in Log Analytics Workspace.

## Services Used
| Service | Purpose |
|---------|---------|
| Log Analytics Workspace | Central log store + KQL engine |
| NSG Flow Logs | Network traffic analysis |
| Azure Activity Log | Subscription-level audit trail |
| Network Watcher | Enable NSG flow logs |

## Architecture
```
NSG Flow Logs → Storage Account → Log Analytics
Activity Logs → Log Analytics (built-in connector)
App Logs → Diagnostic Settings → Log Analytics
    │
    ▼
KQL Queries → Insights → Saved Queries → Alerts
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve

# Run a KQL query via CLI
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "AzureActivity | summarize count() by OperationNameValue | top 10 by count_"
```

## Lessons Learned
- KQL is powerful — learn `summarize`, `project`, `where`, `join`, `extend`
- NSG flow logs: enable on Network Watcher, not on NSG directly
- Activity logs are free — always enable them
- Use `ago(1d)` for time filtering — much faster than datetime ranges

## Code

### `queries/activity_log_queries.kql` — Activity log KQL queries
### `queries/nsg_flow_queries.kql` — NSG flow log KQL queries
### `code/kql_runner.py` — Run KQL queries from Python or CLI

```bash
pip install azure-identity azure-monitor-query

export LOG_ANALYTICS_WORKSPACE_ID="<workspace-id>"

# Use preset queries
python code/kql_runner.py --preset failed-ops
python code/kql_runner.py --preset top-callers
python code/kql_runner.py --preset role-changes

# Run a custom query
python code/kql_runner.py --query "AzureActivity | take 10"

# Run from .kql file
python code/kql_runner.py --file queries/activity_log_queries.kql

# Query last 7 days
python code/kql_runner.py --preset failed-ops --days 7
```

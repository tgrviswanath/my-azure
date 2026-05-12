# Architecture — Project 7.2 Centralized Logging Platform

## Diagram

```
Azure Resources
  ├── VMs → Diagnostic Settings → Log Analytics Workspace
  ├── AKS → Container Insights → Log Analytics Workspace
  ├── App Service → App Logs → Log Analytics Workspace
  ├── Azure SQL → Audit Logs → Log Analytics Workspace
  └── NSG → Flow Logs → Storage → Log Analytics Workspace
                │
                ▼
        Log Analytics Workspace
          ├── KQL queries
          ├── Saved searches
          └── Alert rules
                │
                ▼
        Azure Managed Grafana
          ├── Azure Monitor data source
          ├── Log Analytics data source
          └── Dashboards (infrastructure, app, security)
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Diagnostic Settings | Route resource logs to Log Analytics |
| Log Analytics Workspace | Central log store with KQL query engine |
| Managed Grafana | Fully managed Grafana with Azure AD SSO |
| Data Collection Rules | Define what logs to collect and where to send |
| Retention | Default 30 days free, up to 730 days |

# Architecture — Project 7.4 Log Analytics Query Lab

## Diagram

```
Data Sources
  ├── NSG Flow Logs → Storage Account → Log Analytics (AzureNetworkAnalytics_CL)
  ├── Activity Log → Diagnostic Setting → Log Analytics (AzureActivity)
  ├── VM Logs → MMA/AMA Agent → Log Analytics (Syslog, Event, Perf)
  └── App Logs → Diagnostic Setting → Log Analytics (AppServiceHTTPLogs)
                │
                ▼
        Log Analytics Workspace
          │
          ├── KQL Query Engine
          │     ├── summarize, project, where, join, extend
          │     ├── Time series analysis
          │     └── Anomaly detection (series_decompose_anomalies)
          │
          ├── Saved Queries (query packs)
          │
          └── Alert Rules (scheduled queries)
                │
                ▼
          Action Group → Email / Teams / PagerDuty
```

## Key KQL Operators

| Operator | Use Case |
|----------|---------|
| `where` | Filter rows |
| `summarize` | Aggregate (count, sum, avg, percentile) |
| `project` | Select/rename columns |
| `extend` | Add computed columns |
| `join` | Join two tables |
| `top N by` | Top N results |
| `ago(1d)` | Time filter (last 1 day) |
| `bin(TimeGenerated, 1h)` | Time bucketing |

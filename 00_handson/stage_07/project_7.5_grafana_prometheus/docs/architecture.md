# Architecture — Project 7.5 Grafana + Prometheus Monitoring

## Diagram

```
AKS Cluster
  └── Pods (expose /metrics endpoint)
        │ Prometheus format metrics
        │
        ▼
  AMA Metrics Agent (DaemonSet on each node)
        │ scrapes /metrics every 15s
        │ remote_write with Azure AD auth
        ▼
  Azure Monitor Workspace
  (Managed Prometheus)
        │ PromQL query API
        │
        ▼
  Azure Managed Grafana
        ├── Data source: Azure Monitor (Prometheus)
        ├── Data source: Azure Monitor (metrics)
        │
        ├── Dashboard: Kubernetes Overview
        │     ├── CPU/Memory by namespace
        │     ├── Pod restart count
        │     └── Node resource utilization
        │
        ├── Dashboard: Application (RED method)
        │     ├── Rate: requests/second
        │     ├── Errors: 5xx error rate %
        │     └── Duration: P50/P95/P99 latency
        │
        └── Alerts → Email / Teams / PagerDuty
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Managed Prometheus | Azure-hosted Prometheus — no server management |
| AMA Metrics | Azure Monitor Agent — replaces Prometheus server on AKS |
| PromQL | Prometheus Query Language — powerful time-series queries |
| RED method | Rate, Errors, Duration — golden signals for services |
| Managed Grafana | Azure AD SSO, no password management |

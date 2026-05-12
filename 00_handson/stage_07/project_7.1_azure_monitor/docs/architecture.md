# Architecture — Project 7.1 Azure Monitor

## Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Azure Subscription                           │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    Resource Group: rg-monitor-demo           │   │
│  │                                                              │   │
│  │  ┌─────────────┐    Platform Metrics (auto)                  │   │
│  │  │  VM         │──────────────────────────────────────┐      │   │
│  │  │ (B2s)       │                                      │      │   │
│  │  └─────────────┘                                      ▼      │   │
│  │                                              ┌──────────────┐│   │
│  │  ┌─────────────┐    Diagnostic Logs          │Azure Monitor ││   │
│  │  │  Storage    │──────────────────────────►  │              ││   │
│  │  │  Account    │                             │  Metrics DB  ││   │
│  │  └─────────────┘                             │  (93 days)   ││   │
│  │                                              └──────┬───────┘│   │
│  │  ┌─────────────┐    Activity Logs                   │        │   │
│  │  │  Network    │──────────────────────────────────  │        │   │
│  │  │  (NSG/VNet) │                                    │        │   │
│  │  └─────────────┘                                    │        │   │
│  │                                                     │        │   │
│  │                    ┌────────────────────────────────┘        │   │
│  │                    │                                         │   │
│  │                    ▼                                         │   │
│  │  ┌─────────────────────────────┐                            │   │
│  │  │   Log Analytics Workspace   │                            │   │
│  │  │   law-monitor-demo          │                            │   │
│  │  │                             │                            │   │
│  │  │  Tables:                    │                            │   │
│  │  │  - Perf (CPU, Memory)       │                            │   │
│  │  │  - AzureActivity            │                            │   │
│  │  │  - AzureMetrics             │                            │   │
│  │  │  - Syslog                   │                            │   │
│  │  └──────────────┬──────────────┘                            │   │
│  │                 │                                            │   │
│  │                 ▼                                            │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │              Alert Rules                             │   │   │
│  │  │                                                      │   │   │
│  │  │  alert-cpu-high:  CPU > 80% for 5 min  (Sev 2)      │   │   │
│  │  │  alert-disk-high: Disk I/O > 50MB/s    (Sev 3)      │   │   │
│  │  │  alert-mem-high:  Memory > 90%         (Sev 2)      │   │   │
│  │  └──────────────────────┬───────────────────────────────┘   │   │
│  │                         │                                    │   │
│  │                         ▼                                    │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │              Action Group: ag-monitor-demo           │   │   │
│  │  │                                                      │   │   │
│  │  │  ┌──────────────┐  ┌──────────┐  ┌───────────────┐  │   │   │
│  │  │  │ Email        │  │ SMS      │  │ Webhook       │  │   │   │
│  │  │  │ admin@...    │  │ +1-555.. │  │ teams/slack   │  │   │   │
│  │  │  └──────────────┘  └──────────┘  └───────────────┘  │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  │                                                              │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │              Azure Dashboard                         │   │   │
│  │  │  [CPU Chart] [Disk I/O] [Alert Status] [Log Query]  │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Concepts

| Concept | Description |
|---|---|
| Platform Metrics | Automatically collected by Azure for all resources — CPU, disk, network, etc. Stored for 93 days in Azure Monitor metrics store. No configuration needed. |
| Diagnostic Settings | Route platform metrics and resource logs to Log Analytics, Storage, or Event Hub. Must be explicitly enabled per resource. |
| Log Analytics Workspace | Central store for logs. Uses KQL for querying. Multiple resources can send to one workspace. |
| Metric Alert Rule | Evaluates a metric condition on a schedule (e.g., every 1 min). Fires when condition is met for the evaluation window. |
| Action Group | Reusable set of notification actions. One group can be referenced by many alert rules. Supports email, SMS, voice, webhook, ITSM, Azure Function, Logic App. |
| Alert Severity | 0 = Critical, 1 = Error, 2 = Warning, 3 = Informational, 4 = Verbose. Affects visual priority in portal. |
| Evaluation Window | The time range over which the metric is aggregated before comparing to threshold. Larger windows reduce noise. |
| Evaluation Frequency | How often the alert rule checks the condition. Minimum 1 minute for metric alerts. |
| Dynamic Thresholds | ML-based thresholds that adapt to metric seasonality. Better than static for workloads with daily/weekly patterns. |
| Azure Monitor Agent | Replacement for MMA/OMS agent. Required for custom performance counters, Windows Event Logs, Syslog collection. |
| Data Collection Rule | Defines what data AMA collects and where it sends it. Linked to VMs via association. |

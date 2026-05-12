# Architecture — Project 7.3 Application Insights Distributed Tracing

## Diagram

```
Flask App (instrumented with opencensus-ext-azure)
    │
    │ SDK sends telemetry
    ▼
Application Insights
    ├── Requests (HTTP traces)
    ├── Dependencies (DB calls, HTTP calls)
    ├── Exceptions (stack traces)
    ├── Custom Events (business events)
    └── Custom Metrics (counters, gauges)
          │
          ▼
    Log Analytics Workspace
          │
          ├── Application Map (service topology)
          ├── Transaction Search (individual traces)
          ├── Performance (P50/P95/P99 latency)
          ├── Failures (error rate, exceptions)
          └── Live Metrics (real-time stream)
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Instrumentation Key | Identifies your App Insights resource |
| Correlation ID | Links related requests across services |
| Sampling | Reduce telemetry volume while keeping representative data |
| Application Map | Auto-discovered service dependency graph |
| Smart Detection | ML-based anomaly detection |

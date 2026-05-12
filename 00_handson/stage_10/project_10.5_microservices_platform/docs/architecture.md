# Architecture — Project 10.5 Production-grade Microservices Platform

## Diagram

```
Internet
    │ HTTPS
    ▼
Azure Front Door (CDN + WAF)
    │
    ▼
API Management (apim-platform-001)
    ├── Auth: Azure AD OAuth2
    ├── Rate limiting: 1000 req/min
    ├── Caching: 60s for GET /products
    │
    ├── /api/orders → Order Service (AKS)
    │     ├── Azure SQL (orders DB, hash distributed)
    │     ├── Redis (cache, TTL 300s)
    │     └── Event Hubs (publish OrderPlaced events)
    │
    ├── /api/users → User Service (AKS)
    │     └── Azure SQL (users DB)
    │
    └── /api/analytics → Analytics Service (AKS)
          ├── Event Hubs (consume OrderPlaced events)
          ├── Azure Data Factory (nightly batch)
          └── Synapse Analytics (OLAP queries)

Observability Layer:
    Application Insights → distributed traces
    Azure Monitor → metrics + alerts
    Managed Grafana → dashboards

Security Layer:
    Key Vault → all secrets
    Managed Identity → no stored credentials
    Defender for Cloud → threat detection
    WAF → OWASP protection
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| API Management | Single entry point — auth, rate limiting, routing |
| Event-driven | Services communicate via Event Hubs — decoupled |
| Database per service | Each service owns its data — no shared DB |
| Managed Identity | Services authenticate to Azure without secrets |
| Observability | Traces, metrics, logs — you can't fix what you can't see |

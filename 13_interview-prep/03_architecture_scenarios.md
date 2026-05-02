# Architecture & Scenario Interview Questions

## System Design Scenarios

### S1: Design a globally available e-commerce platform on Azure

**Requirements**: 99.99% availability, < 200ms response time globally, handle 10K concurrent users, PCI-DSS compliant

**Architecture**:
```
Global Layer:
  Azure Front Door Premium (WAF, CDN, global routing)
  
Regional Layer (East US + West Europe):
  App Service Premium P3v3 (auto-scale 3-20 instances)
  Azure Cache for Redis Premium (session, product cache)
  
Data Layer:
  Azure SQL Business Critical (zone-redundant, failover group)
  Azure Cosmos DB (product catalog, global distribution)
  Azure Storage ZRS (product images, CDN origin)
  
Security:
  Azure API Management (rate limiting, auth)
  Key Vault (secrets, certificates)
  Managed Identity (no credentials in code)
  
Monitoring:
  Application Insights (APM)
  Log Analytics (centralized logs)
  Azure Monitor (alerts, dashboards)
```

**Key decisions**:
- Front Door for global routing + WAF (not Traffic Manager — need L7)
- Cosmos DB for product catalog (global reads, eventual consistency OK)
- SQL for orders (ACID transactions required)
- Redis for session (stateless app servers)
- Deployment slots for zero-downtime releases

---

### S2: Design a real-time IoT data processing pipeline

**Requirements**: 1M devices, 1000 events/device/day, real-time alerts, 2-year data retention, analytics dashboard

**Architecture**:
```
Ingestion:
  IoT Hub (device management, D2C messages)
  Event Hubs (high-throughput streaming)
  
Real-time Processing:
  Stream Analytics (windowed aggregations, anomaly detection)
  Azure Functions (triggered by Stream Analytics for alerts)
  
Storage:
  ADLS Gen2 (raw data, Bronze layer)
  Azure Synapse Analytics (Silver/Gold layers)
  Cosmos DB (device state, real-time queries)
  
Analytics:
  Synapse SQL Pool (historical analysis)
  Power BI (dashboards)
  
Alerts:
  Azure Monitor (metric alerts)
  Logic Apps (email/SMS notifications)
```

**Cost optimization**:
- Event Hubs Standard (not Premium) for ingestion
- Stream Analytics 3 SU (scale based on throughput)
- ADLS Gen2 lifecycle: Hot → Cool after 30 days, Archive after 365 days
- Synapse: pause when not in use (dev/test)

---

### S3: Design a microservices architecture for a banking application

**Requirements**: High security, audit trail, 99.999% availability, regulatory compliance

**Architecture**:
```
API Layer:
  Azure API Management (Premium, zone-redundant)
  Azure Front Door (WAF, DDoS protection)
  
Compute:
  AKS (3 zones, system + user node pools)
  Dapr (service mesh, state management)
  
Services:
  Account Service → Azure SQL Business Critical
  Transaction Service → Azure SQL Business Critical
  Notification Service → Service Bus → Azure Functions
  Audit Service → Event Hubs → ADLS Gen2
  
Security:
  Azure AD (identity)
  Key Vault (secrets, HSM keys)
  Managed Identity (workload identity)
  Private Endpoints (all services)
  Azure Firewall Premium (IDPS, TLS inspection)
  Microsoft Defender for Cloud
  
Compliance:
  Azure Policy (enforce standards)
  Azure Blueprints (compliant environment templates)
  Microsoft Purview (data governance)
  Immutable Storage (audit logs)
```

---

## Troubleshooting Scenarios

### T1: App Service returns 503 errors intermittently

**Diagnosis steps**:
1. Check App Service metrics: HTTP 5xx, Response Time, Requests
2. Application Insights: failed requests, exceptions, dependencies
3. Check App Service logs: `az webapp log tail --name $APP --resource-group $RG`
4. Check auto-scale events: was scaling happening?
5. Check deployment: recent deployment causing issues?
6. Check dependencies: database, Redis, external APIs timing out?

**Common causes**:
- App running out of memory → increase plan or fix memory leak
- Database connection pool exhausted → increase pool size
- Cold start on scale-out → use Always On, pre-warmed instances
- Deployment in progress → use deployment slots

### T2: Cosmos DB requests are throttled (429 errors)

**Diagnosis**:
1. Check RU consumption in Azure Monitor
2. Identify which operations consume most RUs
3. Check partition key distribution (hot partition?)

**Solutions**:
1. Increase provisioned throughput (RU/s)
2. Enable autoscale (max RU/s)
3. Optimize queries (add indexes, avoid cross-partition)
4. Implement retry with exponential backoff
5. Use bulk operations for batch writes
6. Cache frequently-read data in Redis

### T3: AKS pods are in CrashLoopBackOff

**Diagnosis**:
```bash
kubectl describe pod $POD_NAME -n $NAMESPACE
kubectl logs $POD_NAME -n $NAMESPACE --previous
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'
```

**Common causes**:
- Application error on startup → check logs
- Missing environment variable/secret → check ConfigMap/Secret
- Insufficient resources → check resource limits
- Liveness probe failing → check probe configuration
- Image pull error → check ACR credentials, image tag
- OOMKilled → increase memory limits

---

## Cost Optimization Questions

### C1: How do you reduce Azure costs by 40%?

**Immediate wins**:
1. Delete unused resources (stopped VMs still charge for storage)
2. Right-size VMs using Azure Advisor
3. Enable auto-shutdown for dev/test VMs
4. Move to Reserved Instances for production (1-year = ~40% savings)

**Medium-term**:
5. Use Spot VMs for batch/CI workloads (up to 90% savings)
6. Storage lifecycle policies (move to Cool/Archive)
7. Azure Hybrid Benefit (use existing Windows/SQL licenses)
8. Consolidate small databases into Elastic Pool

**Architecture changes**:
9. Serverless for variable workloads (Functions, Cosmos Serverless)
10. CDN for static content (reduce App Service load)
11. Caching (Redis) to reduce database queries

### C2: How do you implement FinOps in Azure?

**Visibility**:
- Azure Cost Management + Billing
- Cost allocation tags (Environment, Team, Project)
- Budgets with alerts
- Cost anomaly detection

**Accountability**:
- Separate subscriptions per team/environment
- Chargeback/showback reports
- Monthly cost reviews

**Optimization**:
- Azure Advisor recommendations
- Reserved Instances for predictable workloads
- Savings Plans for flexible compute
- Regular right-sizing reviews

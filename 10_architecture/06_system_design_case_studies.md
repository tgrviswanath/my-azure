# Azure System Design Case Studies

## Case Study 1: Design a Global SaaS Application on Azure

```
Requirements:
  - 10M users across 5 continents
  - < 100ms latency globally
  - 99.99% availability
  - Multi-tenant with data isolation

Architecture:
  ┌─────────────────────────────────────────────────────────┐
  │                  Global Traffic Management               │
  │  Azure Front Door (global load balancing + WAF + CDN)   │
  └──────────────────────┬──────────────────────────────────┘
                         │ Routes to nearest region
         ┌───────────────┼───────────────┐
         ▼               ▼               ▼
    East US         West Europe      Southeast Asia
    ┌──────────┐    ┌──────────┐    ┌──────────┐
    │ App Svc  │    │ App Svc  │    │ App Svc  │
    │ (active) │    │ (active) │    │ (active) │
    └──────────┘    └──────────┘    └──────────┘
         │               │               │
         └───────────────┼───────────────┘
                         ▼
              ┌─────────────────────┐
              │  Cosmos DB          │
              │  (multi-region      │
              │   multi-write)      │
              │  ~1s replication    │
              └─────────────────────┘

Multi-tenancy:
  Option A: Separate DB per tenant (strongest isolation, highest cost)
  Option B: Shared DB, tenant_id in every table (cheapest, shared fate)
  Option C: Separate schema per tenant (balance)

Recommended: Option C for enterprise SaaS
  - Separate Cosmos DB containers per tenant
  - Partition key = tenant_id
  - Shared throughput with per-tenant limits
```

---

## Case Study 2: Design a Real-Time IoT Platform on Azure

```
Requirements:
  - 1M IoT devices sending telemetry every 30 seconds
  - Real-time anomaly detection
  - Historical data analysis
  - Device management (OTA updates, commands)

Scale:
  1M devices × 1 msg/30s = 33,333 messages/sec
  Each message: 1KB → 33 MB/sec ingestion

Architecture:
  IoT Devices
       ↓ MQTT/HTTPS
  Azure IoT Hub (device management + ingestion)
       ↓
  Azure Event Hubs (32 partitions, 33K msg/sec)
       ↓
  ┌────────────────────────────────────────┐
  │           Processing Paths             │
  ├────────────────────────────────────────┤
  │ Hot Path (real-time):                  │
  │   Stream Analytics → Azure Cache       │
  │   (anomaly detection, alerts)          │
  │                                        │
  │ Warm Path (near-real-time):            │
  │   Azure Functions → Cosmos DB          │
  │   (5-min aggregations, dashboards)     │
  │                                        │
  │ Cold Path (batch):                     │
  │   ADLS Gen2 → Synapse Analytics        │
  │   (historical analysis, ML training)   │
  └────────────────────────────────────────┘

Device Management:
  IoT Hub Device Twin → store device state
  Direct Methods → send commands to devices
  IoT Hub Jobs → bulk OTA updates

Key Azure services:
  IoT Hub:          Device connectivity, management
  Event Hubs:       High-throughput message ingestion
  Stream Analytics: Real-time SQL processing
  Cosmos DB:        Device state, recent telemetry
  ADLS Gen2:        Raw telemetry storage
  Synapse:          Historical analytics
  Azure Functions:  Event-driven processing
```

---

## Case Study 3: Design a Healthcare Data Platform on Azure

```
Requirements:
  - Store and process patient records (HIPAA compliant)
  - Real-time clinical alerts
  - ML-powered diagnosis assistance
  - Audit trail for all data access

Architecture:
  ┌─────────────────────────────────────────────────────────┐
  │                  Security Perimeter                      │
  │  Azure AD (identity) + Conditional Access               │
  │  Private Endpoints (no public internet)                 │
  │  Customer-managed encryption keys (Azure Key Vault)     │
  └─────────────────────────────────────────────────────────┘
                              ↓
  ┌─────────────────────────────────────────────────────────┐
  │                  Data Ingestion                          │
  │  EHR Systems → ADF (HL7/FHIR transformation)           │
  │  Medical Devices → IoT Hub → Event Hubs                │
  └─────────────────────────────────────────────────────────┘
                              ↓
  ┌─────────────────────────────────────────────────────────┐
  │                  Data Platform                           │
  │  Bronze: ADLS Gen2 (raw FHIR records)                  │
  │  Silver: Synapse (cleaned, standardized)               │
  │  Gold:   Azure SQL (analytics-ready)                   │
  └─────────────────────────────────────────────────────────┘
                              ↓
  ┌─────────────────────────────────────────────────────────┐
  │                  AI/ML Layer                             │
  │  Azure ML → diagnosis assistance models                 │
  │  Cognitive Services → medical image analysis            │
  │  Azure OpenAI → clinical note summarization             │
  └─────────────────────────────────────────────────────────┘

HIPAA Compliance:
  - All data encrypted at rest (CMK) and in transit (TLS 1.3)
  - Azure Policy: enforce encryption, private endpoints
  - Audit logs: Azure Monitor + Log Analytics (7-year retention)
  - Access control: RBAC + Azure AD PIM (just-in-time access)
  - Data residency: Azure Policy restricts to approved regions
  - BAA (Business Associate Agreement) with Microsoft
```

---

## Case Study 4: Design a CI/CD Platform for 1000 Developers

```
Requirements:
  - 1000 developers, 500 repos
  - 10,000 pipeline runs/day
  - < 10 min build time for most projects
  - Isolated environments per team

Architecture:
  GitHub/Azure Repos
       ↓ Webhook
  Azure DevOps Pipelines
       ↓
  ┌────────────────────────────────────────┐
  │           Build Agents                 │
  │  Microsoft-hosted: standard builds     │
  │  Self-hosted (AKS): GPU/custom builds  │
  │  Scale Set agents: auto-scale 0→100    │
  └────────────────────────────────────────┘
       ↓
  Azure Container Registry (ACR)
  (built images, scan on push)
       ↓
  ┌────────────────────────────────────────┐
  │         Deployment Targets             │
  │  Dev:     AKS (shared, auto-deploy)    │
  │  Staging: AKS (dedicated, manual gate) │
  │  Prod:    AKS (blue/green, approval)   │
  └────────────────────────────────────────┘
       ↓
  Azure Monitor + Application Insights
  (deployment tracking, rollback triggers)

Cost optimization:
  - Scale Set agents: pay only when building (0 idle cost)
  - Spot VMs for non-critical builds (70% cheaper)
  - Cache dependencies in Azure Artifacts
  - Parallel jobs: reduce wall-clock time
```

---

## Azure System Design Interview Framework

```
Key Azure-specific considerations:

1. IDENTITY: Always start with Azure AD
   - Managed Identities for service-to-service auth
   - No credentials in code or config
   - Conditional Access for human users

2. NETWORKING: Private by default
   - Private Endpoints for all PaaS services
   - VNet integration for App Service/Functions
   - Azure Firewall for egress control

3. STORAGE: Choose the right tier
   - Hot/Cool/Archive for Blob Storage
   - Premium for low-latency (< 1ms)
   - ZRS for zone redundancy, GRS for geo

4. COMPUTE: Match to workload
   - App Service: web apps, APIs
   - Functions: event-driven, serverless
   - AKS: containers, microservices
   - Batch: large-scale parallel jobs

5. MONITORING: Observability from day 1
   - Application Insights for APM
   - Log Analytics for centralized logs
   - Azure Monitor for infrastructure metrics
   - Alerts → Action Groups → PagerDuty/Teams
```

---

## Interview Q&A

### Q1: How do you design for zero-downtime deployments on Azure?
1. **App Service deployment slots**: Deploy to staging, swap to production (atomic, instant rollback)
2. **AKS rolling updates**: `maxSurge=1, maxUnavailable=0` — new pods before old ones terminate
3. **Azure Front Door**: Traffic splitting — route 10% to new version (canary)
4. **Blue/green with Traffic Manager**: Two identical environments, DNS switch
5. **Feature flags**: Azure App Configuration — deploy code, enable features gradually

### Q2: When would you use Cosmos DB vs Azure SQL?
**Cosmos DB**: Global distribution, multi-model (document, graph, key-value), < 10ms reads globally, auto-scaling, schema-flexible. Use for: user profiles, product catalogs, IoT telemetry, gaming leaderboards.
**Azure SQL**: Complex queries with JOINs, ACID transactions, existing SQL expertise, reporting. Use for: financial data, order management, ERP systems.
Rule: Cosmos DB for global scale + flexibility; Azure SQL for complex relational data + strong consistency.

### Q3: How do you handle a traffic spike 10x normal on Azure?
1. **App Service**: Auto-scale rules (CPU > 70% → add instances), scale-out in 2-5 min
2. **Azure Functions**: Scales automatically (serverless)
3. **AKS**: Cluster Autoscaler + KEDA for event-driven scaling
4. **Azure Front Door**: WAF rate limiting to protect backend
5. **Azure Cache for Redis**: Absorb read traffic (cache hit rate > 90%)
6. **Pre-warming**: Scheduled scale-out before known events (Black Friday)
7. **Azure Load Testing**: Test capacity before the event

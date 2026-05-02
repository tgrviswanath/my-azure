# Azure Architecture — High Availability, DR & Multi-Region

## High Availability Design Patterns

### SLA Composite Calculation
```
Composite SLA = SLA_A × SLA_B × SLA_C

Example: Web App (99.95%) + SQL DB (99.99%) + Redis (99.9%)
= 0.9995 × 0.9999 × 0.999 = 99.84%

To improve: add redundancy
  Active-Active:  both instances serve traffic simultaneously
  Active-Passive: standby takes over on failure (higher RTO)

SLA Reference:
  VM (single):          99.9%  (Premium SSD)
  VM (Avail Set):       99.95%
  VM (Avail Zones):     99.99%
  App Service:          99.95%
  Azure SQL (GP):       99.99%
  Azure SQL (BC):       99.995%
  Cosmos DB:            99.999% (multi-region write)
  Storage (ZRS):        99.9%
  Storage (GZRS):       99.99%
```

### Hub-Spoke Network Architecture
```
Hub VNet (shared services)
├── Azure Firewall / NVA
├── VPN Gateway / ExpressRoute
├── Azure Bastion
├── DNS Resolver
└── Shared services (AD, monitoring)

Spoke VNets (workloads)
├── Spoke-1: Production app
├── Spoke-2: Development
├── Spoke-3: Data platform
└── Spoke-4: DMZ

Benefits:
  - Centralized security (firewall in hub)
  - Shared connectivity (VPN/ExpressRoute once)
  - Isolation between spokes
  - Cost optimization (shared resources)
```

## Disaster Recovery

```
RTO (Recovery Time Objective):  How long can you be down?
RPO (Recovery Point Objective): How much data can you lose?

DR Strategies (cost vs recovery speed):
  Backup & Restore:    Hours RTO, hours RPO. Cheapest.
  Pilot Light:         Minutes RTO, minutes RPO. Core infra always on.
  Warm Standby:        Minutes RTO, seconds RPO. Scaled-down replica.
  Active-Active:       Near-zero RTO/RPO. Most expensive.
```

```bash
# Azure Site Recovery (VM replication)
az site-recovery vault create \
  --name rsv-dr-westus \
  --resource-group $RG_DR \
  --location westus

# Enable replication for VM
az site-recovery protected-item create \
  --vault-name rsv-dr-westus \
  --resource-group $RG_DR \
  --fabric-name "Azure" \
  --protection-container-name "asr-a2a-default-eastus-container" \
  --name $VM_NAME \
  --policy-id $POLICY_ID

# Test failover
az site-recovery protected-item planned-failover \
  --vault-name rsv-dr-westus \
  --resource-group $RG_DR \
  --fabric-name "Azure" \
  --protection-container-name "container" \
  --name $VM_NAME \
  --failover-direction PrimaryToRecovery
```

## Multi-Region Architecture

```
Active-Active Multi-Region:
  ┌─────────────────────────────────────────────┐
  │              Azure Front Door                │
  │         (Global load balancing + WAF)        │
  └──────────────┬──────────────────────────────┘
                 │
        ┌────────┴────────┐
        ▼                 ▼
  ┌──────────┐      ┌──────────┐
  │ East US  │      │ West EU  │
  │ App Svc  │      │ App Svc  │
  │ SQL DB   │◄────►│ SQL DB   │  (Failover Group)
  │ Redis    │      │ Redis    │
  └──────────┘      └──────────┘
```

```bash
# Azure Front Door (global load balancing)
az afd profile create \
  --profile-name afd-myapp-prod \
  --resource-group $RG \
  --sku Premium_AzureFrontDoor

az afd endpoint create \
  --endpoint-name myapp \
  --profile-name afd-myapp-prod \
  --resource-group $RG

az afd origin-group create \
  --origin-group-name og-webapp \
  --profile-name afd-myapp-prod \
  --resource-group $RG \
  --probe-request-type GET \
  --probe-protocol Https \
  --probe-interval-in-seconds 30 \
  --probe-path /health \
  --sample-size 4 \
  --successful-samples-required 3

# Add origins (East US + West Europe)
az afd origin create \
  --origin-name origin-eastus \
  --profile-name afd-myapp-prod \
  --resource-group $RG \
  --origin-group-name og-webapp \
  --host-name app-myapp-prod-eastus.azurewebsites.net \
  --priority 1 \
  --weight 1000

az afd origin create \
  --origin-name origin-westeurope \
  --profile-name afd-myapp-prod \
  --resource-group $RG \
  --origin-group-name og-webapp \
  --host-name app-myapp-prod-westeurope.azurewebsites.net \
  --priority 1 \
  --weight 1000
```

## Microservices Architecture

```
Event-Driven Microservices on Azure:

  ┌──────────┐    ┌─────────────┐    ┌──────────────┐
  │  Client  │───►│ API Gateway │───►│ Order Service│
  └──────────┘    │(APIM/AGW)   │    └──────┬───────┘
                  └─────────────┘           │ Event
                                            ▼
                                    ┌──────────────┐
                                    │ Service Bus  │
                                    │  (Topic)     │
                                    └──────┬───────┘
                                           │
                          ┌────────────────┼────────────────┐
                          ▼                ▼                ▼
                  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
                  │  Inventory   │ │   Payment    │ │Notification  │
                  │   Service    │ │   Service    │ │   Service    │
                  └──────────────┘ └──────────────┘ └──────────────┘

Azure Services for Microservices:
  API Gateway:    Azure API Management (APIM)
  Service Mesh:   AKS + Istio / Dapr
  Messaging:      Service Bus (reliable), Event Grid (events), Event Hubs (streaming)
  Service Discovery: AKS DNS, Azure Container Apps
  Config:         Azure App Configuration
  Secrets:        Key Vault
  Tracing:        Application Insights distributed tracing
```

## Cost Optimization Architecture

```
Cost Optimization Strategies:

1. Right-sizing:
   - Use Azure Advisor recommendations
   - Monitor actual utilization (CPU, memory)
   - Downsize over-provisioned resources

2. Reserved Instances:
   - 1-year: ~40% savings
   - 3-year: ~60-72% savings
   - Best for: predictable, always-on workloads

3. Spot/Low-priority VMs:
   - Up to 90% savings
   - Can be evicted with 30s notice
   - Best for: batch jobs, dev/test, fault-tolerant workloads

4. Auto-scaling:
   - Scale to zero when not needed
   - Schedule-based scaling for predictable patterns
   - Metric-based for variable load

5. Storage optimization:
   - Lifecycle policies (Hot → Cool → Archive)
   - Delete orphaned disks, snapshots
   - Use appropriate redundancy (LRS for dev, ZRS for prod)

6. Networking:
   - Minimize cross-region data transfer
   - Use CDN for static content
   - Consolidate VPN gateways

7. Dev/Test:
   - Use Dev/Test subscription pricing
   - Auto-shutdown VMs at night
   - Use B-series burstable VMs
```

## Interview Questions

### Q1: How do you design for 99.99% availability in Azure?
**Answer:**
1. Deploy across **Availability Zones** (3 zones per region)
2. Use **zone-redundant** services (SQL Business Critical, ZRS storage)
3. **Multi-region active-active** with Azure Front Door
4. **Auto-scaling** to handle traffic spikes
5. **Health probes** and circuit breakers
6. **Graceful degradation** — partial functionality when dependencies fail
7. **Chaos engineering** — test failure scenarios

### Q2: What is the difference between RTO and RPO?
**Answer:**
- **RTO** (Recovery Time Objective): Maximum acceptable downtime. "How long can we be offline?" If RTO = 1 hour, system must be restored within 1 hour.
- **RPO** (Recovery Point Objective): Maximum acceptable data loss. "How much data can we lose?" If RPO = 15 minutes, backups must be taken every 15 minutes.
- Lower RTO/RPO = higher cost. Balance based on business requirements.

### Q3: When would you use Service Bus vs Event Grid vs Event Hubs?
**Answer:**
- **Service Bus**: Reliable message queuing, guaranteed delivery, ordering, dead-letter queue. Use for: order processing, financial transactions, command patterns.
- **Event Grid**: Event routing, push-based, serverless triggers. Use for: reacting to Azure resource changes, webhook notifications, event-driven automation.
- **Event Hubs**: High-throughput event streaming (millions/sec), Kafka-compatible, time-series data. Use for: telemetry, logs, IoT data, analytics pipelines.

### Q4: What is the hub-spoke network topology and why use it?
**Answer:**
Hub-spoke has a central hub VNet with shared services (firewall, VPN, Bastion) and spoke VNets for workloads. Benefits:
- Centralized security policy (firewall in hub)
- Shared connectivity (one VPN/ExpressRoute)
- Workload isolation (spokes can't communicate directly)
- Cost savings (shared infrastructure)
- Simplified management

# Azure Service Selection Guide — Decision Trees

## Compute Decision Tree

```
What are you deploying?
│
├── Web app / REST API
│   ├── Need full OS control?          → Virtual Machine
│   ├── Containerized?
│   │   ├── Simple, no orchestration?  → Azure Container Instances
│   │   ├── Need orchestration?        → AKS or Azure Container Apps
│   │   └── Serverless containers?     → Azure Container Apps
│   ├── Event-driven / short tasks?    → Azure Functions
│   └── Standard web app?             → App Service
│
├── Batch / HPC workloads             → Azure Batch
├── Spring Boot microservices         → Azure Spring Apps
└── ML training / inference           → Azure Machine Learning
```

## Storage Decision Tree

```
What type of data?
│
├── Files / documents / images        → Blob Storage
│   ├── Need file system semantics?   → Azure Files (SMB/NFS)
│   ├── Big data analytics?           → ADLS Gen2 (HNS enabled)
│   └── High-performance NFS?         → Azure NetApp Files
│
├── Messages / events
│   ├── Simple queue?                 → Storage Queue (cheapest)
│   ├── Enterprise messaging?         → Service Bus
│   ├── Event routing?                → Event Grid
│   └── High-throughput streaming?    → Event Hubs
│
└── VM disks                          → Managed Disks
    ├── OS disk?                      → Premium SSD (P10+)
    ├── Data disk, high IOPS?         → Ultra Disk
    └── Backup / archive?             → Standard HDD
```

## Database Decision Tree

```
What type of data?
│
├── Relational / SQL
│   ├── New cloud-native app?         → Azure SQL Database
│   ├── Migrating SQL Server?         → SQL Managed Instance
│   ├── PostgreSQL?                   → Azure DB for PostgreSQL Flexible
│   ├── MySQL?                        → Azure DB for MySQL Flexible
│   └── Need full VM control?         → SQL Server on VM
│
├── NoSQL
│   ├── Global distribution needed?   → Cosmos DB
│   │   ├── JSON documents?           → Cosmos DB SQL API
│   │   ├── MongoDB migration?        → Cosmos DB MongoDB API
│   │   ├── Cassandra migration?      → Cosmos DB Cassandra API
│   │   └── Graph data?               → Cosmos DB Gremlin API
│   └── Simple key-value?             → Cosmos DB Table API
│
├── Caching / session                 → Azure Cache for Redis
├── Analytics / data warehouse        → Azure Synapse Analytics
├── Search                            → Azure Cognitive Search
└── Time-series / IoT                 → Azure Data Explorer
```

## Networking Decision Tree

```
Need to connect...
│
├── Resources within Azure
│   ├── Same region?                  → VNet (free)
│   ├── Different regions?            → VNet Peering
│   └── Hub-spoke topology?           → Azure Virtual WAN
│
├── On-premises to Azure
│   ├── Dev/test, low bandwidth?      → VPN Gateway (Site-to-Site)
│   ├── Individual users?             → VPN Gateway (Point-to-Site)
│   └── Enterprise, high bandwidth?   → ExpressRoute
│
├── Internet to Azure services
│   ├── Web app, need WAF?            → Application Gateway v2
│   ├── Global, multi-region?         → Azure Front Door
│   ├── DNS-based routing?            → Traffic Manager
│   └── Simple TCP/UDP?               → Azure Load Balancer
│
└── Secure access to VMs
    ├── No public IP needed?          → Azure Bastion
    └── Need JIT access?              → Defender for Cloud JIT
```

## Security Decision Tree

```
What do you need to secure?
│
├── Identity
│   ├── User authentication?          → Azure AD (Entra ID)
│   ├── Customer identities?          → Azure AD B2C
│   ├── External partners?            → Azure AD B2B
│   └── App-to-app auth?              → Managed Identity
│
├── Secrets / keys / certificates     → Key Vault
│
├── Network
│   ├── Subnet-level filtering?       → NSG
│   ├── Centralized firewall?         → Azure Firewall
│   ├── DDoS protection?              → DDoS Protection Standard
│   └── Private service access?       → Private Endpoints
│
├── Workloads
│   ├── VM security?                  → Defender for Servers
│   ├── Container security?           → Defender for Containers
│   ├── Database security?            → Defender for SQL/Cosmos
│   └── Overall posture?              → Defender for Cloud
│
└── Compliance / governance
    ├── Policy enforcement?           → Azure Policy
    ├── Audit logging?                → Activity Log + Log Analytics
    └── SIEM/SOAR?                    → Microsoft Sentinel
```

## Cost Optimization Decision Tree

```
How to reduce costs?
│
├── Compute
│   ├── Predictable workload?         → Reserved Instances (1-3yr)
│   ├── Variable but committed?       → Azure Savings Plans
│   ├── Fault-tolerant batch?         → Spot VMs (up to 90% off)
│   ├── Dev/test?                     → Dev/Test pricing + auto-shutdown
│   └── Existing licenses?            → Azure Hybrid Benefit
│
├── Storage
│   ├── Infrequent access?            → Cool tier
│   ├── Rarely accessed?              → Archive tier
│   └── Automate tiering?             → Lifecycle management policies
│
├── Databases
│   ├── Variable traffic?             → Cosmos DB Serverless
│   ├── Multiple small DBs?           → Elastic Pool
│   └── Predictable load?             → Reserved capacity
│
└── Architecture
    ├── Variable traffic?             → Auto-scaling + scale to zero
    ├── Event-driven?                 → Serverless (Functions)
    └── Static content?               → CDN (reduce origin load)
```

## Monitoring Decision Tree

```
What do you need to monitor?
│
├── Application performance           → Application Insights
│   ├── Request tracing?              → Distributed tracing
│   ├── Dependency tracking?          → Dependency map
│   └── Custom metrics?               → TrackMetric / TrackEvent
│
├── Infrastructure metrics            → Azure Monitor Metrics
│   ├── VM CPU/memory?                → VM Insights
│   ├── Container metrics?            → Container Insights
│   └── Network?                      → Network Insights
│
├── Logs / audit trail                → Log Analytics (KQL)
│   ├── Security events?              → Microsoft Sentinel
│   ├── Activity log?                 → Azure Activity Log
│   └── Resource diagnostics?         → Diagnostic Settings
│
└── Alerts
    ├── Metric threshold?             → Metric Alert
    ├── Log query result?             → Log Alert (Scheduled Query)
    └── Azure service health?         → Service Health Alert
```

## Quick Reference: Service Limits

| Service | Key Limit |
|---------|-----------|
| App Service | 100 apps per plan (Standard+) |
| Azure Functions | 200 instances (Consumption) |
| AKS | 5000 nodes per cluster |
| Cosmos DB | 20GB per logical partition |
| Azure SQL | 4TB per database (Hyperscale: 100TB) |
| Storage Account | 5PB capacity, 20,000 IOPS |
| Key Vault | 25,000 transactions/10s |
| Event Hubs | 1MB max message size |
| Service Bus | 256KB (Standard), 100MB (Premium) |
| VNet | 65,536 IP addresses per subnet |
| NSG | 1000 rules per NSG |

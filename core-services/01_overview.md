# Azure Core Services — Complete Overview

## Compute Services

| Service | Type | Use Case | Pricing Model |
|---------|------|----------|---------------|
| Virtual Machines | IaaS | Full control, lift-and-shift | Per second (running) |
| VM Scale Sets | IaaS | Auto-scaling VM groups | Per VM |
| App Service | PaaS | Web apps, APIs | Per App Service Plan |
| Azure Functions | Serverless | Event-driven, short tasks | Per execution |
| Azure Container Instances | PaaS | Simple containers, no orchestration | Per second |
| Azure Kubernetes Service | PaaS | Container orchestration | Per node VM |
| Azure Container Apps | PaaS | Microservices, serverless containers | Per vCPU/memory |
| Azure Batch | PaaS | Large-scale parallel jobs | Per VM |
| Azure Spring Apps | PaaS | Spring Boot microservices | Per instance |

## Storage Services

| Service | Type | Use Case |
|---------|------|----------|
| Blob Storage | Object | Unstructured data, backups, media |
| Azure Files | File share | SMB/NFS shares, lift-and-shift |
| Queue Storage | Message queue | Decoupled async communication |
| Table Storage | NoSQL | Simple key-value, IoT telemetry |
| Disk Storage | Block | VM OS and data disks |
| Data Lake Storage Gen2 | Object + hierarchy | Big data analytics |
| Azure NetApp Files | Enterprise NFS | High-performance file workloads |

## Database Services

| Service | Type | Use Case |
|---------|------|----------|
| Azure SQL Database | Relational | Cloud-native SQL Server |
| SQL Managed Instance | Relational | SQL Server migration |
| Azure Database for PostgreSQL | Relational | Open-source PostgreSQL |
| Azure Database for MySQL | Relational | Open-source MySQL |
| Azure Database for MariaDB | Relational | Open-source MariaDB |
| Cosmos DB | Multi-model NoSQL | Global distribution, multiple APIs |
| Azure Cache for Redis | In-memory | Caching, session, pub/sub |
| Azure Synapse Analytics | Data warehouse | Analytics at scale |
| Azure Database for PostgreSQL Flexible | Relational | Flexible server PostgreSQL |

## Networking Services

| Service | Use Case |
|---------|----------|
| Virtual Network (VNet) | Private network in Azure |
| VNet Peering | Connect VNets |
| VPN Gateway | Site-to-site, point-to-site VPN |
| ExpressRoute | Dedicated private connection to Azure |
| Azure Firewall | Managed cloud-native firewall |
| Application Gateway | L7 load balancer + WAF |
| Azure Load Balancer | L4 load balancer |
| Azure Front Door | Global L7 load balancer + CDN |
| Traffic Manager | DNS-based global routing |
| Azure CDN | Content delivery network |
| Azure Bastion | Secure RDP/SSH without public IP |
| Private Link / Private Endpoint | Private access to Azure services |
| Azure DNS | DNS hosting |
| DDoS Protection | DDoS mitigation |
| Network Watcher | Network monitoring and diagnostics |

## Identity & Security Services

| Service | Use Case |
|---------|----------|
| Azure Active Directory (Entra ID) | Cloud identity platform |
| Azure AD B2C | Customer identity |
| Azure AD B2B | External user collaboration |
| Key Vault | Secrets, keys, certificates |
| Microsoft Defender for Cloud | Security posture + threat protection |
| Microsoft Sentinel | SIEM + SOAR |
| Azure DDoS Protection | DDoS mitigation |
| Azure Information Protection | Data classification + protection |
| Microsoft Purview | Data governance |

## DevOps & Management Services

| Service | Use Case |
|---------|----------|
| Azure DevOps | CI/CD, boards, repos, artifacts |
| GitHub Actions | CI/CD integrated with GitHub |
| Azure Resource Manager | Deployment and management |
| Azure Bicep | IaC DSL (compiles to ARM) |
| Azure Policy | Governance and compliance |
| Azure Blueprints | Repeatable compliant environments |
| Azure Arc | Manage on-premises + multi-cloud |
| Azure Automation | Runbooks, DSC, update management |
| Azure Advisor | Personalized recommendations |
| Azure Cost Management | Cost analysis and optimization |

## Monitoring & Analytics Services

| Service | Use Case |
|---------|----------|
| Azure Monitor | Metrics, logs, alerts |
| Log Analytics | Query logs with KQL |
| Application Insights | APM for applications |
| Azure Service Health | Azure service status |
| Azure Resource Health | Individual resource health |
| Azure Workbooks | Interactive reports |
| Azure Dashboards | Custom monitoring dashboards |

## Integration & Messaging Services

| Service | Use Case |
|---------|----------|
| Service Bus | Enterprise messaging, queues, topics |
| Event Grid | Event routing, serverless triggers |
| Event Hubs | High-throughput event streaming |
| Logic Apps | Workflow automation, connectors |
| API Management | API gateway, developer portal |
| Azure Relay | Hybrid connections |
| Azure Notification Hubs | Push notifications at scale |

## AI & ML Services

| Service | Use Case |
|---------|----------|
| Azure OpenAI | GPT-4, DALL-E, Whisper |
| Azure Cognitive Services | Vision, Speech, Language, Decision |
| Azure Machine Learning | ML platform, MLOps |
| Azure Bot Service | Conversational AI |
| Azure Search | AI-powered search |

---

## Service Selection Guide

### Web Application
```
Simple static site:     Azure Static Web Apps (free tier)
Web app + API:          App Service (PaaS, managed)
Containerized app:      Azure Container Apps (serverless containers)
High-traffic global:    App Service + Front Door + Redis
```

### Database Selection
```
Relational, new app:    Azure SQL Database (GP tier)
SQL Server migration:   SQL Managed Instance
PostgreSQL:             Azure Database for PostgreSQL Flexible
Global NoSQL:           Cosmos DB (choose API based on use case)
Caching:                Azure Cache for Redis
Analytics:              Azure Synapse Analytics
```

### Messaging Selection
```
Reliable delivery:      Service Bus (queues/topics)
Event routing:          Event Grid (push-based, serverless)
High-throughput stream: Event Hubs (Kafka-compatible)
Simple queue:           Storage Queue (cheapest)
```

### Compute Selection
```
Full control:           Virtual Machines
Web/API app:            App Service
Event-driven:           Azure Functions
Containers (simple):    Azure Container Instances
Containers (complex):   AKS or Azure Container Apps
Batch processing:       Azure Batch
```

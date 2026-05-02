# AZ-900 Interview Questions — Azure Fundamentals

## Cloud Concepts (15-20%)

### Q1: What are the three cloud service models?
**IaaS** (Infrastructure as a Service): You manage OS and above. Azure manages physical infrastructure. Example: Azure VMs.
**PaaS** (Platform as a Service): You manage app and data. Azure manages everything else. Example: App Service.
**SaaS** (Software as a Service): You use the software. Azure manages everything. Example: Microsoft 365.

### Q2: What is the shared responsibility model?
Responsibility is shared between Microsoft and the customer:
- **Always Microsoft**: physical datacenter, network, hosts
- **Always Customer**: data, accounts, access management
- **Shared (varies by model)**: OS, network controls, applications, identity

### Q3: What are the benefits of cloud computing?
1. **High availability**: SLAs guarantee uptime
2. **Scalability**: scale up/out on demand
3. **Elasticity**: auto-scale based on demand
4. **Agility**: deploy resources in minutes
5. **Geo-distribution**: deploy globally
6. **Disaster recovery**: built-in backup/replication
7. **CapEx → OpEx**: pay-as-you-go, no upfront investment

### Q4: What is the difference between CapEx and OpEx?
- **CapEx** (Capital Expenditure): Upfront investment in physical infrastructure. Fixed cost, depreciated over time. On-premises model.
- **OpEx** (Operational Expenditure): Pay for services as you use them. Variable cost. Cloud model.

---

## Core Azure Services (30-35%)

### Q5: What is an Azure Region?
A geographic area containing one or more datacenters. Azure has 60+ regions worldwide. Each region is paired with another for disaster recovery. Data residency is maintained within the geography.

### Q6: What is an Availability Zone?
Physically separate datacenters within a region with independent power, cooling, and networking. Minimum 3 zones per region. Protects against datacenter-level failures. SLA: 99.99% for zone-redundant services.

### Q7: What is Azure Resource Manager (ARM)?
ARM is the deployment and management service for Azure. All Azure operations go through ARM. Provides: consistent management layer, RBAC, tagging, templates (IaC), resource groups.

### Q8: What is the difference between Azure SQL Database and Azure SQL Managed Instance?
- **SQL Database**: Fully managed PaaS. Some SQL Server features not available. Best for new cloud-native apps.
- **SQL Managed Instance**: Near 100% SQL Server compatibility. VNet injection. Best for lift-and-shift migrations.

### Q9: What is Azure Blob Storage used for?
Unstructured data storage: images, videos, documents, backups, logs, static website content. Three types: Block blobs (files), Append blobs (logs), Page blobs (VHD disks).

### Q10: What is Azure Active Directory?
Microsoft's cloud identity platform. Provides: authentication (OAuth 2.0, OIDC), authorization (RBAC), MFA, Conditional Access, B2B/B2C. Different from on-premises Active Directory Domain Services.

---

## Security, Privacy, Compliance (25-30%)

### Q11: What is Azure RBAC?
Role-Based Access Control assigns permissions to security principals (users, groups, service principals) at a scope (management group, subscription, resource group, resource). Built-in roles: Owner, Contributor, Reader.

### Q12: What is Azure Key Vault?
Managed service for storing and accessing secrets, keys, and certificates. Provides: hardware security modules (HSM), access logging, soft delete, purge protection. Use for: database passwords, API keys, TLS certificates.

### Q13: What is Microsoft Defender for Cloud?
Unified security management and threat protection. Provides: security posture assessment, threat detection, regulatory compliance, secure score, recommendations. Covers: VMs, containers, databases, storage, App Service.

### Q14: What is Azure Policy?
Service for creating, assigning, and managing policies that enforce rules on Azure resources. Examples: "All resources must have tags", "Only allow certain VM sizes", "Storage must use HTTPS". Evaluates compliance and can auto-remediate.

---

## Azure Pricing and Lifecycle (20-25%)

### Q15: What factors affect Azure pricing?
1. **Resource type**: different services have different pricing models
2. **Usage**: pay-as-you-go, per second/minute/hour
3. **Region**: prices vary by region
4. **Bandwidth**: outbound data transfer costs
5. **Reserved capacity**: commit for 1-3 years for discounts
6. **Azure Hybrid Benefit**: use existing licenses

### Q16: What is the Azure Free Account?
- 12 months of popular services free
- $200 credit for 30 days
- 55+ always-free services
- Examples: 750 hours B1s VM, 5GB Blob storage, 250GB SQL Database

### Q17: What is the Azure SLA?
Service Level Agreement defines the uptime guarantee. If Azure fails to meet the SLA, customers receive service credits. SLAs range from 99.9% to 99.999% depending on service and configuration.

### Q18: What is the Azure Total Cost of Ownership (TCO) Calculator?
Tool to estimate cost savings by migrating from on-premises to Azure. Compares: hardware, software, IT labor, datacenter costs vs Azure costs.

---

## Scenario Questions

### S1: A company needs to run a web application with 99.99% availability. What do you recommend?
- Deploy across **Availability Zones** (3 zones)
- Use **App Service** with zone redundancy (Premium v3)
- **Azure SQL** Business Critical (zone-redundant)
- **Azure Front Door** for global load balancing
- **Auto-scaling** for traffic spikes
- **Deployment slots** for zero-downtime deployments

### S2: A startup wants to minimize costs for a new application. What do you recommend?
- **Azure Functions** (Consumption plan) — pay per execution, first 1M free
- **Cosmos DB Serverless** — pay per RU consumed
- **Azure Static Web Apps** — free tier for frontend
- **Azure SQL** Basic tier for small databases
- **Azure Cache for Redis** Basic C0 for caching
- Set up **budgets and alerts** to monitor spending

### S3: A company needs to store 100TB of archive data cost-effectively. What do you recommend?
- **Azure Blob Storage Archive tier** — lowest cost (~$0.001/GB/month)
- **Lifecycle management policy** — automatically move data to Archive after 180 days
- **ZRS or GRS** redundancy based on compliance requirements
- **Immutable storage** if compliance requires WORM (Write Once Read Many)

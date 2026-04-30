# Azure Fundamentals — Cloud Concepts & Global Infrastructure

## Cloud Computing Models

### Service Models
```
IaaS (Infrastructure as a Service)
├── You manage: OS, runtime, middleware, apps, data
├── Azure manages: virtualization, servers, storage, networking
├── Examples: Azure VMs, Azure Storage, Azure VNet
└── Use when: full control needed, lift-and-shift migrations

PaaS (Platform as a Service)
├── You manage: apps, data
├── Azure manages: OS, runtime, middleware, infrastructure
├── Examples: App Service, Azure SQL, Azure Functions
└── Use when: focus on app development, not infrastructure

SaaS (Software as a Service)
├── You manage: data, access
├── Azure manages: everything else
├── Examples: Microsoft 365, Dynamics 365, Azure DevOps
└── Use when: ready-to-use software needed

Serverless (subset of PaaS)
├── Event-driven, auto-scaling, pay-per-execution
├── Examples: Azure Functions, Logic Apps, Event Grid
└── Use when: event-driven workloads, variable traffic
```

### Deployment Models
```
Public Cloud:   Resources on Azure's shared infrastructure
Private Cloud:  Resources on dedicated infrastructure (Azure Stack)
Hybrid Cloud:   Mix of on-premises + public cloud (Azure Arc)
Multi-Cloud:    Multiple cloud providers (Azure + AWS/GCP)
```

---

## Azure Global Infrastructure

### Regions
Azure has **60+ regions** worldwide — more than any other cloud provider.

```
Region = geographic area containing one or more datacenters
├── East US (Virginia)
├── West Europe (Netherlands)
├── Southeast Asia (Singapore)
├── Australia East (New South Wales)
└── ...

Region Pairs:
├── Each region paired with another in same geography
├── Updates rolled out to one region at a time
├── Data residency maintained within geography
└── Examples: East US ↔ West US, North Europe ↔ West Europe
```

### Availability Zones (AZs)
```
Availability Zone = physically separate datacenter within a region
├── Each zone has independent power, cooling, networking
├── Connected via high-speed fiber (< 2ms latency)
├── Minimum 3 zones per region (where supported)
└── Protects against datacenter-level failures

Zone-redundant services: automatically replicate across zones
  Examples: Zone-redundant Storage, Azure SQL, App Gateway v2

Zonal services: pinned to specific zone
  Examples: VMs, managed disks, standard IPs
```

### Availability Sets (Legacy)
```
Availability Set = logical grouping within a datacenter
├── Fault Domains (FD): separate physical racks (power/network)
├── Update Domains (UD): groups updated during maintenance
├── SLA: 99.95% for 2+ VMs in availability set
└── Use AZs instead for new deployments
```

---

## Resource Organization

### Hierarchy
```
Azure Account (Microsoft Account / Work Account)
└── Tenant (Azure Active Directory)
    └── Management Groups (optional, for enterprise)
        └── Subscriptions (billing boundary, access boundary)
            └── Resource Groups (logical container)
                └── Resources (VMs, storage, databases, etc.)
```

### Resource Groups
```bash
# Create resource group
az group create \
  --name rg-myapp-prod-eastus \
  --location eastus \
  --tags Environment=Production Project=MyApp Owner=TeamA

# List resource groups
az group list --output table

# Delete resource group (deletes ALL resources inside)
az group delete --name rg-myapp-prod-eastus --yes --no-wait
```

**Naming Convention Best Practice:**
```
{resource-type}-{workload}-{environment}-{region}-{instance}
Examples:
  rg-webapp-prod-eastus
  vm-api-dev-westus-001
  st-data-prod-eastus (storage account, no hyphens)
  kv-secrets-prod-eastus
```

### Subscriptions
```
Subscription = billing unit + access boundary
├── Each subscription has limits (quotas)
├── Multiple subscriptions per tenant
├── Common patterns:
│   ├── Dev/Test subscription (lower cost)
│   ├── Production subscription
│   └── Sandbox subscription
└── Management Groups organize subscriptions
```

---

## Pricing & Cost Management

### Pricing Models
```
Pay-as-you-go:    Pay for what you use, no commitment
Reserved:         1 or 3 year commitment, up to 72% savings
Spot:             Use unused capacity, up to 90% savings (can be evicted)
Hybrid Benefit:   Use existing Windows Server / SQL Server licenses
Dev/Test:         Discounted rates for non-production workloads
```

### Cost Optimization Strategies
```
1. Right-sizing:     Match VM size to actual workload needs
2. Reserved Instances: Commit to 1-3 years for predictable workloads
3. Auto-scaling:     Scale down during off-peak hours
4. Spot VMs:         For fault-tolerant, interruptible workloads
5. Storage tiers:    Move cold data to Cool/Archive tiers
6. Delete unused:    Remove stopped VMs, orphaned disks, old snapshots
7. Azure Advisor:    Built-in recommendations for cost savings
8. Budgets + Alerts: Set spending limits with notifications
```

### Azure Cost Management
```bash
# View current month costs
az consumption usage list \
  --start-date 2024-01-01 \
  --end-date 2024-01-31 \
  --output table

# Create budget alert
az consumption budget create \
  --budget-name "monthly-budget" \
  --amount 1000 \
  --time-grain Monthly \
  --start-date 2024-01-01 \
  --end-date 2024-12-31 \
  --category Cost
```

---

## Interview Questions

### Q1: What is the difference between IaaS, PaaS, and SaaS?
**Answer:**
- **IaaS**: You manage OS and above. Azure manages physical infrastructure. Most control, most responsibility. Example: Azure VMs.
- **PaaS**: You manage application and data. Azure manages everything else. Faster development, less control. Example: App Service.
- **SaaS**: You use the software. Azure manages everything. No infrastructure management. Example: Microsoft 365.

### Q2: What is an Availability Zone and how does it differ from an Availability Set?
**Answer:**
- **Availability Zone**: Physically separate datacenter within a region with independent power/cooling/networking. Protects against datacenter failure. SLA: 99.99%.
- **Availability Set**: Logical grouping within a single datacenter using fault domains and update domains. Protects against rack-level failures and planned maintenance. SLA: 99.95%.
- **Recommendation**: Use Availability Zones for new deployments where supported.

### Q3: What is a Resource Group and what are the rules?
**Answer:**
- Logical container for Azure resources
- Resources can only be in ONE resource group
- Resources in different regions can be in the same resource group
- Deleting a resource group deletes ALL resources inside
- Used for lifecycle management, access control, and billing
- Best practice: group resources that share the same lifecycle

### Q4: What is the difference between a Subscription and a Tenant?
**Answer:**
- **Tenant**: Azure Active Directory instance. Represents an organization. Contains users, groups, and applications.
- **Subscription**: Billing and access boundary. Linked to a tenant. Contains resources. One tenant can have multiple subscriptions.

### Q5: How do you reduce Azure costs for a predictable workload?
**Answer:**
1. **Reserved Instances**: 1 or 3-year commitment for up to 72% savings
2. **Azure Hybrid Benefit**: Use existing Windows Server/SQL licenses
3. **Right-sizing**: Use Azure Advisor recommendations
4. **Auto-shutdown**: Schedule VMs to stop during off-hours
5. **Storage lifecycle policies**: Move data to cooler tiers automatically

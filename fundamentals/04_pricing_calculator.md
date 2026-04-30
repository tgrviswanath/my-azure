# Azure Pricing — Calculator, Models & Cost Estimation

## Pricing Models

```
Pay-as-you-go:    No commitment. Pay per second/minute/hour.
                  Best for: unpredictable workloads, new projects

Reserved (1yr):   ~40% savings vs PAYG. 1-year commitment.
                  Best for: stable, predictable production workloads

Reserved (3yr):   ~60-72% savings vs PAYG. 3-year commitment.
                  Best for: long-term stable workloads

Spot:             Up to 90% savings. Can be evicted with 30s notice.
                  Best for: batch jobs, CI/CD agents, fault-tolerant apps

Savings Plans:    Commit to hourly spend. Flexible (any size/region).
                  Best for: variable workloads needing flexibility

Hybrid Benefit:   Use existing Windows Server / SQL Server licenses.
                  Savings: up to 40% on Windows VMs, 55% on SQL

Dev/Test:         Discounted rates for non-production.
                  Requires Visual Studio subscription.
```

## Common Service Pricing (Approximate, East US, 2024)

### Compute
```
VM Sizes (Linux, PAYG):
  B1s  (1 vCPU, 1GB):   ~$7.59/month
  B2s  (2 vCPU, 4GB):   ~$30.37/month
  D2s_v5 (2 vCPU, 8GB): ~$69.35/month
  D4s_v5 (4 vCPU, 16GB):~$138.70/month
  D8s_v5 (8 vCPU, 32GB):~$277.40/month

App Service Plans (Linux):
  F1 (Free):    $0/month (60 min/day CPU)
  B1 (Basic):   ~$13.14/month
  S1 (Standard):~$56.94/month
  P1v3 (Premium):~$113.88/month
  P2v3:         ~$227.76/month

Azure Functions (Consumption):
  First 1M executions: FREE
  Additional: $0.20 per million
  Compute: $0.000016/GB-second
```

### Storage
```
Blob Storage (Standard, ZRS, East US):
  Hot tier:     $0.023/GB/month
  Cool tier:    $0.01/GB/month
  Cold tier:    $0.004/GB/month
  Archive tier: $0.00099/GB/month

  Operations (per 10,000):
    Hot read:   $0.004
    Hot write:  $0.05
    Archive rehydrate: $0.022/GB

Managed Disks:
  Standard HDD (S10, 128GB): ~$5.28/month
  Standard SSD (E10, 128GB): ~$10.21/month
  Premium SSD (P10, 128GB):  ~$19.71/month
  Ultra Disk (128GB, 1000 IOPS): ~$13.65/month
```

### Databases
```
Azure SQL Database (vCore, East US):
  General Purpose, 2 vCores: ~$368/month
  General Purpose, 4 vCores: ~$736/month
  Business Critical, 4 vCores: ~$1,472/month
  Hyperscale, 4 vCores: ~$736/month

  With 1-year Reserved: ~40% savings
  With Hybrid Benefit: ~55% savings

Cosmos DB:
  Provisioned: $0.008/RU/hour (100 RU/s = $0.008/hr = ~$5.76/month)
  Serverless: $0.25 per million RUs
  Storage: $0.25/GB/month

Azure Cache for Redis:
  Basic C0 (250MB): ~$16.06/month
  Standard C1 (1GB): ~$54.75/month
  Premium P1 (6GB): ~$328.50/month
```

### Networking
```
VNet: FREE
VNet Peering: $0.01/GB (intra-region), $0.02/GB (inter-region)
VPN Gateway: ~$27/month (Basic) to ~$1,400/month (VpnGw5AZ)
ExpressRoute: ~$55/month (50Mbps) to ~$5,000/month (10Gbps)
Azure Firewall: ~$1.25/hour + $0.016/GB processed
Application Gateway: ~$0.008/hour + $0.008/GB
Front Door: ~$0.01/GB + $0.008/10K requests
Load Balancer Standard: ~$0.025/hour + $0.005/GB

Bandwidth (outbound from Azure):
  First 100GB/month: FREE
  100GB - 10TB: $0.087/GB
  10TB - 50TB: $0.083/GB
```

## Cost Estimation Examples

### Small Web App (Dev/Test)
```
App Service B1:          $13/month
Azure SQL Basic:         $5/month
Storage (10GB):          $0.23/month
Application Insights:    $0 (5GB free)
─────────────────────────────────────
Total:                   ~$18/month
```

### Medium Production Web App
```
App Service P2v3 (2 instances): $456/month
Azure SQL GP_Gen5_4:            $736/month
Redis Cache Standard C1:        $55/month
Azure Front Door:               $50/month
Storage ZRS (100GB):            $2.30/month
Key Vault:                      $0 (10K ops free)
Application Insights (10GB):    $23/month
─────────────────────────────────────────────
Total:                          ~$1,322/month
With Reserved Instances (1yr):  ~$900/month
```

### AKS Microservices (Production)
```
AKS nodes (3x D4s_v5):         $416/month
Azure SQL (3x GP_Gen5_2):       $1,104/month
Redis Cache Standard C1:        $55/month
ACR Premium:                    $50/month
Service Bus Standard:           $10/month
Application Insights (20GB):    $46/month
Log Analytics (10GB):           $23/month
─────────────────────────────────────────────
Total:                          ~$1,704/month
```

## Cost Management Tools

```bash
# Azure Pricing Calculator (web)
# https://azure.microsoft.com/en-us/pricing/calculator/

# TCO Calculator (compare on-premises vs Azure)
# https://azure.microsoft.com/en-us/pricing/tco/calculator/

# Azure Cost Management CLI
az consumption usage list \
  --start-date 2024-01-01 \
  --end-date 2024-01-31 \
  --output table

# Get cost by resource group
az consumption usage list \
  --start-date 2024-01-01 \
  --end-date 2024-01-31 \
  --query "sort_by([].{Name:instanceName,Cost:pretaxCost}, &Cost) | reverse(@)" \
  --output table

# Create budget with alert
az consumption budget create \
  --budget-name "monthly-budget" \
  --amount 1000 \
  --time-grain Monthly \
  --start-date 2024-01-01 \
  --end-date 2024-12-31 \
  --category Cost \
  --notification-enabled true \
  --notification-threshold 80 \
  --notification-contact-emails "admin@company.com"

# Azure Advisor cost recommendations
az advisor recommendation list \
  --category Cost \
  --query "[].{Impact:impact,Recommendation:shortDescription.solution}" \
  --output table
```

## Interview Questions

### Q1: How do you estimate Azure costs before deploying?
**Answer:**
1. **Azure Pricing Calculator**: Build architecture, select services, get monthly estimate
2. **TCO Calculator**: Compare on-premises vs Azure costs
3. **Azure Advisor**: After deployment, get right-sizing recommendations
4. **Cost Management**: Set budgets and alerts before going live
5. **What-if analysis**: Use `az deployment group what-if` to preview resource changes

### Q2: What is the difference between Reserved Instances and Azure Savings Plans?
**Answer:**
- **Reserved Instances**: Commit to specific VM size, region, OS. Up to 72% savings. Inflexible — must match exact configuration.
- **Savings Plans**: Commit to hourly spend amount. Applies to any VM size/region/OS. More flexible. Up to 65% savings.
- Use RI for: stable, predictable workloads with known configuration.
- Use Savings Plans for: variable workloads, multiple regions, mixed VM sizes.

### Q3: How do you reduce Azure SQL Database costs?
**Answer:**
1. **Reserved capacity**: 1-year = ~33% savings, 3-year = ~40% savings
2. **Azure Hybrid Benefit**: Use existing SQL Server licenses (up to 55% savings)
3. **Right-sizing**: Use Query Performance Insight to identify over-provisioned DBs
4. **Elastic Pool**: Share DTUs/vCores across multiple databases
5. **Serverless**: Auto-pause when idle (dev/test)
6. **Hyperscale**: Pay for compute separately from storage
7. **Dev/Test pricing**: Discounted rates for non-production

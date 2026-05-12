# Project 2.2 — Multi-Tier Application Architecture

## What It Does

Deploys a production-grade multi-tier application on Azure:
- **Azure Front Door** — Global CDN + WAF + anycast routing
- **Application Gateway** — Regional L7 load balancer with WAF
- **VM Scale Sets** — Auto-scaling web tier
- **Azure SQL** — Managed relational database

This mirrors how real enterprise applications are deployed on Azure.

## Azure Services Used

| Service | Purpose |
|---|---|
| Azure Front Door (Standard) | Global load balancing, CDN, WAF |
| Application Gateway v2 | Regional L7 load balancing, SSL termination |
| VM Scale Sets (Linux) | Auto-scaling compute tier |
| Azure SQL Server + Database | Managed relational database |
| Virtual Network + Subnets | Network isolation |
| NSGs | Traffic filtering |

## How to Deploy

### Prerequisites
```bash
az login
az account set --subscription "<your-subscription-id>"
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Sql
```

### Deploy with Terraform
```bash
cd terraform/
terraform init
terraform plan -var="sql_admin_password=YourP@ssw0rd123" -out=tfplan
terraform apply tfplan
```

### Deploy with Azure CLI
```bash
# Resource group
az group create --name rg-multitier --location eastus

# VNet
az network vnet create \
  --resource-group rg-multitier \
  --name vnet-multitier \
  --address-prefix 10.1.0.0/16

# App Gateway subnet (requires /24 minimum)
az network vnet subnet create \
  --resource-group rg-multitier \
  --vnet-name vnet-multitier \
  --name subnet-appgw \
  --address-prefix 10.1.0.0/24

# VMSS subnet
az network vnet subnet create \
  --resource-group rg-multitier \
  --vnet-name vnet-multitier \
  --name subnet-vmss \
  --address-prefix 10.1.1.0/24
```

### Verify Health
```bash
pip install azure-mgmt-network azure-mgmt-compute azure-mgmt-sql azure-identity
python code/health_check.py --resource-group rg-multitier
```

### Cleanup
```bash
az group delete --name rg-multitier --yes --no-wait
```

## Lessons Learned

- **Application Gateway requires its own dedicated subnet** — no other resources can share it
- **Front Door + App Gateway** is a common pattern: Front Door handles global routing, App GW handles regional WAF + routing
- **VMSS health probes** — configure application health extension so Azure knows when instances are healthy
- **Azure SQL firewall rules** — by default, Azure SQL blocks all connections; you must explicitly allow your subnet or IP
- **App Gateway backend health** — check the backend health blade first when traffic isn't flowing
- **VMSS scaling policies** — scale out on CPU > 70%, scale in on CPU < 30% with a 5-minute cooldown

## Code

See `code/health_check.py` — checks Application Gateway state, VMSS instance count, and Azure SQL availability.

```bash
python code/health_check.py --resource-group rg-multitier --subscription-id <id>
```

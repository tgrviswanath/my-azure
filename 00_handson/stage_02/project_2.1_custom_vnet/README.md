# Project 2.1 — Custom VNet with Public/Private Subnets

## What It Does

Builds a production-style Azure Virtual Network with a 3-tier architecture:
- **Public Subnet** — Web tier (internet-facing, behind NSG)
- **Private App Subnet** — Application tier (no direct internet access)
- **Private DB Subnet** — Database tier (most restricted)
- **NAT Gateway** — Outbound internet for private subnets
- **Route Tables** — Custom routing to force traffic through NAT

This is the foundational networking pattern used in almost every real Azure deployment.

## Azure Services Used

| Service | Purpose |
|---|---|
| Azure Virtual Network | Core network isolation |
| Subnets (3x) | Tier separation |
| Network Security Groups | Inbound/outbound traffic rules |
| NAT Gateway | Outbound internet for private subnets |
| Public IP (Static) | NAT Gateway public IP |
| Route Tables | Custom routing |

## How to Deploy

### Prerequisites
```bash
az login
az account set --subscription "<your-subscription-id>"
```

### Option A — Azure CLI
```bash
# Create resource group
az group create --name rg-vnet-lab --location eastus

# Create VNet
az network vnet create \
  --resource-group rg-vnet-lab \
  --name vnet-main \
  --address-prefix 10.0.0.0/16 \
  --location eastus

# Create subnets
az network vnet subnet create \
  --resource-group rg-vnet-lab \
  --vnet-name vnet-main \
  --name subnet-web \
  --address-prefix 10.0.1.0/24

az network vnet subnet create \
  --resource-group rg-vnet-lab \
  --vnet-name vnet-main \
  --name subnet-app \
  --address-prefix 10.0.2.0/24

az network vnet subnet create \
  --resource-group rg-vnet-lab \
  --vnet-name vnet-main \
  --name subnet-db \
  --address-prefix 10.0.3.0/24
```

### Option B — Terraform
```bash
cd terraform/
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Cleanup
```bash
az group delete --name rg-vnet-lab --yes --no-wait
# or
terraform destroy
```

## Lessons Learned

- **VNet address space planning matters** — use /16 for the VNet, /24 for each subnet to leave room to grow
- **NSGs are stateful** — you only need to allow inbound; return traffic is automatically allowed
- **NAT Gateway vs outbound rules** — NAT Gateway is the recommended approach for predictable outbound IPs
- **Route tables override default routing** — use 0.0.0.0/0 → VirtualAppliance to force traffic through a firewall
- **Subnet delegation** — some Azure services (App Service, Azure SQL MI) require dedicated subnets with delegation
- **Service endpoints vs Private endpoints** — service endpoints are simpler; private endpoints give a private IP inside your VNet

## Code

See `code/vnet_checker.py` — uses `azure-mgmt-network` to verify the VNet configuration, list subnets, check NSG rules, and confirm NAT Gateway is attached.

```bash
pip install azure-mgmt-network azure-identity
python code/vnet_checker.py --resource-group rg-vnet-lab --vnet-name vnet-main
```

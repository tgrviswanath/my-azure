# Deployment Steps — Custom VNet

## Phase 1: Create VNet and Subnets

```bash
# 1.1 Login and set subscription
az login
az account set --subscription "<your-subscription-id>"

# 1.2 Create resource group
az group create \
  --name rg-vnet-lab \
  --location eastus \
  --tags project=vnet-lab environment=learning

# 1.3 Create the Virtual Network
az network vnet create \
  --resource-group rg-vnet-lab \
  --name vnet-main \
  --address-prefix 10.0.0.0/16 \
  --location eastus

# 1.4 Create Web subnet (public tier)
az network vnet subnet create \
  --resource-group rg-vnet-lab \
  --vnet-name vnet-main \
  --name subnet-web \
  --address-prefix 10.0.1.0/24

# 1.5 Create App subnet (private tier)
az network vnet subnet create \
  --resource-group rg-vnet-lab \
  --vnet-name vnet-main \
  --name subnet-app \
  --address-prefix 10.0.2.0/24

# 1.6 Create DB subnet (private tier)
az network vnet subnet create \
  --resource-group rg-vnet-lab \
  --vnet-name vnet-main \
  --name subnet-db \
  --address-prefix 10.0.3.0/24

# 1.7 Verify
az network vnet show \
  --resource-group rg-vnet-lab \
  --name vnet-main \
  --output table

az network vnet subnet list \
  --resource-group rg-vnet-lab \
  --vnet-name vnet-main \
  --output table
```

---

## Phase 2: Create and Attach NSGs

```bash
# 2.1 Create NSG for web subnet
az network nsg create \
  --resource-group rg-vnet-lab \
  --name nsg-web

# 2.2 Allow HTTP inbound to web
az network nsg rule create \
  --resource-group rg-vnet-lab \
  --nsg-name nsg-web \
  --name Allow-HTTP \
  --priority 100 \
  --protocol Tcp \
  --destination-port-range 80 \
  --access Allow \
  --direction Inbound

# 2.3 Allow HTTPS inbound to web
az network nsg rule create \
  --resource-group rg-vnet-lab \
  --nsg-name nsg-web \
  --name Allow-HTTPS \
  --priority 110 \
  --protocol Tcp \
  --destination-port-range 443 \
  --access Allow \
  --direction Inbound

# 2.4 Create NSG for app subnet
az network nsg create \
  --resource-group rg-vnet-lab \
  --name nsg-app

# 2.5 Allow traffic from web subnet to app subnet on port 8080
az network nsg rule create \
  --resource-group rg-vnet-lab \
  --nsg-name nsg-app \
  --name Allow-From-Web \
  --priority 100 \
  --protocol Tcp \
  --source-address-prefix 10.0.1.0/24 \
  --destination-port-range 8080 \
  --access Allow \
  --direction Inbound

# 2.6 Create NSG for DB subnet
az network nsg create \
  --resource-group rg-vnet-lab \
  --name nsg-db

# 2.7 Allow SQL from app subnet only
az network nsg rule create \
  --resource-group rg-vnet-lab \
  --nsg-name nsg-db \
  --name Allow-SQL-From-App \
  --priority 100 \
  --protocol Tcp \
  --source-address-prefix 10.0.2.0/24 \
  --destination-port-range 1433 \
  --access Allow \
  --direction Inbound

# 2.8 Deny all other inbound to DB
az network nsg rule create \
  --resource-group rg-vnet-lab \
  --nsg-name nsg-db \
  --name Deny-All-Inbound \
  --priority 4000 \
  --protocol '*' \
  --destination-port-range '*' \
  --access Deny \
  --direction Inbound

# 2.9 Associate NSGs with subnets
az network vnet subnet update \
  --resource-group rg-vnet-lab \
  --vnet-name vnet-main \
  --name subnet-web \
  --network-security-group nsg-web

az network vnet subnet update \
  --resource-group rg-vnet-lab \
  --vnet-name vnet-main \
  --name subnet-app \
  --network-security-group nsg-app

az network vnet subnet update \
  --resource-group rg-vnet-lab \
  --vnet-name vnet-main \
  --name subnet-db \
  --network-security-group nsg-db
```

---

## Phase 3: Create NAT Gateway

```bash
# 3.1 Create a static public IP for NAT Gateway
az network public-ip create \
  --resource-group rg-vnet-lab \
  --name pip-nat-gateway \
  --sku Standard \
  --allocation-method Static \
  --location eastus

# 3.2 Create NAT Gateway
az network nat gateway create \
  --resource-group rg-vnet-lab \
  --name nat-gateway-main \
  --public-ip-addresses pip-nat-gateway \
  --idle-timeout 10 \
  --location eastus

# 3.3 Associate NAT Gateway with private subnets
az network vnet subnet update \
  --resource-group rg-vnet-lab \
  --vnet-name vnet-main \
  --name subnet-app \
  --nat-gateway nat-gateway-main

az network vnet subnet update \
  --resource-group rg-vnet-lab \
  --vnet-name vnet-main \
  --name subnet-db \
  --nat-gateway nat-gateway-main

# 3.4 Verify NAT Gateway
az network nat gateway show \
  --resource-group rg-vnet-lab \
  --name nat-gateway-main \
  --output table
```

---

## Phase 4: Create Route Tables

```bash
# 4.1 Create route table for app subnet
az network route-table create \
  --resource-group rg-vnet-lab \
  --name rt-app \
  --location eastus

# 4.2 Add default route (all traffic via NAT Gateway — handled automatically, but explicit for learning)
az network route-table route create \
  --resource-group rg-vnet-lab \
  --route-table-name rt-app \
  --name route-to-internet \
  --address-prefix 0.0.0.0/0 \
  --next-hop-type Internet

# 4.3 Create route table for DB subnet
az network route-table create \
  --resource-group rg-vnet-lab \
  --name rt-db \
  --location eastus

# 4.4 Route DB subnet traffic only to app subnet (block direct internet)
az network route-table route create \
  --resource-group rg-vnet-lab \
  --route-table-name rt-db \
  --name route-block-internet \
  --address-prefix 0.0.0.0/0 \
  --next-hop-type None

# 4.5 Associate route tables with subnets
az network vnet subnet update \
  --resource-group rg-vnet-lab \
  --vnet-name vnet-main \
  --name subnet-app \
  --route-table rt-app

az network vnet subnet update \
  --resource-group rg-vnet-lab \
  --vnet-name vnet-main \
  --name subnet-db \
  --route-table rt-db
```

---

## Phase 5: Verify Connectivity

```bash
# 5.1 List all resources in the group
az resource list --resource-group rg-vnet-lab --output table

# 5.2 Show effective routes for a NIC (after deploying a VM)
# az network nic show-effective-route-table \
#   --resource-group rg-vnet-lab \
#   --name <nic-name> \
#   --output table

# 5.3 Show effective NSG rules for a NIC
# az network nic list-effective-nsg \
#   --resource-group rg-vnet-lab \
#   --name <nic-name>

# 5.4 Run the Python checker
pip install azure-mgmt-network azure-identity
python code/vnet_checker.py \
  --resource-group rg-vnet-lab \
  --vnet-name vnet-main

# 5.5 Cleanup
az group delete --name rg-vnet-lab --yes --no-wait
```

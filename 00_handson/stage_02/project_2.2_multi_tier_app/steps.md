# Deployment Steps — Multi-Tier Application

## Phase 1: Deploy VNet and Subnets

```bash
# 1.1 Create resource group
az group create --name rg-multitier --location eastus

# 1.2 Create VNet
az network vnet create \
  --resource-group rg-multitier \
  --name vnet-multitier \
  --address-prefix 10.1.0.0/16

# 1.3 App Gateway subnet (must be dedicated, /24 or larger)
az network vnet subnet create \
  --resource-group rg-multitier \
  --vnet-name vnet-multitier \
  --name subnet-appgw \
  --address-prefix 10.1.0.0/24

# 1.4 VMSS (web tier) subnet
az network vnet subnet create \
  --resource-group rg-multitier \
  --vnet-name vnet-multitier \
  --name subnet-web \
  --address-prefix 10.1.1.0/24

# 1.5 DB subnet
az network vnet subnet create \
  --resource-group rg-multitier \
  --vnet-name vnet-multitier \
  --name subnet-db \
  --address-prefix 10.1.2.0/24

# 1.6 Public IP for App Gateway
az network public-ip create \
  --resource-group rg-multitier \
  --name pip-appgw \
  --sku Standard \
  --allocation-method Static \
  --zone 1 2 3
```

---

## Phase 2: Deploy Application Gateway

```bash
# 2.1 Create Application Gateway (Standard_v2 with WAF)
az network application-gateway create \
  --resource-group rg-multitier \
  --name appgw-main \
  --location eastus \
  --sku WAF_v2 \
  --capacity 2 \
  --vnet-name vnet-multitier \
  --subnet subnet-appgw \
  --public-ip-address pip-appgw \
  --http-settings-port 80 \
  --http-settings-protocol Http \
  --frontend-port 80 \
  --priority 100

# 2.2 Enable WAF
az network application-gateway waf-config set \
  --resource-group rg-multitier \
  --gateway-name appgw-main \
  --enabled true \
  --firewall-mode Prevention \
  --rule-set-version 3.2

# 2.3 Verify App Gateway
az network application-gateway show \
  --resource-group rg-multitier \
  --name appgw-main \
  --query "{name:name, state:operationalState, sku:sku.name}" \
  --output table
```

---

## Phase 3: Deploy VM Scale Sets

```bash
# 3.1 Create VMSS
az vmss create \
  --resource-group rg-multitier \
  --name vmss-web \
  --image Ubuntu2204 \
  --vm-sku Standard_B2s \
  --instance-count 2 \
  --vnet-name vnet-multitier \
  --subnet subnet-web \
  --upgrade-policy-mode automatic \
  --admin-username azureuser \
  --generate-ssh-keys \
  --custom-data cloud-init.txt

# 3.2 Configure autoscale
az monitor autoscale create \
  --resource-group rg-multitier \
  --resource vmss-web \
  --resource-type Microsoft.Compute/virtualMachineScaleSets \
  --name autoscale-vmss-web \
  --min-count 2 \
  --max-count 10 \
  --count 2

# 3.3 Scale out rule (CPU > 70%)
az monitor autoscale rule create \
  --resource-group rg-multitier \
  --autoscale-name autoscale-vmss-web \
  --condition "Percentage CPU > 70 avg 5m" \
  --scale out 2

# 3.4 Scale in rule (CPU < 30%)
az monitor autoscale rule create \
  --resource-group rg-multitier \
  --autoscale-name autoscale-vmss-web \
  --condition "Percentage CPU < 30 avg 5m" \
  --scale in 1

# 3.5 Add VMSS backend pool to App Gateway
VMSS_ID=$(az vmss show --resource-group rg-multitier --name vmss-web --query id -o tsv)
az network application-gateway address-pool update \
  --resource-group rg-multitier \
  --gateway-name appgw-main \
  --name appGatewayBackendPool \
  --servers $VMSS_ID
```

---

## Phase 4: Deploy Azure SQL

```bash
# 4.1 Create SQL Server
az sql server create \
  --resource-group rg-multitier \
  --name sql-server-multitier-$(date +%s) \
  --location eastus \
  --admin-user sqladmin \
  --admin-password "YourP@ssw0rd123"

# Store the server name
SQL_SERVER=$(az sql server list --resource-group rg-multitier --query "[0].name" -o tsv)

# 4.2 Create database
az sql db create \
  --resource-group rg-multitier \
  --server $SQL_SERVER \
  --name db-app \
  --service-objective S1 \
  --backup-storage-redundancy Local

# 4.3 Allow Azure services to connect
az sql server firewall-rule create \
  --resource-group rg-multitier \
  --server $SQL_SERVER \
  --name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

# 4.4 Add VNet rule for VMSS subnet
SUBNET_ID=$(az network vnet subnet show \
  --resource-group rg-multitier \
  --vnet-name vnet-multitier \
  --name subnet-web \
  --query id -o tsv)

az sql server vnet-rule create \
  --resource-group rg-multitier \
  --server $SQL_SERVER \
  --name allow-vmss-subnet \
  --subnet $SUBNET_ID
```

---

## Phase 5: Deploy Azure Front Door

```bash
# 5.1 Get App Gateway public IP
APPGW_IP=$(az network public-ip show \
  --resource-group rg-multitier \
  --name pip-appgw \
  --query ipAddress -o tsv)

# 5.2 Create Front Door profile (Standard tier)
az afd profile create \
  --resource-group rg-multitier \
  --profile-name afd-multitier \
  --sku Standard_AzureFrontDoor

# 5.3 Create endpoint
az afd endpoint create \
  --resource-group rg-multitier \
  --profile-name afd-multitier \
  --endpoint-name ep-main \
  --enabled-state Enabled

# 5.4 Create origin group
az afd origin-group create \
  --resource-group rg-multitier \
  --profile-name afd-multitier \
  --origin-group-name og-appgw \
  --probe-request-type GET \
  --probe-protocol Http \
  --probe-interval-in-seconds 30 \
  --probe-path "/" \
  --sample-size 4 \
  --successful-samples-required 3

# 5.5 Add App Gateway as origin
az afd origin create \
  --resource-group rg-multitier \
  --profile-name afd-multitier \
  --origin-group-name og-appgw \
  --origin-name origin-appgw \
  --host-name $APPGW_IP \
  --origin-host-header $APPGW_IP \
  --http-port 80 \
  --https-port 443 \
  --priority 1 \
  --weight 1000

# 5.6 Create route
az afd route create \
  --resource-group rg-multitier \
  --profile-name afd-multitier \
  --endpoint-name ep-main \
  --route-name route-main \
  --origin-group og-appgw \
  --supported-protocols Http Https \
  --patterns-to-match "/*"

# 5.7 Get Front Door hostname
az afd endpoint show \
  --resource-group rg-multitier \
  --profile-name afd-multitier \
  --endpoint-name ep-main \
  --query hostName -o tsv
```

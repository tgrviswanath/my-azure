# Lab 01 — Create VM and Configure Networking

## Objective
Deploy a Linux VM in a secure VNet with NSG, configure SSH access via Bastion, and install a web server.

## Prerequisites
- Azure subscription
- Azure CLI installed and logged in
- Estimated time: 45 minutes
- Estimated cost: ~$0.10 (B1s VM for 1 hour)

## Step 1: Create Resource Group and VNet

```bash
# Variables
RG="rg-lab01-dev-eastus"
LOCATION="eastus"
VNET="vnet-lab01"
SUBNET_WEB="snet-web"
SUBNET_BASTION="AzureBastionSubnet"  # Must be exactly this name

# Create resource group
az group create --name $RG --location $LOCATION --tags Lab=01 Purpose=Learning

# Create VNet
az network vnet create \
  --name $VNET \
  --resource-group $RG \
  --location $LOCATION \
  --address-prefix 10.0.0.0/16

# Create web subnet
az network vnet subnet create \
  --name $SUBNET_WEB \
  --resource-group $RG \
  --vnet-name $VNET \
  --address-prefix 10.0.1.0/24

# Create Bastion subnet (must be /27 or larger)
az network vnet subnet create \
  --name $SUBNET_BASTION \
  --resource-group $RG \
  --vnet-name $VNET \
  --address-prefix 10.0.2.0/27
```

**Expected output**: Two subnets created in VNet 10.0.0.0/16

## Step 2: Create NSG with Rules

```bash
NSG="nsg-web-lab01"

# Create NSG
az network nsg create \
  --name $NSG \
  --resource-group $RG \
  --location $LOCATION

# Allow HTTP (port 80)
az network nsg rule create \
  --name AllowHTTP \
  --nsg-name $NSG \
  --resource-group $RG \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefix Internet \
  --destination-port-range 80

# Allow HTTPS (port 443)
az network nsg rule create \
  --name AllowHTTPS \
  --nsg-name $NSG \
  --resource-group $RG \
  --priority 110 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefix Internet \
  --destination-port-range 443

# Deny all other inbound
az network nsg rule create \
  --name DenyAllInbound \
  --nsg-name $NSG \
  --resource-group $RG \
  --priority 4096 \
  --direction Inbound \
  --access Deny \
  --protocol "*" \
  --source-address-prefix "*" \
  --destination-port-range "*"

# Associate NSG with subnet
az network vnet subnet update \
  --name $SUBNET_WEB \
  --resource-group $RG \
  --vnet-name $VNET \
  --network-security-group $NSG

# Verify NSG rules
az network nsg rule list --nsg-name $NSG --resource-group $RG --output table
```

**Expected output**: 3 NSG rules (AllowHTTP, AllowHTTPS, DenyAllInbound)

## Step 3: Create VM (No Public IP)

```bash
VM_NAME="vm-web-lab01"
ADMIN_USER="azureuser"

# Create VM without public IP
az vm create \
  --resource-group $RG \
  --name $VM_NAME \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --admin-username $ADMIN_USER \
  --generate-ssh-keys \
  --vnet-name $VNET \
  --subnet $SUBNET_WEB \
  --public-ip-address "" \
  --nsg "" \
  --tags Lab=01 Role=WebServer

# Verify VM has no public IP
az vm show \
  --resource-group $RG \
  --name $VM_NAME \
  --show-details \
  --query "{name:name, privateIp:privateIps, publicIp:publicIps}" \
  --output table
```

**Expected output**: VM with private IP only (10.0.1.x), no public IP

## Step 4: Install Web Server via Custom Script Extension

```bash
# Install nginx via extension (no SSH needed)
az vm extension set \
  --resource-group $RG \
  --vm-name $VM_NAME \
  --name CustomScript \
  --publisher Microsoft.Azure.Extensions \
  --version 2.1 \
  --settings '{
    "commandToExecute": "apt-get update && apt-get install -y nginx && echo \"<h1>Hello from Azure VM Lab!</h1><p>VM: $(hostname)</p>\" > /var/www/html/index.html && systemctl enable nginx && systemctl start nginx"
  }'

# Check extension status
az vm extension show \
  --resource-group $RG \
  --vm-name $VM_NAME \
  --name CustomScript \
  --query "provisioningState" \
  --output tsv
```

**Expected output**: "Succeeded"

## Step 5: Create Azure Bastion

```bash
# Create public IP for Bastion
az network public-ip create \
  --name pip-bastion-lab01 \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard \
  --allocation-method Static

# Create Bastion (takes ~5 minutes)
az network bastion create \
  --name bastion-lab01 \
  --resource-group $RG \
  --location $LOCATION \
  --vnet-name $VNET \
  --public-ip-address pip-bastion-lab01 \
  --sku Basic

echo "Bastion deployment started (takes ~5 minutes)..."
az network bastion show \
  --name bastion-lab01 \
  --resource-group $RG \
  --query "provisioningState" \
  --output tsv
```

## Step 6: Test Connectivity

```bash
# Get VM private IP
PRIVATE_IP=$(az vm show \
  --resource-group $RG \
  --name $VM_NAME \
  --show-details \
  --query privateIps \
  --output tsv)

echo "VM Private IP: $PRIVATE_IP"

# Test HTTP from another VM or via Bastion tunnel
# Option 1: SSH via Bastion (portal or CLI)
az network bastion ssh \
  --name bastion-lab01 \
  --resource-group $RG \
  --target-resource-id $(az vm show --resource-group $RG --name $VM_NAME --query id --output tsv) \
  --auth-type ssh-key \
  --username $ADMIN_USER \
  --ssh-key ~/.ssh/id_rsa

# Inside VM: test nginx
# curl localhost
# systemctl status nginx
```

## Step 7: Add Load Balancer (Optional Extension)

```bash
# Create public IP for LB
az network public-ip create \
  --name pip-lb-lab01 \
  --resource-group $RG \
  --sku Standard \
  --allocation-method Static

# Create Load Balancer
az network lb create \
  --name lb-web-lab01 \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard \
  --public-ip-address pip-lb-lab01 \
  --frontend-ip-name frontend \
  --backend-pool-name backend-pool

# Add health probe
az network lb probe create \
  --name http-probe \
  --lb-name lb-web-lab01 \
  --resource-group $RG \
  --protocol Http \
  --port 80 \
  --path /

# Add LB rule
az network lb rule create \
  --name http-rule \
  --lb-name lb-web-lab01 \
  --resource-group $RG \
  --frontend-ip-name frontend \
  --backend-pool-name backend-pool \
  --probe-name http-probe \
  --protocol Tcp \
  --frontend-port 80 \
  --backend-port 80

# Add VM NIC to backend pool
NIC_ID=$(az vm show --resource-group $RG --name $VM_NAME --query "networkProfile.networkInterfaces[0].id" --output tsv)
az network nic ip-config address-pool add \
  --address-pool backend-pool \
  --ip-config-name ipconfig1 \
  --nic-name $(basename $NIC_ID) \
  --resource-group $RG \
  --lb-name lb-web-lab01

# Get LB public IP
LB_IP=$(az network public-ip show --name pip-lb-lab01 --resource-group $RG --query ipAddress --output tsv)
echo "Load Balancer IP: $LB_IP"
echo "Test: curl http://$LB_IP"
```

## Cleanup

```bash
# Delete all resources (saves cost)
az group delete --name $RG --yes --no-wait
echo "Resource group deletion initiated"
```

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| VM creation fails | Quota exceeded | Check `az vm list-usage --location $LOCATION` |
| Extension fails | Script error | Check `az vm extension show` for error details |
| Bastion not connecting | Subnet too small | AzureBastionSubnet must be /27 or larger |
| HTTP not working | NSG blocking | Check effective NSG rules on NIC |
| No public IP on LB | SKU mismatch | Standard LB requires Standard public IP |

## Expected Outcomes
- ✅ VM running with private IP only
- ✅ NSG allowing HTTP/HTTPS, denying all else
- ✅ Nginx serving web page
- ✅ Bastion providing secure SSH access
- ✅ Load Balancer distributing traffic

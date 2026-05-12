# Deployment Steps — App Gateway vs Load Balancer

## Phase 1: Deploy Both Load Balancers

```bash
# 1.1 Create resource group
az group create --name rg-lb-comparison --location eastus

# 1.2 Create shared VNet
az network vnet create \
  --resource-group rg-lb-comparison \
  --name vnet-comparison \
  --address-prefix 10.2.0.0/16

# 1.3 App Gateway subnet (dedicated)
az network vnet subnet create \
  --resource-group rg-lb-comparison \
  --vnet-name vnet-comparison \
  --name subnet-appgw \
  --address-prefix 10.2.0.0/24

# 1.4 App Gateway backend subnet
az network vnet subnet create \
  --resource-group rg-lb-comparison \
  --vnet-name vnet-comparison \
  --name subnet-appgw-backend \
  --address-prefix 10.2.1.0/24

# 1.5 Load Balancer backend subnet
az network vnet subnet create \
  --resource-group rg-lb-comparison \
  --vnet-name vnet-comparison \
  --name subnet-lb-backend \
  --address-prefix 10.2.2.0/24

# 1.6 Public IPs
az network public-ip create \
  --resource-group rg-lb-comparison \
  --name pip-appgw \
  --sku Standard \
  --allocation-method Static

az network public-ip create \
  --resource-group rg-lb-comparison \
  --name pip-lb \
  --sku Standard \
  --allocation-method Static

# 1.7 Create Application Gateway
az network application-gateway create \
  --resource-group rg-lb-comparison \
  --name appgw-comparison \
  --location eastus \
  --sku Standard_v2 \
  --capacity 1 \
  --vnet-name vnet-comparison \
  --subnet subnet-appgw \
  --public-ip-address pip-appgw \
  --http-settings-port 80 \
  --http-settings-protocol Http \
  --frontend-port 80 \
  --priority 100

# 1.8 Create Azure Load Balancer
az network lb create \
  --resource-group rg-lb-comparison \
  --name lb-comparison \
  --sku Standard \
  --public-ip-address pip-lb \
  --frontend-ip-name lb-frontend \
  --backend-pool-name lb-backend-pool

# 1.9 Add health probe to LB
az network lb probe create \
  --resource-group rg-lb-comparison \
  --lb-name lb-comparison \
  --name lb-health-probe \
  --protocol Http \
  --port 80 \
  --path /health

# 1.10 Add LB rule
az network lb rule create \
  --resource-group rg-lb-comparison \
  --lb-name lb-comparison \
  --name lb-http-rule \
  --protocol Tcp \
  --frontend-port 80 \
  --backend-port 80 \
  --frontend-ip-name lb-frontend \
  --backend-pool-name lb-backend-pool \
  --probe-name lb-health-probe
```

---

## Phase 2: Test Path-Based Routing (App Gateway)

```bash
# 2.1 Add path-based routing rule to App Gateway
# First, create a second backend pool for /api path
az network application-gateway address-pool create \
  --resource-group rg-lb-comparison \
  --gateway-name appgw-comparison \
  --name api-backend-pool

# 2.2 Create URL path map
az network application-gateway url-path-map create \
  --resource-group rg-lb-comparison \
  --gateway-name appgw-comparison \
  --name url-path-map \
  --paths /api/* \
  --address-pool api-backend-pool \
  --http-settings appGatewayBackendHttpSettings \
  --default-address-pool appGatewayBackendPool \
  --default-http-settings appGatewayBackendHttpSettings

# 2.3 Get App Gateway public IP
APPGW_IP=$(az network public-ip show \
  --resource-group rg-lb-comparison \
  --name pip-appgw \
  --query ipAddress -o tsv)

# 2.4 Test path routing
curl -v http://$APPGW_IP/
curl -v http://$APPGW_IP/api/users
curl -v http://$APPGW_IP/static/logo.png
```

---

## Phase 3: Test TCP Load Balancing (Azure LB)

```bash
# 3.1 Get LB public IP
LB_IP=$(az network public-ip show \
  --resource-group rg-lb-comparison \
  --name pip-lb \
  --query ipAddress -o tsv)

# 3.2 Test TCP connectivity
curl -v http://$LB_IP/
curl -v http://$LB_IP/api/users

# 3.3 Check LB backend health
az network lb show \
  --resource-group rg-lb-comparison \
  --name lb-comparison \
  --query "backendAddressPools[0].backendIPConfigurations" \
  --output table

# 3.4 Check LB rules
az network lb rule list \
  --resource-group rg-lb-comparison \
  --lb-name lb-comparison \
  --output table
```

---

## Phase 4: Compare Latency

```bash
# 4.1 Install test dependencies
pip install requests statistics

# 4.2 Run comparison test
python code/load_test.py \
  --appgw-url http://$APPGW_IP \
  --lb-url http://$LB_IP \
  --requests 200 \
  --concurrency 10

# 4.3 Manual latency test with curl
echo "=== App Gateway ===" 
for i in {1..10}; do
  curl -o /dev/null -s -w "%{time_total}\n" http://$APPGW_IP/
done

echo "=== Load Balancer ==="
for i in {1..10}; do
  curl -o /dev/null -s -w "%{time_total}\n" http://$LB_IP/
done

# 4.4 Cleanup
az group delete --name rg-lb-comparison --yes --no-wait
```

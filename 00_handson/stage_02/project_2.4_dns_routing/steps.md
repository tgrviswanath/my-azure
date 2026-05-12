# Deployment Steps — Azure DNS + Traffic Manager

## Phase 1: Create DNS Zone

```bash
# 1.1 Create resource group
az group create --name rg-dns-lab --location eastus

# 1.2 Create DNS zone (replace with your domain)
az network dns zone create \
  --resource-group rg-dns-lab \
  --name yourdomain.com

# 1.3 Get name servers (update your domain registrar with these)
az network dns zone show \
  --resource-group rg-dns-lab \
  --name yourdomain.com \
  --query nameServers \
  --output table

# 1.4 Create A record
az network dns record-set a add-record \
  --resource-group rg-dns-lab \
  --zone-name yourdomain.com \
  --record-set-name www \
  --ipv4-address 20.1.2.3

# 1.5 Create CNAME record
az network dns record-set cname set-record \
  --resource-group rg-dns-lab \
  --zone-name yourdomain.com \
  --record-set-name api \
  --cname myapp.azurewebsites.net

# 1.6 Create TXT record (for domain verification)
az network dns record-set txt add-record \
  --resource-group rg-dns-lab \
  --zone-name yourdomain.com \
  --record-set-name @ \
  --value "v=spf1 include:spf.protection.outlook.com -all"

# 1.7 List all DNS records
az network dns record-set list \
  --resource-group rg-dns-lab \
  --zone-name yourdomain.com \
  --output table
```

---

## Phase 2: Create Traffic Manager Profile

```bash
# 2.1 Create Traffic Manager profile (Priority routing = failover)
az network traffic-manager profile create \
  --resource-group rg-dns-lab \
  --name tm-main \
  --routing-method Priority \
  --unique-dns-name tm-main-$(date +%s) \
  --ttl 30 \
  --protocol HTTP \
  --port 80 \
  --path /health

# 2.2 Verify profile
az network traffic-manager profile show \
  --resource-group rg-dns-lab \
  --name tm-main \
  --output table
```

---

## Phase 3: Add Endpoints

```bash
# 3.1 Create two public IPs to simulate endpoints
az network public-ip create \
  --resource-group rg-dns-lab \
  --name pip-primary \
  --sku Standard \
  --allocation-method Static \
  --dns-name tm-endpoint-primary-$(date +%s)

az network public-ip create \
  --resource-group rg-dns-lab \
  --name pip-secondary \
  --sku Standard \
  --allocation-method Static \
  --dns-name tm-endpoint-secondary-$(date +%s)

# 3.2 Get Public IP resource IDs
PRIMARY_ID=$(az network public-ip show \
  --resource-group rg-dns-lab \
  --name pip-primary \
  --query id -o tsv)

SECONDARY_ID=$(az network public-ip show \
  --resource-group rg-dns-lab \
  --name pip-secondary \
  --query id -o tsv)

# 3.3 Add primary endpoint (priority 1 = highest)
az network traffic-manager endpoint create \
  --resource-group rg-dns-lab \
  --profile-name tm-main \
  --name endpoint-primary \
  --type azureEndpoints \
  --target-resource-id $PRIMARY_ID \
  --priority 1 \
  --endpoint-status Enabled

# 3.4 Add secondary endpoint (priority 2 = failover)
az network traffic-manager endpoint create \
  --resource-group rg-dns-lab \
  --profile-name tm-main \
  --name endpoint-secondary \
  --type azureEndpoints \
  --target-resource-id $SECONDARY_ID \
  --priority 2 \
  --endpoint-status Enabled

# 3.5 List endpoints
az network traffic-manager endpoint list \
  --resource-group rg-dns-lab \
  --profile-name tm-main \
  --output table
```

---

## Phase 4: Configure Routing Methods

```bash
# 4.1 Switch to Weighted routing (for A/B testing)
az network traffic-manager profile update \
  --resource-group rg-dns-lab \
  --name tm-main \
  --routing-method Weighted

# Update weights
az network traffic-manager endpoint update \
  --resource-group rg-dns-lab \
  --profile-name tm-main \
  --name endpoint-primary \
  --type azureEndpoints \
  --weight 80

az network traffic-manager endpoint update \
  --resource-group rg-dns-lab \
  --profile-name tm-main \
  --name endpoint-secondary \
  --type azureEndpoints \
  --weight 20

# 4.2 Switch to Performance routing (latency-based)
az network traffic-manager profile update \
  --resource-group rg-dns-lab \
  --name tm-main \
  --routing-method Performance

# 4.3 Switch back to Priority (failover)
az network traffic-manager profile update \
  --resource-group rg-dns-lab \
  --name tm-main \
  --routing-method Priority
```

---

## Phase 5: Test Failover

```bash
# 5.1 Get Traffic Manager DNS name
TM_DNS=$(az network traffic-manager profile show \
  --resource-group rg-dns-lab \
  --name tm-main \
  --query dnsConfig.fqdn -o tsv)

echo "Traffic Manager DNS: $TM_DNS"

# 5.2 Resolve DNS (should return primary endpoint)
nslookup $TM_DNS

# 5.3 Disable primary endpoint to trigger failover
az network traffic-manager endpoint update \
  --resource-group rg-dns-lab \
  --profile-name tm-main \
  --name endpoint-primary \
  --type azureEndpoints \
  --endpoint-status Disabled

# 5.4 Wait for health probe to detect failure (30–60 seconds)
sleep 60

# 5.5 Resolve DNS again (should now return secondary endpoint)
nslookup $TM_DNS

# 5.6 Re-enable primary
az network traffic-manager endpoint update \
  --resource-group rg-dns-lab \
  --profile-name tm-main \
  --name endpoint-primary \
  --type azureEndpoints \
  --endpoint-status Enabled

# 5.7 Run Python checker
python code/dns_checker.py --resource-group rg-dns-lab

# 5.8 Cleanup
az group delete --name rg-dns-lab --yes --no-wait
```

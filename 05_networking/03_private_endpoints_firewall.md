# Azure Private Endpoints, Firewall & Advanced Networking

## Private Endpoints — Deep Dive

Private Endpoints give Azure PaaS services (Storage, SQL, Key Vault, etc.) a private IP address inside your VNet. Traffic never leaves the Azure backbone.

```
Without Private Endpoint:
  App (VNet) → Internet → storage.blob.core.windows.net (public IP)

With Private Endpoint:
  App (VNet) → Private IP (10.0.3.4) → storage.blob.core.windows.net
                                         (resolved via private DNS)
```

### Supported Services
Storage (blob, file, queue, table), SQL Database, Cosmos DB, Key Vault, App Service, AKS API server, Service Bus, Event Hubs, Redis Cache, ACR, and 100+ more.

### Setup Pattern

```bash
# 1. Create private endpoint
STORAGE_ID=$(az storage account show \
  --name $STORAGE_NAME --resource-group $RG \
  --query id --output tsv)

az network private-endpoint create \
  --name pe-storage-blob \
  --resource-group $RG \
  --vnet-name vnet-app-prod \
  --subnet snet-pe \
  --private-connection-resource-id $STORAGE_ID \
  --group-id blob \
  --connection-name conn-storage-blob \
  --location $LOCATION

# 2. Create private DNS zone
az network private-dns zone create \
  --resource-group $RG \
  --name "privatelink.blob.core.windows.net"

# 3. Link DNS zone to VNet
az network private-dns link vnet create \
  --resource-group $RG \
  --zone-name "privatelink.blob.core.windows.net" \
  --name link-vnet-app \
  --virtual-network vnet-app-prod \
  --registration-enabled false

# 4. Create DNS record group (auto-creates A record)
az network private-endpoint dns-zone-group create \
  --resource-group $RG \
  --endpoint-name pe-storage-blob \
  --name dns-zone-group \
  --private-dns-zone "privatelink.blob.core.windows.net" \
  --zone-name blob

# 5. Disable public access on storage
az storage account update \
  --name $STORAGE_NAME \
  --resource-group $RG \
  --public-network-access Disabled

# Verify DNS resolution (from inside VNet)
# nslookup mystorageaccount.blob.core.windows.net
# → resolves to 10.0.3.4 (private IP)
```

### Private DNS Zones Reference

| Service | DNS Zone |
|---------|---------|
| Blob Storage | privatelink.blob.core.windows.net |
| File Storage | privatelink.file.core.windows.net |
| SQL Database | privatelink.database.windows.net |
| Cosmos DB | privatelink.documents.azure.com |
| Key Vault | privatelink.vaultcore.azure.net |
| ACR | privatelink.azurecr.io |
| Service Bus | privatelink.servicebus.windows.net |
| App Service | privatelink.azurewebsites.net |
| Redis Cache | privatelink.redis.cache.windows.net |

---

## Azure Firewall

Azure Firewall is a managed, cloud-native network security service. Stateful, fully scalable, with built-in high availability.

```
Hub VNet
├── Azure Firewall (central inspection point)
│   ├── Application Rules (FQDN-based, L7)
│   ├── Network Rules (IP/port-based, L4)
│   └── NAT Rules (DNAT for inbound)
└── Route Tables (force all traffic through firewall)

Spoke VNets → Hub VNet → Azure Firewall → Internet/On-premises
```

### Deploy Azure Firewall

```bash
# Create dedicated subnet (must be named AzureFirewallSubnet)
az network vnet subnet create \
  --name AzureFirewallSubnet \
  --resource-group $RG \
  --vnet-name vnet-hub-prod \
  --address-prefix 10.0.0.0/26

# Create public IP
az network public-ip create \
  --name pip-firewall-prod \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard \
  --allocation-method Static \
  --zone 1 2 3

# Create Firewall Policy
az network firewall policy create \
  --name fwpol-prod \
  --resource-group $RG \
  --location $LOCATION \
  --sku Premium \
  --threat-intel-mode Alert \
  --enable-dns-proxy true

# Create Azure Firewall
az network firewall create \
  --name fw-hub-prod \
  --resource-group $RG \
  --location $LOCATION \
  --sku AZFW_VNet \
  --tier Premium \
  --firewall-policy fwpol-prod \
  --vnet-name vnet-hub-prod \
  --public-ip pip-firewall-prod \
  --zones 1 2 3

# Get firewall private IP
FW_PRIVATE_IP=$(az network firewall show \
  --name fw-hub-prod \
  --resource-group $RG \
  --query "ipConfigurations[0].privateIPAddress" \
  --output tsv)
echo "Firewall private IP: $FW_PRIVATE_IP"
```

### Firewall Rules

```bash
# Application Rule Collection — allow HTTPS to specific FQDNs
az network firewall policy rule-collection-group create \
  --name DefaultApplicationRuleCollectionGroup \
  --policy-name fwpol-prod \
  --resource-group $RG \
  --priority 300

az network firewall policy rule-collection-group collection add-filter-collection \
  --name AllowWebTraffic \
  --policy-name fwpol-prod \
  --resource-group $RG \
  --rule-collection-group-name DefaultApplicationRuleCollectionGroup \
  --priority 100 \
  --action Allow \
  --rule-name AllowAzureServices \
  --rule-type ApplicationRule \
  --source-addresses "10.0.0.0/8" \
  --protocols "Https=443" \
  --target-fqdns \
    "*.azure.com" \
    "*.microsoft.com" \
    "*.azurecr.io" \
    "*.blob.core.windows.net"

# Network Rule Collection — allow specific ports
az network firewall policy rule-collection-group collection add-filter-collection \
  --name AllowNetworkTraffic \
  --policy-name fwpol-prod \
  --resource-group $RG \
  --rule-collection-group-name DefaultApplicationRuleCollectionGroup \
  --priority 200 \
  --action Allow \
  --rule-name AllowDNS \
  --rule-type NetworkRule \
  --source-addresses "10.0.0.0/8" \
  --destination-addresses "168.63.129.16" \
  --ip-protocols UDP \
  --destination-ports 53

# NAT Rule — inbound DNAT (expose internal service)
az network firewall policy rule-collection-group collection add-nat-collection \
  --name InboundNAT \
  --policy-name fwpol-prod \
  --resource-group $RG \
  --rule-collection-group-name DefaultApplicationRuleCollectionGroup \
  --priority 50 \
  --rule-name InboundHTTPS \
  --source-addresses "*" \
  --destination-addresses $FW_PUBLIC_IP \
  --destination-ports 443 \
  --ip-protocols TCP \
  --translated-address 10.0.1.10 \
  --translated-port 443
```

### Force Tunnel All Traffic Through Firewall

```bash
# Create route table
az network route-table create \
  --name rt-spoke-to-hub \
  --resource-group $RG \
  --location $LOCATION \
  --disable-bgp-route-propagation true

# Default route → Firewall
az network route-table route create \
  --name default-to-firewall \
  --resource-group $RG \
  --route-table-name rt-spoke-to-hub \
  --address-prefix 0.0.0.0/0 \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address $FW_PRIVATE_IP

# Associate with spoke subnet
az network vnet subnet update \
  --name snet-app \
  --resource-group $RG_SPOKE \
  --vnet-name vnet-spoke-prod \
  --route-table rt-spoke-to-hub
```

---

## Azure DDoS Protection

```bash
# Create DDoS Protection Plan (Standard — ~$2,944/month)
az network ddos-protection create \
  --name ddos-plan-prod \
  --resource-group $RG \
  --location $LOCATION

# Associate with VNet
az network vnet update \
  --name vnet-app-prod \
  --resource-group $RG \
  --ddos-protection true \
  --ddos-protection-plan ddos-plan-prod
```

**DDoS Basic** (free): Always-on monitoring, automatic mitigation for Azure infrastructure.
**DDoS Standard** (~$2,944/month): Per-VNet protection, adaptive tuning, attack analytics, cost protection guarantee.

---

## Service Endpoints vs Private Endpoints

| Feature | Service Endpoints | Private Endpoints |
|---------|------------------|------------------|
| Traffic path | Azure backbone (no internet) | Azure backbone (no internet) |
| Private IP | ❌ Service keeps public IP | ✅ Service gets private IP in VNet |
| On-premises access | ❌ | ✅ Via VPN/ExpressRoute |
| DNS | No change | Private DNS zone required |
| Cost | Free | ~$0.01/hr per endpoint |
| Cross-region | ❌ | ✅ |
| Use case | Simple VNet-to-service | Full private access, compliance |

**Recommendation**: Use Private Endpoints for production. Service Endpoints for dev/test or when cost is a concern.

---

## Interview Q&A

### Q1: What is the difference between Azure Firewall and NSG?
**NSG**: Stateful packet filter at subnet/NIC level. Layer 3/4 rules only (IP, port, protocol). Free. No FQDN filtering. Best for basic network segmentation within a VNet.
**Azure Firewall**: Managed, centralized firewall. Layer 3-7. FQDN filtering, threat intelligence, TLS inspection, IDPS (Premium). Centralized policy management across VNets. ~$1.25/hr. Best for hub-spoke architectures, enterprise security, egress filtering.
Use both: NSG for micro-segmentation, Firewall for centralized egress control.

### Q2: How does Private Endpoint DNS resolution work?
When you create a Private Endpoint, Azure creates a private DNS zone (e.g., `privatelink.blob.core.windows.net`). The storage account's public DNS name (`mystorageaccount.blob.core.windows.net`) has a CNAME to `mystorageaccount.privatelink.blob.core.windows.net`. Inside the VNet, this resolves to the private IP (10.x.x.x). Outside the VNet, it resolves to the public IP. This means the same connection string works from both inside and outside the VNet.

### Q3: What is a hub-spoke network topology and why use it?
Hub-spoke: a central hub VNet contains shared services (Firewall, VPN Gateway, Bastion, DNS), and spoke VNets contain workloads. Spokes connect to hub via VNet peering. Benefits: (1) Centralized security — all traffic inspected by hub firewall, (2) Shared connectivity — VPN/ExpressRoute provisioned once in hub, (3) Cost savings — shared resources, (4) Isolation — spokes can't communicate directly (traffic goes through hub). Use Azure Virtual WAN for large-scale hub-spoke.

### Q4: How do you prevent data exfiltration from a storage account?
1. Disable public network access (`--public-network-access Disabled`)
2. Use Private Endpoints — traffic stays on Azure backbone
3. Storage firewall — allow only specific VNets/IPs
4. Service Endpoint Policies — restrict which storage accounts a VNet can access
5. Azure Firewall FQDN rules — only allow specific storage account FQDNs
6. Defender for Storage — detect anomalous access patterns
7. Immutable storage + legal hold for compliance data

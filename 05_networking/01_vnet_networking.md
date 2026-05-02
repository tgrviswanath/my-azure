# Azure Networking — VNet, NSG, Load Balancer & Advanced

## Virtual Network (VNet) Architecture

```
VNet (10.0.0.0/16)
├── Subnet: web-tier    (10.0.1.0/24)  → App Service, VMs
├── Subnet: app-tier    (10.0.2.0/24)  → Backend services
├── Subnet: data-tier   (10.0.3.0/24)  → Databases
├── Subnet: mgmt        (10.0.4.0/24)  → Bastion, jump boxes
└── Subnet: gateway     (10.0.5.0/27)  → VPN/ExpressRoute Gateway

Reserved IPs per subnet (Azure uses first 4 + last):
  x.x.x.0  — Network address
  x.x.x.1  — Default gateway
  x.x.x.2  — DNS mapping
  x.x.x.3  — Reserved
  x.x.x.255 — Broadcast
```

## VNet Creation & Peering

```bash
# Create VNet with subnets
az network vnet create \
  --name vnet-app-prod \
  --resource-group $RG \
  --location $LOCATION \
  --address-prefix 10.0.0.0/16

az network vnet subnet create \
  --name snet-web \
  --resource-group $RG \
  --vnet-name vnet-app-prod \
  --address-prefix 10.0.1.0/24 \
  --service-endpoints Microsoft.Storage Microsoft.Sql

az network vnet subnet create \
  --name snet-db \
  --resource-group $RG \
  --vnet-name vnet-app-prod \
  --address-prefix 10.0.2.0/24

# VNet Peering (connect two VNets)
az network vnet peering create \
  --name peer-app-to-hub \
  --resource-group $RG \
  --vnet-name vnet-app-prod \
  --remote-vnet vnet-hub-prod \
  --allow-vnet-access \
  --allow-forwarded-traffic

# Reverse peering (required for bidirectional)
az network vnet peering create \
  --name peer-hub-to-app \
  --resource-group $RG_HUB \
  --vnet-name vnet-hub-prod \
  --remote-vnet vnet-app-prod \
  --allow-vnet-access \
  --allow-forwarded-traffic
```

## Network Security Groups (NSG)

```bash
# Create NSG
az network nsg create \
  --name nsg-web-prod \
  --resource-group $RG \
  --location $LOCATION

# Allow HTTPS inbound
az network nsg rule create \
  --name AllowHTTPS \
  --nsg-name nsg-web-prod \
  --resource-group $RG \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefix Internet \
  --source-port-range "*" \
  --destination-address-prefix "*" \
  --destination-port-range 443

# Allow from specific subnet only
az network nsg rule create \
  --name AllowFromAppTier \
  --nsg-name nsg-db-prod \
  --resource-group $RG \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefix 10.0.2.0/24 \
  --destination-port-range 5432

# Deny all inbound (lowest priority = last resort)
az network nsg rule create \
  --name DenyAllInbound \
  --nsg-name nsg-web-prod \
  --resource-group $RG \
  --priority 4096 \
  --direction Inbound \
  --access Deny \
  --protocol "*" \
  --source-address-prefix "*" \
  --destination-port-range "*"

# Associate NSG with subnet
az network vnet subnet update \
  --name snet-web \
  --resource-group $RG \
  --vnet-name vnet-app-prod \
  --network-security-group nsg-web-prod
```

## Load Balancer vs Application Gateway

```
Azure Load Balancer (Layer 4 — TCP/UDP)
├── Internal or Public
├── Basic (free) vs Standard (SLA, zone-redundant)
├── Health probes: TCP, HTTP
├── No SSL termination
├── No URL-based routing
└── Use for: non-HTTP traffic, simple TCP load balancing

Application Gateway (Layer 7 — HTTP/HTTPS)
├── URL-based routing (/api → backend1, /images → backend2)
├── SSL termination (offload TLS from backends)
├── WAF (Web Application Firewall) — OWASP rules
├── Cookie-based session affinity
├── Autoscaling (v2)
├── Zone redundancy (v2)
└── Use for: web apps, APIs, need WAF/SSL termination

Azure Front Door (Global Layer 7)
├── Global load balancing across regions
├── CDN capabilities
├── WAF
├── Anycast routing (closest POP)
└── Use for: multi-region apps, global CDN

Traffic Manager (DNS-based)
├── Routes DNS queries to endpoints
├── Routing methods: performance, weighted, priority, geographic
├── No data plane (just DNS)
└── Use for: multi-region failover, geographic routing
```

```bash
# Create Standard Load Balancer
az network lb create \
  --name lb-web-prod \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard \
  --public-ip-address pip-lb-prod \
  --frontend-ip-name frontend \
  --backend-pool-name backend-pool

# Add health probe
az network lb probe create \
  --name health-probe \
  --lb-name lb-web-prod \
  --resource-group $RG \
  --protocol Http \
  --port 80 \
  --path /health \
  --interval 15 \
  --threshold 2

# Add load balancing rule
az network lb rule create \
  --name http-rule \
  --lb-name lb-web-prod \
  --resource-group $RG \
  --frontend-ip-name frontend \
  --backend-pool-name backend-pool \
  --probe-name health-probe \
  --protocol Tcp \
  --frontend-port 80 \
  --backend-port 80

# Create Application Gateway with WAF
az network application-gateway create \
  --name agw-web-prod \
  --resource-group $RG \
  --location $LOCATION \
  --sku WAF_v2 \
  --capacity 2 \
  --vnet-name vnet-app-prod \
  --subnet snet-agw \
  --public-ip-address pip-agw-prod \
  --http-settings-port 80 \
  --http-settings-protocol Http \
  --frontend-port 443 \
  --cert-file ./cert.pfx \
  --cert-password "CertPassword"
```

## Azure Bastion

```bash
# Create Bastion (secure RDP/SSH without public IP on VMs)
az network bastion create \
  --name bastion-prod \
  --resource-group $RG \
  --location $LOCATION \
  --vnet-name vnet-app-prod \
  --public-ip-address pip-bastion \
  --sku Standard \
  --enable-tunneling true

# Connect to VM via Bastion
az network bastion ssh \
  --name bastion-prod \
  --resource-group $RG \
  --target-resource-id $VM_ID \
  --auth-type ssh-key \
  --username azureuser \
  --ssh-key ~/.ssh/id_rsa
```

## Private Endpoints

```bash
# Create private endpoint for storage account
az network private-endpoint create \
  --name pe-storage-prod \
  --resource-group $RG \
  --vnet-name vnet-app-prod \
  --subnet snet-app \
  --private-connection-resource-id $STORAGE_ID \
  --group-id blob \
  --connection-name conn-storage

# Create private DNS zone
az network private-dns zone create \
  --resource-group $RG \
  --name "privatelink.blob.core.windows.net"

# Link DNS zone to VNet
az network private-dns link vnet create \
  --resource-group $RG \
  --zone-name "privatelink.blob.core.windows.net" \
  --name dns-link-vnet \
  --virtual-network vnet-app-prod \
  --registration-enabled false

# Create DNS record for private endpoint
az network private-endpoint dns-zone-group create \
  --resource-group $RG \
  --endpoint-name pe-storage-prod \
  --name dns-zone-group \
  --private-dns-zone "privatelink.blob.core.windows.net" \
  --zone-name blob
```

## Interview Questions

### Q1: What is the difference between NSG and Azure Firewall?
**Answer:**
- **NSG**: Stateful packet filter at subnet/NIC level. Layer 3/4 rules (IP, port, protocol). Free. No logging by default. Best for basic network segmentation.
- **Azure Firewall**: Managed, cloud-native firewall. Layer 3-7. FQDN filtering, threat intelligence, TLS inspection, IDPS. Centralized policy management. Costs ~$1.25/hour. Best for enterprise security, hub-spoke architectures.

### Q2: What is the difference between Load Balancer and Application Gateway?
**Answer:**
- **Load Balancer**: Layer 4 (TCP/UDP). Fast, simple, no SSL termination, no URL routing. Use for non-HTTP or simple TCP load balancing.
- **Application Gateway**: Layer 7 (HTTP/HTTPS). URL-based routing, SSL termination, WAF, session affinity. Use for web apps needing advanced routing or WAF.

### Q3: What is a Private Endpoint and why use it?
**Answer:**
Private Endpoint gives an Azure service (Storage, SQL, Key Vault, etc.) a private IP in your VNet. Traffic stays on the Azure backbone — never traverses the public internet. Use to:
- Prevent data exfiltration
- Meet compliance requirements
- Access services from on-premises via VPN/ExpressRoute
- Disable public access to services entirely

### Q4: What is VNet Peering and what are its limitations?
**Answer:**
VNet Peering connects two VNets for private communication. Limitations:
- Non-transitive: A↔B and B↔C doesn't mean A↔C (need hub-spoke or VNet Gateway)
- Address spaces cannot overlap
- Peering is not free (charged per GB transferred)
- Cannot peer across different Azure AD tenants without special configuration
- Use Azure Virtual WAN or hub-spoke with NVA for transitive routing

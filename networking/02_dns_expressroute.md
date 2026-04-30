# Azure Networking — DNS, VPN Gateway & ExpressRoute

## Azure DNS

```bash
# Create public DNS zone
az network dns zone create \
  --name "mycompany.com" \
  --resource-group $RG

# Add records
az network dns record-set a add-record \
  --resource-group $RG \
  --zone-name "mycompany.com" \
  --record-set-name "www" \
  --ipv4-address "20.1.2.3"

az network dns record-set cname set-record \
  --resource-group $RG \
  --zone-name "mycompany.com" \
  --record-set-name "api" \
  --cname "app-myapp-prod.azurewebsites.net"

az network dns record-set mx add-record \
  --resource-group $RG \
  --zone-name "mycompany.com" \
  --record-set-name "@" \
  --exchange "mail.mycompany.com" \
  --preference 10

# Get name servers (update at registrar)
az network dns zone show \
  --name "mycompany.com" \
  --resource-group $RG \
  --query "nameServers"

# Private DNS zone
az network private-dns zone create \
  --resource-group $RG \
  --name "internal.mycompany.com"

az network private-dns link vnet create \
  --resource-group $RG \
  --zone-name "internal.mycompany.com" \
  --name "link-to-vnet" \
  --virtual-network $VNET_NAME \
  --registration-enabled true  # auto-register VM hostnames

az network private-dns record-set a add-record \
  --resource-group $RG \
  --zone-name "internal.mycompany.com" \
  --record-set-name "db" \
  --ipv4-address "10.0.2.4"
```

## Azure DNS Private Resolver

```bash
# For hybrid DNS (on-premises ↔ Azure)
az dns-resolver create \
  --name dnsresolver-prod \
  --resource-group $RG \
  --location $LOCATION \
  --id $(az network vnet show --name $VNET_NAME --resource-group $RG --query id -o tsv)

# Inbound endpoint (on-premises → Azure DNS)
az dns-resolver inbound-endpoint create \
  --dns-resolver-name dnsresolver-prod \
  --resource-group $RG \
  --name inbound-endpoint \
  --ip-configurations '[{"privateIpAllocationMethod":"Dynamic","id":"'$SUBNET_ID'"}]'

# Outbound endpoint (Azure → on-premises DNS)
az dns-resolver outbound-endpoint create \
  --dns-resolver-name dnsresolver-prod \
  --resource-group $RG \
  --name outbound-endpoint \
  --id $SUBNET_ID

# Forwarding ruleset
az dns-resolver forwarding-ruleset create \
  --name ruleset-prod \
  --resource-group $RG \
  --outbound-endpoints '[{"id":"'$OUTBOUND_ENDPOINT_ID'"}]'

# Forward on-premises domain to on-premises DNS
az dns-resolver forwarding-rule create \
  --ruleset-name ruleset-prod \
  --resource-group $RG \
  --name forward-onprem \
  --domain-name "corp.internal." \
  --target-dns-servers '[{"ipAddress":"192.168.1.10","port":53}]'
```

## VPN Gateway

```bash
# Create VPN Gateway (takes 30-45 minutes)
# First create gateway subnet
az network vnet subnet create \
  --name GatewaySubnet \
  --resource-group $RG \
  --vnet-name $VNET_NAME \
  --address-prefix 10.0.255.0/27

# Create public IP for gateway
az network public-ip create \
  --name pip-vpngw \
  --resource-group $RG \
  --sku Standard \
  --allocation-method Static \
  --zone 1 2 3

# Create VPN Gateway
az network vnet-gateway create \
  --name vpngw-prod \
  --resource-group $RG \
  --location $LOCATION \
  --vnet $VNET_NAME \
  --gateway-type Vpn \
  --vpn-type RouteBased \
  --sku VpnGw2AZ \
  --public-ip-address pip-vpngw \
  --no-wait

# Site-to-site VPN (connect to on-premises)
az network local-gateway create \
  --name lgw-onprem \
  --resource-group $RG \
  --location $LOCATION \
  --gateway-ip-address "203.0.113.1" \
  --local-address-prefixes "192.168.0.0/16"

az network vpn-connection create \
  --name conn-to-onprem \
  --resource-group $RG \
  --vnet-gateway1 vpngw-prod \
  --local-gateway2 lgw-onprem \
  --shared-key "$(openssl rand -hex 32)" \
  --connection-type IPsec

# Point-to-site VPN (individual users)
az network vnet-gateway update \
  --name vpngw-prod \
  --resource-group $RG \
  --address-prefixes "172.16.0.0/24" \
  --client-protocol OpenVPN \
  --vpn-auth-type AAD \
  --aad-tenant "https://login.microsoftonline.com/$TENANT_ID/" \
  --aad-audience "41b23e61-6c1e-4545-b367-cd054e0ed4b4" \
  --aad-issuer "https://sts.windows.net/$TENANT_ID/"
```

## ExpressRoute

```
ExpressRoute = dedicated private connection to Azure
├── Not over public internet
├── More reliable, faster, lower latency than VPN
├── Bandwidth: 50Mbps to 100Gbps
├── Connectivity models:
│   ├── CloudExchange co-location (at carrier-neutral facility)
│   ├── Point-to-point Ethernet connection
│   └── Any-to-any (IPVPN) network
└── Pricing: circuit + gateway + data transfer

ExpressRoute vs VPN:
  VPN:          Over internet, encrypted, up to 10Gbps, lower cost
  ExpressRoute: Private, not encrypted (add MACsec), up to 100Gbps, higher cost

ExpressRoute Global Reach:
  Connect on-premises sites via Azure backbone
  Site A → ExpressRoute → Azure → ExpressRoute → Site B
```

```bash
# Create ExpressRoute circuit
az network express-route create \
  --name er-circuit-prod \
  --resource-group $RG \
  --location $LOCATION \
  --bandwidth 1000 \
  --peering-location "Silicon Valley" \
  --provider "Equinix" \
  --sku-family MeteredData \
  --sku-tier Standard

# Get service key (give to provider)
az network express-route show \
  --name er-circuit-prod \
  --resource-group $RG \
  --query "serviceKey"

# Create ExpressRoute Gateway
az network vnet-gateway create \
  --name ergw-prod \
  --resource-group $RG \
  --vnet $VNET_NAME \
  --gateway-type ExpressRoute \
  --sku ErGw2AZ \
  --public-ip-address pip-ergw

# Connect gateway to circuit
az network vpn-connection create \
  --name conn-er \
  --resource-group $RG \
  --vnet-gateway1 ergw-prod \
  --express-route-circuit2 er-circuit-prod \
  --connection-type ExpressRoute
```

## Interview Questions

### Q1: What is the difference between VPN Gateway and ExpressRoute?
**Answer:**
| | VPN Gateway | ExpressRoute |
|---|---|---|
| Connection | Over public internet | Private, dedicated |
| Encryption | IPsec (always encrypted) | Not encrypted by default (add MACsec) |
| Bandwidth | Up to 10 Gbps | Up to 100 Gbps |
| Latency | Variable (internet) | Consistent, low |
| Reliability | Internet SLA | Carrier SLA (99.95%) |
| Cost | Lower | Higher |
| Setup time | Hours | Weeks (carrier provisioning) |
| Use case | Dev/test, small offices | Enterprise, compliance, high bandwidth |

### Q2: What is Azure Private DNS and when do you need it?
**Answer:**
Private DNS zones provide DNS resolution within VNets without exposing DNS to the internet. Use when:
- Resources need to resolve each other by hostname (not IP)
- Private endpoints need DNS resolution (required for private endpoints to work)
- Hybrid environments need consistent DNS across on-premises and Azure
- Microservices need service discovery

Auto-registration: link zone to VNet with registration enabled → VMs automatically get DNS records.

### Q3: What is the difference between Azure DNS and Azure Private DNS Resolver?
**Answer:**
- **Azure DNS**: Hosts public DNS zones. Resolves public domain names.
- **Private DNS zones**: Resolves private names within VNets.
- **Private DNS Resolver**: Enables conditional forwarding between on-premises DNS and Azure DNS. Needed when on-premises servers need to resolve Azure private DNS names, or Azure resources need to resolve on-premises names.

### Q4: How do you design DNS for a hybrid environment?
**Answer:**
1. On-premises DNS server forwards Azure private zones to Azure DNS Resolver inbound endpoint
2. Azure DNS Resolver outbound endpoint forwards on-premises zones to on-premises DNS
3. Azure resources use Azure DNS (168.63.129.16) by default
4. Private DNS zones for all Azure services (privatelink.*)
5. Custom DNS server in VNet if needed for complex scenarios

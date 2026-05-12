# Architecture — Custom VNet

## ASCII Diagram

```
                        ┌─────────────────────────────────────────────────────┐
                        │              Azure Virtual Network                   │
                        │              10.0.0.0/16  (vnet-main)               │
                        │                                                       │
  ┌──────────┐          │  ┌─────────────────────────────────────────────┐    │
  │          │  HTTP/   │  │  Public Subnet — subnet-web (10.0.1.0/24)   │    │
  │ Internet │──HTTPS──►│  │                                              │    │
  │          │          │  │  ┌──────────┐    ┌──────────────────────┐   │    │
  └──────────┘          │  │  │  NSG-Web │    │   Web VMs / App GW   │   │    │
                        │  │  │ Allow 80 │───►│   (internet-facing)  │   │    │
                        │  │  │ Allow 443│    └──────────┬───────────┘   │    │
                        │  │  └──────────┘               │               │    │
                        │  └─────────────────────────────┼───────────────┘    │
                        │                                 │ port 8080          │
                        │  ┌──────────────────────────────▼──────────────┐    │
                        │  │  Private Subnet — subnet-app (10.0.2.0/24)  │    │
                        │  │                                              │    │
                        │  │  ┌──────────┐    ┌──────────────────────┐   │    │
                        │  │  │  NSG-App │    │   App VMs / AKS      │   │    │
                        │  │  │ Allow    │───►│   (no public IP)     │   │    │
                        │  │  │ from Web │    └──────────┬───────────┘   │    │
                        │  │  └──────────┘               │               │    │
                        │  │                              │ NAT GW ──────►│Internet
                        │  └──────────────────────────────┼───────────────┘    │
                        │                                 │ port 1433          │
                        │  ┌──────────────────────────────▼──────────────┐    │
                        │  │  Private Subnet — subnet-db (10.0.3.0/24)   │    │
                        │  │                                              │    │
                        │  │  ┌──────────┐    ┌──────────────────────┐   │    │
                        │  │  │  NSG-DB  │    │   Azure SQL / VMs    │   │    │
                        │  │  │ Allow SQL│───►│   (most restricted)  │   │    │
                        │  │  │ from App │    └──────────────────────┘   │    │
                        │  │  │ Deny All │                               │    │
                        │  │  └──────────┘                               │    │
                        │  └─────────────────────────────────────────────┘    │
                        │                                                       │
                        │  ┌─────────────────────────────────────────────┐    │
                        │  │  NAT Gateway (nat-gateway-main)              │    │
                        │  │  Public IP: pip-nat-gateway (Static)         │    │
                        │  │  Attached to: subnet-app, subnet-db          │    │
                        │  └─────────────────────────────────────────────┘    │
                        └─────────────────────────────────────────────────────┘
```

## Key Concepts

| Concept | Explanation |
|---|---|
| VNet | Isolated network in Azure. Nothing enters or leaves without explicit rules. |
| Subnet | Logical subdivision of the VNet. Each tier gets its own subnet. |
| NSG | Stateful firewall at subnet or NIC level. Rules evaluated by priority (lower = first). |
| NAT Gateway | Provides outbound internet for private subnets with a predictable static IP. |
| Route Table | Overrides Azure's default routing. Use to force traffic through NVAs or block paths. |
| Service Endpoint | Extends VNet identity to Azure PaaS services (e.g., Storage, SQL) over Azure backbone. |
| Private Endpoint | Gives a PaaS service a private IP inside your VNet — stronger isolation than service endpoints. |

## Traffic Flow

### Inbound (Internet → Web Tier)
```
Internet → NSG-Web (Allow 80/443) → subnet-web → Web VM
```

### Web → App Tier
```
subnet-web (10.0.1.x) → NSG-App (Allow from 10.0.1.0/24 on 8080) → subnet-app → App VM
```

### App → DB Tier
```
subnet-app (10.0.2.x) → NSG-DB (Allow from 10.0.2.0/24 on 1433) → subnet-db → Azure SQL
```

### Outbound (Private Subnets → Internet)
```
subnet-app/subnet-db → NAT Gateway → pip-nat-gateway (static IP) → Internet
```

## NSG Rule Priority Order

NSG rules are evaluated lowest priority number first. First matching rule wins.

```
Priority 100  — Allow specific traffic (e.g., HTTP, SQL from known source)
Priority 200  — Allow management traffic (e.g., SSH from bastion)
Priority 4000 — Deny all (explicit catch-all)
Priority 65500 — DenyAllInBound (Azure default, always last)
```

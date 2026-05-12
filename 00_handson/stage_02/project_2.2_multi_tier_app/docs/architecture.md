# Architecture — Multi-Tier Application

## ASCII Diagram

```
  ┌─────────────────────────────────────────────────────────────────────┐
  │                        Global Layer                                  │
  │                                                                       │
  │   ┌──────────┐     ┌─────────────────────────────────────────────┐  │
  │   │          │     │         Azure Front Door (Standard)          │  │
  │   │ Internet │────►│  • Anycast routing (PoP in 100+ locations)  │  │
  │   │          │     │  • WAF policies                              │  │
  │   └──────────┘     │  • Health probes to App Gateway              │  │
  │                    └──────────────────┬──────────────────────────┘  │
  └───────────────────────────────────────┼─────────────────────────────┘
                                          │ HTTPS
  ┌───────────────────────────────────────▼─────────────────────────────┐
  │                    Azure Region (East US)                            │
  │                                                                       │
  │   ┌─────────────────────────────────────────────────────────────┐   │
  │   │              Virtual Network (10.1.0.0/16)                   │   │
  │   │                                                               │   │
  │   │  ┌──────────────────────────────────────────────────────┐   │   │
  │   │  │  subnet-appgw (10.1.0.0/24)                          │   │   │
  │   │  │                                                        │   │   │
  │   │  │  ┌──────────────────────────────────────────────┐    │   │   │
  │   │  │  │  Application Gateway WAF_v2                   │    │   │   │
  │   │  │  │  • SSL termination                            │    │   │   │
  │   │  │  │  • Path-based routing                         │    │   │   │
  │   │  │  │  • WAF (OWASP 3.2)                            │    │   │   │
  │   │  │  │  • Backend health probes                      │    │   │   │
  │   │  │  └──────────────────────┬───────────────────────┘    │   │   │
  │   │  └─────────────────────────┼──────────────────────────── ┘   │   │
  │   │                            │ HTTP port 80                      │   │
  │   │  ┌─────────────────────────▼──────────────────────────────┐   │   │
  │   │  │  subnet-web (10.1.1.0/24)                               │   │   │
  │   │  │                                                          │   │   │
  │   │  │  ┌────────────────────────────────────────────────┐    │   │   │
  │   │  │  │  VM Scale Set (vmss-web)                        │    │   │   │
  │   │  │  │  • 2–10 instances (Standard_B2s)                │    │   │   │
  │   │  │  │  • Ubuntu 22.04 + Nginx/App                     │    │   │   │
  │   │  │  │  • Autoscale: CPU > 70% → scale out             │    │   │   │
  │   │  │  │  • Autoscale: CPU < 30% → scale in              │    │   │   │
  │   │  │  └────────────────────────┬───────────────────────┘    │   │   │
  │   │  └───────────────────────────┼──────────────────────────── ┘   │   │
  │   │                              │ TCP 1433                          │   │
  │   │  ┌───────────────────────────▼──────────────────────────────┐   │   │
  │   │  │  subnet-db (10.1.2.0/24)                                  │   │   │
  │   │  │                                                            │   │   │
  │   │  │  ┌────────────────────────────────────────────────────┐  │   │   │
  │   │  │  │  Azure SQL (Managed)                                │  │   │   │
  │   │  │  │  • S1 tier (20 DTU)                                 │  │   │   │
  │   │  │  │  • Geo-redundant backups                            │  │   │   │
  │   │  │  │  • VNet service endpoint                            │  │   │   │
  │   │  │  └────────────────────────────────────────────────────┘  │   │   │
  │   │  └────────────────────────────────────────────────────────── ┘   │   │
  │   └─────────────────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────────────────┘
```

## Key Concepts

| Concept | Explanation |
|---|---|
| Azure Front Door | Global anycast entry point. Routes users to nearest healthy origin. Includes CDN and WAF. |
| Application Gateway v2 | Regional L7 load balancer. Handles SSL termination, path routing, WAF, session affinity. |
| VM Scale Sets | Group of identical VMs that scale in/out automatically based on metrics or schedules. |
| Azure SQL | Fully managed SQL Server. Handles patching, backups, HA automatically. |
| WAF (Web Application Firewall) | Protects against OWASP Top 10 (SQLi, XSS, etc.). Can run in Detection or Prevention mode. |
| Backend Health Probe | App Gateway periodically checks if backend VMs are healthy before sending traffic. |
| Autoscale | VMSS scales based on CPU, memory, or custom metrics. Cooldown prevents thrashing. |

## Traffic Flow

```
User → Front Door PoP (nearest) → App Gateway (WAF check) → VMSS instance → Azure SQL
```

## Health Check Hierarchy

```
Front Door health probe → App Gateway (checks /health endpoint)
App Gateway backend probe → VMSS instances (checks HTTP 200)
VMSS application health extension → reports instance health to Azure
```

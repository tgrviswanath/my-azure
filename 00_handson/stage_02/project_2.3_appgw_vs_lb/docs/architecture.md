# Architecture — App Gateway vs Load Balancer

## ASCII Diagram

```
                    ┌─────────────────────────────────────────────────────────┐
                    │              Shared VNet (10.2.0.0/16)                   │
                    │                                                           │
  ┌──────────┐      │  ┌──────────────────────────────────────────────────┐   │
  │          │      │  │  STACK A — Application Gateway (L7)               │   │
  │ Internet │──────┼─►│                                                   │   │
  │          │      │  │  pip-appgw (Static)                               │   │
  └──────────┘      │  │  ↓                                                │   │
                    │  │  Application Gateway Standard_v2                  │   │
                    │  │  subnet-appgw (10.2.0.0/24)                       │   │
                    │  │                                                    │   │
                    │  │  Routing rules:                                    │   │
                    │  │    /api/*      → api-backend-pool                  │   │
                    │  │    /static/*   → static-backend-pool               │   │
                    │  │    /* (default)→ web-backend-pool                  │   │
                    │  │                                                    │   │
                    │  │  ↓                                                 │   │
                    │  │  Backend VMs (subnet-appgw-backend 10.2.1.0/24)   │   │
                    │  │  [VM1] [VM2]  ← receives plain HTTP               │   │
                    │  └──────────────────────────────────────────────────┘   │
                    │                                                           │
                    │  ┌──────────────────────────────────────────────────┐   │
                    │  │  STACK B — Azure Load Balancer (L4)               │   │
                    │  │                                                    │   │
                    │  │  pip-lb (Static)                                   │   │
                    │  │  ↓                                                 │   │
                    │  │  Azure Load Balancer Standard                      │   │
                    │  │  (no subnet — it's a regional service)             │   │
                    │  │                                                    │   │
                    │  │  Rules:                                            │   │
                    │  │    TCP:80 → backend-pool (round-robin / hash)      │   │
                    │  │    TCP:443 → backend-pool                          │   │
                    │  │                                                    │   │
                    │  │  ↓                                                 │   │
                    │  │  Backend VMs (subnet-lb-backend 10.2.2.0/24)      │   │
                    │  │  [VM1] [VM2]  ← receives raw TCP packets          │   │
                    │  └──────────────────────────────────────────────────┘   │
                    └─────────────────────────────────────────────────────────┘
```

## Feature Comparison Table

| Feature | Application Gateway | Azure Load Balancer |
|---|---|---|
| OSI Layer | 7 (Application) | 4 (Transport) |
| Protocol | HTTP, HTTPS, WebSocket | TCP, UDP |
| SSL Termination | Yes | No (pass-through) |
| Path-based routing | Yes | No |
| Host-based routing | Yes | No |
| WAF | Yes (WAF_v2 SKU) | No |
| Session affinity | Cookie-based | Source IP hash |
| Health probes | HTTP (checks response) | TCP/HTTP (checks port) |
| Backend types | VMs, VMSS, App Service, IPs | VMs, VMSS, IPs |
| Latency | ~5–20ms overhead | Sub-millisecond |
| Pricing | ~$125/month base | ~$18/month base |
| Subnet required | Yes (dedicated) | No |
| Zone redundancy | Yes (v2) | Yes (Standard) |

## When to Use Each

**Use Application Gateway when:**
- Hosting web applications or REST APIs
- Need SSL termination to offload crypto from VMs
- Need WAF protection (OWASP rules)
- Need path-based routing (`/api` vs `/web`)
- Need host-based routing (multiple domains on one IP)

**Use Azure Load Balancer when:**
- Load balancing non-HTTP traffic (databases, game servers, custom TCP)
- Need lowest possible latency
- Internal service-to-service load balancing
- Cost is a constraint
- Simple round-robin is sufficient

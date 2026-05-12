# Architecture — Azure DNS + Traffic Manager

## ASCII Diagram

```
  ┌──────────────────────────────────────────────────────────────────────┐
  │                         DNS Resolution Flow                           │
  │                                                                        │
  │   Client                                                               │
  │     │                                                                  │
  │     │  1. DNS query: www.yourdomain.com                               │
  │     ▼                                                                  │
  │   ┌─────────────────────────────────────────────────────────────┐    │
  │   │  Azure DNS Zone (yourdomain.com)                             │    │
  │   │                                                               │    │
  │   │  Records:                                                     │    │
  │   │    www    CNAME → tm-main.trafficmanager.net                 │    │
  │   │    api    CNAME → myapp.azurewebsites.net                    │    │
  │   │    @      A     → 20.1.2.3                                   │    │
  │   │    @      TXT   → "v=spf1 ..."                               │    │
  │   └──────────────────────────┬──────────────────────────────────┘    │
  │                               │  2. CNAME → trafficmanager.net        │
  │                               ▼                                        │
  │   ┌─────────────────────────────────────────────────────────────┐    │
  │   │  Traffic Manager (tm-main.trafficmanager.net)                │    │
  │   │                                                               │    │
  │   │  Routing Method: Priority                                     │    │
  │   │  TTL: 30 seconds                                              │    │
  │   │  Health probe: HTTP GET /health every 30s                    │    │
  │   │                                                               │    │
  │   │  ┌─────────────────────────────────────────────────────┐    │    │
  │   │  │  Endpoint: endpoint-primary (Priority 1)             │    │    │
  │   │  │  Status: ● Online                                    │    │    │
  │   │  │  Target: pip-primary (20.1.2.3)                      │    │    │
  │   │  └─────────────────────────────────────────────────────┘    │    │
  │   │                                                               │    │
  │   │  ┌─────────────────────────────────────────────────────┐    │    │
  │   │  │  Endpoint: endpoint-secondary (Priority 2)           │    │    │
  │   │  │  Status: ○ Standby (primary is healthy)              │    │    │
  │   │  │  Target: pip-secondary (20.4.5.6)                    │    │    │
  │   │  └─────────────────────────────────────────────────────┘    │    │
  │   └──────────────────────────┬──────────────────────────────────┘    │
  │                               │  3. Returns IP of healthy endpoint     │
  │                               ▼                                        │
  │   Client connects directly to endpoint IP (Traffic Manager not in path)│
  └──────────────────────────────────────────────────────────────────────┘

  ─────────────────────────────────────────────────────────────────────────
  Failover Scenario (primary goes down):
  ─────────────────────────────────────────────────────────────────────────

  Primary endpoint fails health probe
       │
       ▼ (after 3 consecutive failures × 30s interval = ~90s)
  Traffic Manager marks endpoint-primary as Degraded
       │
       ▼
  Traffic Manager returns endpoint-secondary IP for new DNS queries
       │
       ▼ (after TTL expires on cached responses = 30s)
  All clients now connect to secondary endpoint
```

## Routing Methods Comparison

| Method | DNS Returns | Best For |
|---|---|---|
| Priority | Highest-priority healthy endpoint | Active/passive failover |
| Weighted | Random endpoint weighted by value | Canary, A/B testing |
| Performance | Endpoint with lowest latency to client | Global apps |
| Geographic | Endpoint mapped to client's region | Data residency |
| Multivalue | All healthy endpoints (up to 8) | Client-side load balancing |
| Subnet | Endpoint mapped to client IP range | Custom routing |

## Key Concepts

| Concept | Explanation |
|---|---|
| Traffic Manager is DNS-based | It doesn't proxy traffic — it just returns different IPs. Client connects directly to endpoint. |
| TTL | How long clients cache the DNS response. Lower TTL = faster failover but more DNS queries. |
| Health probe | Traffic Manager polls each endpoint's HTTP/HTTPS/TCP endpoint. 3 failures = degraded. |
| Nested profiles | A Traffic Manager endpoint can point to another Traffic Manager profile. Combine routing methods. |
| Endpoint types | Azure (ARM resource), External (any IP/FQDN), Nested (another TM profile) |
| Real User Measurements | Optional: clients report actual latency to Azure regions, improving Performance routing accuracy. |

# Project 2.4 — Azure DNS + Traffic Manager

## What It Does

Configures Azure DNS and Traffic Manager for intelligent global traffic routing:
- **Azure DNS Zone** — Hosts DNS records for your domain
- **Traffic Manager** — Routes traffic based on policy (failover, latency, weighted, geographic)
- **Health Probes** — Automatically detects endpoint failures and reroutes
- **Failover routing** — Primary endpoint takes all traffic; secondary activates on failure

## Azure Services Used

| Service | Purpose |
|---|---|
| Azure DNS Zone | Authoritative DNS for your domain |
| Traffic Manager Profile | Global traffic routing with health probes |
| Traffic Manager Endpoints | Azure or external endpoints to route to |
| Public IPs | Endpoints for Traffic Manager |

## Routing Methods

| Method | How It Works | Use Case |
|---|---|---|
| Priority | Route to highest-priority healthy endpoint | Active/passive failover |
| Weighted | Distribute traffic by weight (0–1000) | Canary deployments, A/B testing |
| Performance | Route to lowest-latency endpoint | Global apps with regional backends |
| Geographic | Route based on user's geography | Data residency, regional content |
| Multivalue | Return multiple healthy endpoints | DNS-based load balancing |
| Subnet | Route based on client IP subnet | Custom routing for known IP ranges |

## How to Deploy

```bash
cd terraform/
terraform init
terraform plan -var="dns_zone_name=yourdomain.com" -out=tfplan
terraform apply tfplan
```

### Verify DNS
```bash
pip install azure-mgmt-dns azure-mgmt-trafficmanager azure-identity
python code/dns_checker.py --resource-group rg-dns-lab
```

### Test failover
```bash
# Disable primary endpoint
az network traffic-manager endpoint update \
  --resource-group rg-dns-lab \
  --profile-name tm-main \
  --name endpoint-primary \
  --type azureEndpoints \
  --endpoint-status Disabled

# Watch Traffic Manager switch to secondary
nslookup tm-main.trafficmanager.net
```

### Cleanup
```bash
az group delete --name rg-dns-lab --yes --no-wait
```

## Lessons Learned

- **Traffic Manager is DNS-based** — it returns different IP addresses based on routing policy; it doesn't proxy traffic
- **TTL matters** — low TTL (30s) means faster failover but more DNS queries; high TTL (300s) means slower failover
- **Health probe interval** — minimum 10 seconds; faster probes = faster failover detection
- **Traffic Manager doesn't work with private IPs** — endpoints must be publicly reachable
- **DNS propagation delay** — even after Traffic Manager switches, clients may cache the old IP for the TTL duration
- **Nested profiles** — combine routing methods (e.g., geographic → performance within each region)

## Code

See `code/dns_checker.py` — lists DNS records, checks Traffic Manager routing method, and reports endpoint health.

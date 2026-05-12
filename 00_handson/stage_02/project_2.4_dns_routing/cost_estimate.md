# Cost Estimate — Azure DNS + Traffic Manager

## Monthly Cost Breakdown

| Resource | Pricing Model | Usage | Monthly Cost |
|---|---|---|---|
| Azure DNS Zone | $0.50/zone/month | 1 zone | $0.50 |
| DNS Queries (first 1B) | $0.40/million | ~1M queries | $0.40 |
| Traffic Manager Profile | $0.36/month | 1 profile | $0.36 |
| Traffic Manager Queries | $0.54/million | ~1M queries | $0.54 |
| Traffic Manager Health Checks | $0.36/endpoint/month | 2 endpoints | $0.72 |
| Public IPs (2x Standard) | $3.65/month each | 2 | $7.30 |

## Total Estimated Monthly Cost: ~$9.82/month

---

## Traffic Manager Pricing Detail

| Component | Price |
|---|---|
| DNS queries (first 1 billion/month) | $0.54 per million |
| DNS queries (over 1 billion/month) | $0.27 per million |
| Health checks (Azure endpoints) | $0.36 per endpoint/month |
| Health checks (external endpoints) | $1.44 per endpoint/month |
| Real User Measurements | $2.00 per 100,000 measurements |

## Azure DNS Pricing Detail

| Component | Price |
|---|---|
| Hosted DNS zones (first 25) | $0.50 per zone/month |
| DNS queries (first 1 billion/month) | $0.40 per million |
| DNS queries (over 1 billion/month) | $0.20 per million |

## Cost Notes

- Traffic Manager is extremely cheap — the main cost is the endpoints (VMs, App Services) behind it
- DNS zones are nearly free for learning purposes
- Real cost comes from the Azure resources Traffic Manager routes to
- For a global app with 10M queries/month: Traffic Manager adds only ~$5.40/month

## Teardown to $0

```bash
az group delete --name rg-dns-lab --yes --no-wait
```

# Cost Estimate — Failure Simulation

## Monthly Cost Breakdown (if left running)

| Resource | SKU / Tier | Qty | Unit Cost | Monthly Total |
|---|---|---|---|---|
| Linux VM | Standard_B1s (1 vCPU, 1 GB) | 1 | ~$7.59 | $7.59 |
| Azure SQL Database | Basic (5 DTU) | 1 | ~$4.99 | $4.99 |
| Public IP | Standard Static | 1 | ~$3.65 | $3.65 |
| VNet + Subnet + NSG | — | 1 | Free | $0.00 |
| OS Disk (Standard HDD) | 30 GB | 1 | ~$1.20 | $1.20 |

## Total if Left Running: ~$17.43/month

---

## Actual Cost for This Lab

This lab is designed to run for **1–2 hours**, not a full month.

| Duration | Estimated Cost |
|---|---|
| 1 hour | ~$0.02 |
| 4 hours | ~$0.10 |
| 1 day | ~$0.58 |
| 1 week | ~$4.06 |

## Cost During Chaos Actions

- **VM deallocated** — compute billing stops immediately; disk and IP still billed
- **NSG changes** — no cost impact
- **SQL failover** — no extra cost; same billing tier

## Teardown to $0

```bash
az group delete --name rg-chaos-lab --yes --no-wait
```

Always run this after the lab. The whole point is to learn, not to pay for idle resources.

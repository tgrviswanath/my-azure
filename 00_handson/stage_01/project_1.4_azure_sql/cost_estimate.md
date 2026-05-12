# Cost Estimate — Project 1.4 Azure SQL Database

| Resource | SKU | Monthly Cost |
|----------|-----|-------------|
| Azure SQL Server | Logical server (free) | $0 |
| Azure SQL Database | Basic (5 DTU, 2 GB) | ~$4.99 |
| Backup Storage | Included in Basic | $0 |
| Firewall Rules | Free | $0 |
| **Total (Basic)** | | **~$4.99/month** |

## Service Tier Comparison
| Tier | DTUs | Storage | Monthly Cost | Use Case |
|------|------|---------|-------------|---------|
| Basic | 5 | 2 GB | ~$4.99 | Dev/test, learning |
| Standard S0 | 10 | 250 GB | ~$15.03 | Light production |
| Standard S1 | 20 | 250 GB | ~$30.06 | Small production |
| Standard S2 | 50 | 250 GB | ~$75.14 | Medium production |
| Premium P1 | 125 | 500 GB | ~$465.00 | High performance |

## vCore Model (more flexible)
| Tier | vCores | Monthly Cost |
|------|--------|-------------|
| General Purpose 2 vCore | 2 | ~$368/month |
| Serverless (auto-pause) | 0.5-2 | ~$0.50/hour active |

## Cost Saving Tips
- Basic tier is perfect for learning — $4.99/month
- Use Serverless tier for dev: auto-pauses after 1 hour idle, ~$0/month when paused
- Delete the database (not server) when not in use — server itself is free
- Geo-replication doubles the database cost (secondary region)
- Azure Hybrid Benefit: use existing SQL Server licenses for up to 55% discount

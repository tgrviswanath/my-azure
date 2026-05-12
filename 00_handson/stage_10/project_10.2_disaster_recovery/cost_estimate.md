# Cost Estimate — Project 10.2 Disaster Recovery Architecture

## Summary

| Item | Monthly Cost |
|------|-------------|
| Azure SQL primary (S1) | ~$30 |
| Azure SQL secondary (geo-replica) | ~$30 |
| Failover group | $0 |
| GRS Storage (10GB) | ~$0.46 |
| Traffic Manager (1M queries) | ~$0.54 |
| **Total** | **~$61/month** |

## Notes
- Geo-replica costs the same as the primary database
- GRS storage: 2x the cost of LRS (~$0.046/GB vs $0.023/GB)
- Traffic Manager: $0.54/million DNS queries
- Consider Azure Site Recovery for VM DR: ~$25/VM/month

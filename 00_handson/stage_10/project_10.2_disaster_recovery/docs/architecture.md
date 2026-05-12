# Architecture — Project 10.2 Disaster Recovery Architecture

## Diagram

```
Primary Region (East US)                Secondary Region (West US)
─────────────────────────               ──────────────────────────
App Service (active)                    App Service (standby)
    │                                       │
    │ Traffic Manager (failover routing)    │
    └───────────────────────────────────────┘
                    │
                    ▼
            DNS: fg-handson.database.windows.net
            (always points to current primary)

Azure SQL Primary ──async geo-replication──▶ Azure SQL Secondary
    │ RPO: ~5 seconds                            │ promoted on failover
    │ RTO: ~30 seconds (auto failover)           │

Storage (GRS) ──async replication──▶ Storage (secondary)
    │ RPO: ~15 minutes                   │ read-only until failover
```

## DR Strategies

| Strategy | RTO | RPO | Cost |
|----------|-----|-----|------|
| Backup & Restore | Hours | Hours | Low |
| Pilot Light | 10-30 min | Minutes | Medium |
| Warm Standby | Minutes | Seconds | High |
| Multi-site Active/Active | Seconds | Near-zero | Very High |

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| RTO | Recovery Time Objective — max acceptable downtime |
| RPO | Recovery Point Objective — max acceptable data loss |
| Failover group | Automatic DNS failover for Azure SQL |
| GRS | Geo-redundant storage — async replication to paired region |
| Traffic Manager | DNS-based load balancer with health checks |

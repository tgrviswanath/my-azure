# Project 10.2 — Disaster Recovery Architecture

## What This Does
Implements cross-region disaster recovery for Azure SQL and Storage using geo-replication, failover groups, and automated DNS failover via Traffic Manager.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure SQL Failover Group | Automatic failover for Azure SQL |
| GRS Storage | Geo-redundant storage replication |
| Traffic Manager | DNS-based failover routing |
| Azure Site Recovery | VM replication (optional) |

## Architecture
```
Primary Region (East US)
    ├── Azure SQL (primary)  ──geo-replication──▶  Secondary (West US)
    ├── Storage (GRS)        ──async replication──▶  Secondary (West US)
    └── App Service          ──Traffic Manager──▶  Standby App Service

Traffic Manager (failover routing)
    ├── Primary endpoint: East US (priority 1)
    └── Secondary endpoint: West US (priority 2)
          │ automatic failover on health check failure
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve
python code/dr_failover.py test
```

## Lessons Learned
- RTO: Recovery Time Objective — how long can you be down?
- RPO: Recovery Point Objective — how much data can you lose?
- Failover group: automatic DNS failover for Azure SQL (~30s)
- GRS storage: async replication, ~15 min lag
- Test DR regularly — untested DR plans fail when needed

## Code

### `code/dr_failover.py` — Test, trigger, and verify DR failover

```bash
pip install azure-identity azure-mgmt-sql azure-mgmt-storage
python code/dr_failover.py test
python code/dr_failover.py failover   # WARNING: redirects traffic!
python code/dr_failover.py failback
```

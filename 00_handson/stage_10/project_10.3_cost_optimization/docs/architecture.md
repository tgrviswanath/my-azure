# Architecture — Project 10.3 Cost Optimization Automation

## Diagram

```
Azure Monitor (CPU metrics)
    │ CPU < 5% for 7 days
    ▼
Azure Automation Runbook (scheduled daily)
    ├── Identify idle VMs → deallocate
    ├── Find unattached disks → delete
    ├── Find old snapshots (>30d) → delete
    └── Apply storage lifecycle policies

Azure Advisor
    │ ML-based recommendations
    ├── Rightsize VMs
    ├── Buy Reserved Instances
    ├── Delete unused resources
    └── Storage optimization

Cost Management
    ├── Budget: $500/month
    ├── Alert at 80% → email
    └── Alert at 100% → email + Teams
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Deallocate vs Stop | Deallocate = no compute billing. Stop = still billed! |
| Unattached disk | Disk exists after VM deletion — still billed |
| Reserved Instance | 1-3 year commitment = 40-60% savings |
| Savings Plan | Commit to $/hour spend — flexible across VM sizes |
| Spot VMs | Up to 90% discount — can be evicted with 30s notice |

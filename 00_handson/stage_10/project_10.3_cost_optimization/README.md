# Project 10.3 — Cost Optimization Automation

## What This Does
Automates Azure cost optimization: identifies idle VMs, unattached disks, old snapshots, and rightsizing recommendations using Azure Advisor.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure Advisor | Cost recommendations |
| Azure Automation | Runbooks for cleanup |
| Cost Management | Budgets and alerts |
| Azure Monitor | CPU metrics for idle detection |

## Architecture
```
Azure Advisor
    │ cost recommendations
    ▼
Automation Runbooks (scheduled)
    ├── Stop idle VMs (CPU < 5% for 7 days)
    ├── Delete unattached disks
    ├── Remove old snapshots (> 30 days)
    └── Apply storage lifecycle policies
          │
          ▼
    Cost Management → Budget alerts → Email
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve
python code/cost_optimizer.py --dry-run   # See what would be cleaned
python code/cost_optimizer.py             # Apply optimizations
```

## Lessons Learned
- Azure Advisor: free ML-based recommendations — always check it
- Idle VMs: CPU < 5% for 7 days — deallocate to stop billing
- Unattached disks: still billed even when VM is deleted
- Reserved Instances: 1-year = 40% savings, 3-year = 60% savings
- Savings Plans: commit to $/hour spend — more flexible than RIs

## Code

### `code/cost_optimizer.py` — Find and clean up idle resources

```bash
pip install azure-identity azure-mgmt-compute azure-mgmt-advisor
python code/cost_optimizer.py --dry-run
python code/cost_optimizer.py --action stop-idle-vms
```

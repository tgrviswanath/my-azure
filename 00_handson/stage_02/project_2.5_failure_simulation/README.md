# Project 2.5 — Failure Simulation & Resilience Testing

## What It Does

Deliberately breaks things to learn how Azure systems fail and recover:
- **VM failure** — Deallocate a VM and observe what happens to traffic
- **NSG lockout** — Remove allow rules to simulate a misconfigured firewall
- **DB failure** — Trigger Azure SQL failover to test application resilience
- **Restore** — Roll back all chaos actions from a JSON rollback log

This is a controlled chaos engineering exercise. All actions are logged for safe rollback.

## Azure Services Used

| Service | Purpose |
|---|---|
| Azure VM (Linux) | Target for VM failure simulation |
| Network Security Group | Target for NSG lockout simulation |
| Azure SQL | Target for DB failover simulation |
| Azure Monitor | Observe alerts during failures |

## How to Deploy

```bash
# Deploy test environment
cd terraform/
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Run chaos simulations
pip install azure-mgmt-compute azure-mgmt-network azure-mgmt-sql azure-identity
python code/chaos_simulator.py stop-vm --resource-group rg-chaos-lab
python code/chaos_simulator.py block-nsg --resource-group rg-chaos-lab
python code/chaos_simulator.py simulate-db-fail --resource-group rg-chaos-lab

# Restore everything
python code/chaos_simulator.py restore --resource-group rg-chaos-lab
```

## Chaos Actions

| Action | What It Does | How to Detect | How to Restore |
|---|---|---|---|
| `stop-vm` | Deallocates a random VM | VM shows "Deallocated" in portal | `restore` action |
| `block-nsg` | Removes all Allow rules from NSG | Traffic stops flowing | `restore` action |
| `simulate-db-fail` | Triggers Azure SQL failover | Connection strings fail briefly | `restore` action |
| `restore` | Reads rollback.json and undoes all actions | All resources back to normal | — |

## Lessons Learned

- **VM deallocation vs stop** — "Stop" keeps the VM allocated (still billed); "Deallocate" releases compute (not billed but loses ephemeral state)
- **NSG rule removal is instant** — traffic stops immediately; no grace period
- **Azure SQL failover takes 20–30 seconds** — applications need retry logic with exponential backoff
- **Always test your rollback procedure** — chaos without a restore plan is just destruction
- **Azure Monitor alerts** — set up alerts before running chaos so you can observe the failure in real time
- **Resilience patterns** — retry with backoff, circuit breaker, health checks, graceful degradation

## Code

See `code/chaos_simulator.py` — implements stop-vm, block-nsg, simulate-db-fail, and restore actions with full rollback logging.

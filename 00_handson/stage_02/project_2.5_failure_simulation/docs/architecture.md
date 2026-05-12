# Architecture — Failure Simulation

## ASCII Diagram

```
  ┌─────────────────────────────────────────────────────────────────────┐
  │                    Test Environment (rg-chaos-lab)                   │
  │                                                                       │
  │   ┌─────────────────────────────────────────────────────────────┐   │
  │   │  Virtual Network (vnet-chaos, 10.3.0.0/16)                   │   │
  │   │                                                               │   │
  │   │  ┌──────────────────────────────────────────────────────┐   │   │
  │   │  │  subnet-vms (10.3.1.0/24)                             │   │   │
  │   │  │                                                        │   │   │
  │   │  │  ┌──────────┐    ┌──────────────────────────────┐    │   │   │
  │   │  │  │ NSG-chaos │    │  vm-chaos-target (B1s)        │    │   │   │
  │   │  │  │           │    │  Ubuntu 22.04                 │    │   │   │
  │   │  │  │ Allow SSH │───►│  Public IP: pip-chaos         │    │   │   │
  │   │  │  │ Allow HTTP│    │                               │    │   │   │
  │   │  │  └──────────┘    └──────────────────────────────┘    │   │   │
  │   │  └──────────────────────────────────────────────────────┘   │   │
  │   │                                                               │   │
  │   │  ┌──────────────────────────────────────────────────────┐   │   │
  │   │  │  Azure SQL (sql-chaos-xxxxx)                          │   │   │
  │   │  │  db-chaos (Basic tier)                                │   │   │
  │   │  └──────────────────────────────────────────────────────┘   │   │
  │   └─────────────────────────────────────────────────────────────┘   │
  │                                                                       │
  │   ┌─────────────────────────────────────────────────────────────┐   │
  │   │  chaos_simulator.py                                          │   │
  │   │                                                               │   │
  │   │  Actions:                                                     │   │
  │   │    stop-vm        → Deallocate vm-chaos-target               │   │
  │   │    block-nsg      → Remove all Allow rules from nsg-chaos    │   │
  │   │    simulate-db-fail → Trigger SQL failover                   │   │
  │   │    restore        → Read rollback.json, undo all actions     │   │
  │   │                                                               │   │
  │   │  rollback.json (auto-generated):                             │   │
  │   │    { "actions": [                                            │   │
  │   │        {"type": "start_vm", "vm": "vm-chaos-target"},        │   │
  │   │        {"type": "restore_nsg_rules", "nsg": "nsg-chaos",     │   │
  │   │         "rules": [...]},                                     │   │
  │   │      ]}                                                      │   │
  │   └─────────────────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────────────────┘
```

## Chaos Action Details

| Action | Azure API Call | Observable Effect | Recovery Time |
|---|---|---|---|
| stop-vm | `virtual_machines.begin_deallocate()` | VM shows "Deallocated"; SSH fails | ~2 min to restart |
| block-nsg | Delete all NSG security rules | All inbound traffic blocked | Instant on restore |
| simulate-db-fail | `databases.begin_failover()` | SQL connections fail for 20–30s | Automatic |
| restore | Reverse all logged actions | All resources back to normal | ~3–5 min total |

## Resilience Patterns to Test

```
1. Retry with exponential backoff
   ─────────────────────────────
   Attempt 1: fail → wait 1s
   Attempt 2: fail → wait 2s
   Attempt 3: fail → wait 4s
   Attempt 4: success ✔

2. Circuit Breaker
   ─────────────────────────────
   Closed → Open (after N failures) → Half-Open (probe) → Closed

3. Health Check Endpoint
   ─────────────────────────────
   GET /health → 200 OK (all dependencies healthy)
              → 503 Service Unavailable (DB down)

4. Graceful Degradation
   ─────────────────────────────
   DB unavailable → serve cached data → show "limited functionality" banner
```

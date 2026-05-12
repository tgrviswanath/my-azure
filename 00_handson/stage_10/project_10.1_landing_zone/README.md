# Project 10.1 — Multi-subscription Azure Landing Zone

## What This Does
Implements an Azure Landing Zone following the Cloud Adoption Framework (CAF). Sets up Management Group hierarchy, Azure Policy initiatives, RBAC at scale, and enterprise governance.

## Services Used
| Service | Purpose |
|---------|---------|
| Management Groups | Organize subscriptions into hierarchy |
| Azure Policy | Enforce compliance at scale |
| RBAC | Role assignments at MG level |
| Defender for Cloud | Security posture across all subscriptions |
| Cost Management | Budgets and alerts per subscription |

## Architecture
```
Tenant Root Group
    │
    ├── Platform MG
    │     ├── Identity subscription
    │     ├── Management subscription
    │     └── Connectivity subscription
    │
    └── Landing Zones MG
          ├── Corp MG (internal apps)
          │     ├── Dev subscription
          │     ├── QA subscription
          │     └── Prod subscription
          └── Online MG (internet-facing)
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve
python code/org_manager.py
```

## Lessons Learned
- Management Groups: up to 6 levels deep, policies inherit downward
- Policy at MG level: applies to all subscriptions in the group
- RBAC at MG level: assign roles once, applies to all child subscriptions
- Landing Zone: a subscription with guardrails (policies, RBAC, networking)

## Code

### `code/org_manager.py` — List management groups and policy assignments

```bash
pip install azure-identity azure-mgmt-managementgroups azure-mgmt-resource
python code/org_manager.py
```

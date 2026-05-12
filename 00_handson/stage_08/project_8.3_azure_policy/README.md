# Project 8.3 — Azure Policy Compliance Automation

## What This Does
Enforces compliance across Azure resources using Azure Policy. Audits non-compliant resources and auto-remediates them.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure Policy | Define and enforce compliance rules |
| Policy Initiatives | Group related policies |
| Remediation Tasks | Auto-fix non-compliant resources |
| Compliance Dashboard | View compliance state |

## Architecture
```
Policy Definition (what to enforce)
    │ assigned to scope (subscription/RG)
    ▼
Policy Assignment
    │ evaluates all resources in scope
    ▼
Compliance State: COMPLIANT / NON_COMPLIANT
    │ non-compliant resources
    ▼
Remediation Task (auto-fix)
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve
python code/compliance_checker.py
```

## Lessons Learned
- Policy effects: Deny, Audit, Append, Modify, DeployIfNotExists
- Use Audit first — understand impact before switching to Deny
- DeployIfNotExists: auto-deploy missing resources (e.g., enable diagnostics)
- Policy is free — use it extensively for governance

## Code

### `code/compliance_checker.py` — Check compliance status

```bash
pip install azure-identity azure-mgmt-policyinsights
python code/compliance_checker.py
```

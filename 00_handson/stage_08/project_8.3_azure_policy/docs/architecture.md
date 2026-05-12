# Architecture — Project 8.3 Azure Policy Compliance Automation

## Diagram

```
Policy Definition
  (what to check/enforce)
        │ assigned to scope
        ▼
Policy Assignment
  (subscription / management group / resource group)
        │ evaluates all resources
        ▼
Compliance Evaluation (runs every 24h or on-demand)
        │
        ├── COMPLIANT → no action
        │
        └── NON_COMPLIANT
              │
              ├── Audit effect → log only
              ├── Deny effect → block resource creation
              ├── Modify effect → add/change tags
              └── DeployIfNotExists → auto-deploy missing resource
                        │
                        ▼
                  Remediation Task
                  (fixes existing non-compliant resources)
```

## Policy Effects

| Effect | Behavior |
|--------|---------|
| Audit | Log non-compliant resources — no blocking |
| Deny | Block resource creation/update if non-compliant |
| Append | Add fields to resource (e.g., tags) |
| Modify | Add/replace/remove tags or properties |
| DeployIfNotExists | Deploy a related resource if missing |
| AuditIfNotExists | Audit if a related resource is missing |

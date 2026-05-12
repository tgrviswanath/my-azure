# Architecture — Project 10.1 Multi-subscription Azure Landing Zone

## Diagram

```
Azure AD Tenant
    │
    └── Tenant Root Management Group
          │
          ├── Platform MG
          │     ├── Policy: Require tags
          │     ├── RBAC: Platform team = Owner
          │     │
          │     ├── Identity Subscription
          │     │     └── Azure AD DS, PIM
          │     ├── Management Subscription
          │     │     └── Log Analytics, Automation, Defender
          │     └── Connectivity Subscription
          │           └── Hub VNet, Firewall, VPN Gateway
          │
          └── Landing Zones MG
                ├── Policy: Allowed locations
                ├── Policy: Azure Security Benchmark
                ├── RBAC: Dev team = Contributor
                │
                ├── Corp MG (internal apps)
                │     ├── Dev Subscription
                │     ├── QA Subscription
                │     └── Prod Subscription
                │
                └── Online MG (internet-facing)
                      └── Prod Subscription
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Management Group | Container for subscriptions — policies inherit downward |
| Landing Zone | Subscription with guardrails (policies, RBAC, networking) |
| Policy inheritance | Policies assigned at MG apply to all child subscriptions |
| RBAC inheritance | Role assignments at MG apply to all child subscriptions |
| Hub-spoke | Connectivity subscription = hub, landing zones = spokes |

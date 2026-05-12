# Cost Estimate — Project 1.3 Azure AD RBAC & Identity Management

| Resource | Monthly Cost |
|----------|-------------|
| Azure Active Directory Free | $0 |
| RBAC Role Assignments | $0 |
| Managed Identity | $0 |
| Azure Monitor (basic audit logs) | $0 |
| **Total (Free tier)** | **$0** |

## Azure AD Tier Comparison
| Feature | Free | P1 ($6/user/mo) | P2 ($9/user/mo) |
|---------|------|-----------------|-----------------|
| RBAC | ✅ | ✅ | ✅ |
| MFA (Security Defaults) | ✅ | ✅ | ✅ |
| Conditional Access | ❌ | ✅ | ✅ |
| Privileged Identity Management (PIM) | ❌ | ❌ | ✅ |
| Identity Protection | ❌ | ❌ | ✅ |
| Access Reviews | ❌ | ✅ | ✅ |

## Notes
- RBAC is free — no charge for role assignments
- Managed Identity is free — no charge for creating or using them
- Azure AD Free supports up to 500,000 directory objects
- For production: Azure AD P1 ($6/user/month) adds Conditional Access
- PIM (just-in-time access) requires P2 — worth it for production

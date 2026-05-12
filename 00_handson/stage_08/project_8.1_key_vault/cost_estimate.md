# Cost Estimate — Project 8.1 Key Vault Integration

## Summary

| Item | Monthly Cost |
|------|-------------|
| Key Vault Standard (secrets operations, 10K/month) | ~$0.03 |
| Managed Identity | $0 |
| RBAC role assignments | $0 |
| **Total** | **~$0.03/month** |

## Notes
- Key Vault is extremely cheap — $0.03 per 10,000 operations
- HSM-backed keys (Premium tier): $1/key/month + $0.03/10K operations
- Certificates: $3/certificate/month (renewal included)

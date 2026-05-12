# Cost Estimate — Project 8.6: Zero Trust Security on Azure

| Service | Unit | Price | Est. Monthly Usage | Est. Monthly Cost |
|---|---|---|---|---|
| Azure AD P2 | Per user/month | $9.00/user | 5 users (lab) | $45.00 |
| Private Endpoint (Key Vault) | Per endpoint/hour | $0.01/hr | 730 hrs | $7.30 |
| Private Endpoint (Storage) | Per endpoint/hour | $0.01/hr | 730 hrs | $7.30 |
| Private DNS Zone | Per zone/month | $0.50/zone | 2 zones | $1.00 |
| Private DNS Queries | Per million queries | $0.60/M | 1M queries | $0.60 |
| Virtual Network | Free | $0 | — | $0.00 |
| Network Security Groups | Free | $0 | — | $0.00 |
| Key Vault (Standard) | Per 10K operations | $0.03 | 10K ops | $0.03 |
| Defender for Cloud (VMs) | Per server/month | $15.00 | 0 VMs (lab) | $0.00 |
| Defender for Cloud (Storage) | Per storage/month | $10.00 | 1 account | $10.00 |
| Defender for Cloud (Key Vault) | Per vault/month | $0.02/10K ops | 10K ops | $0.02 |
| **Total** | | | | **~$71/month** |

## Notes

- **Azure AD P2 is the biggest cost**: Required for Conditional Access risk policies and PIM. For basic MFA enforcement only, Azure AD P1 ($6/user/month) is sufficient.
- **Private Endpoints**: Each PE costs ~$7.30/month. In production you'll have PEs for every service (SQL, Storage, Key Vault, Service Bus, etc.) — costs add up to $50-100/month.
- **Defender for Cloud**: Standard tier per-resource pricing. For a full production environment with 10 VMs + SQL + Storage, expect $200-500/month.
- **Lab cost reduction**:
  - Use Azure AD P2 trial (30 days free)
  - Delete Private Endpoints when not testing (they charge by the hour)
  - Use Defender for Cloud free tier (no threat protection, just recommendations)
- **Production estimate**: Full Zero Trust for 50 users + 20 resources ≈ $500-1000/month
- Always run `az group delete --name $RG --yes` after the lab to stop all charges.

# Cost Estimate — Project 8.2 WAF Application Protection

## Summary

| Item | Monthly Cost |
|------|-------------|
| Application Gateway WAF_v2 (1 CU) | ~$125 |
| WAF Policy | $0 |
| Public IP (Standard) | ~$3 |
| Log Analytics (WAF logs) | ~$2 |
| **Total** | **~$130/month** |

## Notes
- WAF_v2 minimum: $125/month for 1 capacity unit
- Each additional CU: ~$0.008/hour
- Consider Azure Front Door WAF for global deployments (~$35/month base)
- Destroy after learning to avoid ongoing costs

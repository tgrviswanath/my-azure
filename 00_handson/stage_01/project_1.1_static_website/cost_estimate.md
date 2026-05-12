# Cost Estimate — Project 1.1 Static Website on Azure Storage + CDN

| Resource | Details | Monthly Cost |
|----------|---------|-------------|
| Azure Storage Account | Standard LRS, 1 GB | ~$0.02 |
| Storage Operations | 10,000 read operations | ~$0.004 |
| Azure CDN (Microsoft) | 10 GB outbound transfer | ~$0.87 |
| CDN HTTP requests | 100,000 requests | ~$0.075 |
| Azure DNS Zone | 1 zone + 1M queries | ~$0.90 |
| **Total** | | **~$1.87/month** |

## CDN Pricing Breakdown (Microsoft tier)
| Region | Price per GB |
|--------|-------------|
| North America / Europe | $0.087/GB |
| Asia Pacific | $0.138/GB |
| South America | $0.181/GB |

## Cost Saving Tips
- First 5 GB of CDN outbound is free each month
- Storage static website is essentially free at small scale
- Use CDN compression to reduce transfer size by 60-70%
- Set long `Cache-Control` headers to reduce origin requests

## Comparison: Azure vs AWS
| Service | Azure | AWS Equivalent |
|---------|-------|---------------|
| Static hosting | Azure Storage $web | S3 static website |
| CDN | Azure CDN | CloudFront |
| DNS | Azure DNS | Route 53 |
| Monthly cost (10 GB) | ~$1.87 | ~$1.50 |

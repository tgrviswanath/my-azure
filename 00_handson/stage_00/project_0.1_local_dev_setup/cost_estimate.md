# Cost Estimate — Project 0.1 Local Cloud Development Setup

| Item | Monthly Cost |
|------|-------------|
| Azurite (open source) | $0 |
| Docker Desktop (personal use) | $0 |
| Azure CLI | $0 |
| Azure Functions Core Tools | $0 |
| Terraform (open source) | $0 |
| All emulated Azure services | $0 |
| **Total** | **$0** |

## Notes
- This entire project runs locally — zero Azure spend
- Azurite is the official Microsoft Azure Storage emulator
- No Azure subscription activity occurs in this project
- Docker Desktop is free for personal/educational use
- Azure Functions Core Tools v4 is open source (MIT license)

## If You Move to Real Azure (for comparison)
| Service | Estimated Monthly Cost |
|---------|----------------------|
| Azure Storage Account (LRS, 5 GB) | ~$0.10 |
| Azure Functions (Consumption plan, 1M calls) | ~$0.20 |
| Azure Queue Storage (1M operations) | ~$0.004 |
| **Real Azure Total** | **~$0.30** |

Even in real Azure, these services are extremely cheap at dev scale.

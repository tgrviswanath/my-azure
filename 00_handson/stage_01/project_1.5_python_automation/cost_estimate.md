# Cost Estimate — Project 1.5 Python Azure Automation

| Resource | Details | Monthly Cost |
|----------|---------|-------------|
| Azure SDK (open source) | Free | $0 |
| Azure Storage Account | Standard LRS, 10 GB | ~$0.20 |
| Storage Operations | 10,000 write + 10,000 read | ~$0.01 |
| Azure CLI | Free | $0 |
| Python | Free | $0 |
| **Total** | | **~$0.21/month** |

## Notes
- The Azure Python SDK is open source (MIT license) — free to use
- Costs depend entirely on which Azure resources you automate
- Storage is the main cost here — very cheap at small scale
- VM automation itself is free; the VMs you manage have their own costs
- `DefaultAzureCredential` with `az login` is free for local development

## SDK Package Costs
| Package | License | Cost |
|---------|---------|------|
| azure-identity | MIT | $0 |
| azure-storage-blob | MIT | $0 |
| azure-mgmt-compute | MIT | $0 |
| azure-mgmt-resource | MIT | $0 |
| azure-mgmt-storage | MIT | $0 |

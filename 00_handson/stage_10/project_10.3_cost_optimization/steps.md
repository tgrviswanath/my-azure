# Steps — Project 10.3 Cost Optimization Automation

## Phase 1 — Enable Azure Advisor

```bash
# Azure Advisor is always enabled — view recommendations
az advisor recommendation list --category Cost --output table

# Get high-impact cost recommendations
az advisor recommendation list \
  --category Cost \
  --query "[?impact=='High']" \
  --output table
```

---

## Phase 2 — Identify Idle VMs

```bash
# List VMs with low CPU (< 5% average over 7 days)
az monitor metrics list \
  --resource /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/<vm> \
  --metric "Percentage CPU" \
  --interval PT1H \
  --aggregation Average \
  --start-time $(date -d '7 days ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ)
```

---

## Phase 3 — Rightsize Recommendations

```bash
# Get Advisor rightsize recommendations
az advisor recommendation list \
  --category Cost \
  --query "[?shortDescription.problem=='Right-size or shutdown underutilized virtual machines']" \
  --output table
```

---

## Phase 4 — Storage Lifecycle Policies

```bash
# Add lifecycle policy to move blobs to cool/archive tier
az storage account management-policy create \
  --account-name mystorageaccount \
  --resource-group myrg \
  --policy '{
    "rules": [{
      "name": "move-to-cool",
      "type": "Lifecycle",
      "definition": {
        "filters": {"blobTypes": ["blockBlob"]},
        "actions": {
          "baseBlob": {
            "tierToCool": {"daysAfterModificationGreaterThan": 30},
            "tierToArchive": {"daysAfterModificationGreaterThan": 90},
            "delete": {"daysAfterModificationGreaterThan": 365}
          }
        }
      }
    }]
  }'
```

---

## Phase 5 — Reserved Instances Analysis

```bash
# View RI recommendations from Advisor
az advisor recommendation list \
  --category Cost \
  --query "[?shortDescription.problem=='Buy virtual machine reserved instances to save money over pay-as-you-go costs']" \
  --output table
```

---

## Screenshots to Take
- [ ] Azure Advisor cost recommendations
- [ ] Idle VMs identified with CPU metrics
- [ ] Storage lifecycle policy applied
- [ ] Budget alert configured

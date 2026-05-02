#!/bin/bash
# Azure Cost Optimization Scripts
# Find and report on cost-saving opportunities

set -euo pipefail

SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
OUTPUT_FILE="cost-report-$(date +%Y%m%d).txt"

echo "🔍 Azure Cost Optimization Report" | tee $OUTPUT_FILE
echo "   Subscription: $SUBSCRIPTION_ID" | tee -a $OUTPUT_FILE
echo "   Date: $(date)" | tee -a $OUTPUT_FILE
echo "================================================" | tee -a $OUTPUT_FILE

# ── 1. Stopped (not deallocated) VMs ─────────────────────────────────────────
echo "" | tee -a $OUTPUT_FILE
echo "⚠️  VMs that are STOPPED but not DEALLOCATED (still billing for compute):" | tee -a $OUTPUT_FILE
az vm list --query "[].{Name:name,RG:resourceGroup}" -o tsv | while read VM_NAME RG; do
  STATUS=$(az vm get-instance-view \
    --resource-group "$RG" \
    --name "$VM_NAME" \
    --query "instanceView.statuses[1].displayStatus" \
    -o tsv 2>/dev/null)
  if [[ "$STATUS" == "VM stopped" ]]; then
    echo "  ❌ $VM_NAME ($RG) — STOPPED but not deallocated" | tee -a $OUTPUT_FILE
    echo "     Fix: az vm deallocate --resource-group $RG --name $VM_NAME"
  fi
done

# ── 2. Orphaned Managed Disks ─────────────────────────────────────────────────
echo "" | tee -a $OUTPUT_FILE
echo "💾 Orphaned managed disks (not attached to any VM):" | tee -a $OUTPUT_FILE
az disk list \
  --query "[?managedBy==null].{Name:name,RG:resourceGroup,Size:diskSizeGb,SKU:sku.name,Created:timeCreated}" \
  -o table | tee -a $OUTPUT_FILE

ORPHAN_DISK_COUNT=$(az disk list --query "[?managedBy==null] | length(@)" -o tsv)
echo "  Total orphaned disks: $ORPHAN_DISK_COUNT" | tee -a $OUTPUT_FILE

# ── 3. Unused Public IPs ──────────────────────────────────────────────────────
echo "" | tee -a $OUTPUT_FILE
echo "🌐 Unused public IP addresses (not associated with any resource):" | tee -a $OUTPUT_FILE
az network public-ip list \
  --query "[?ipConfiguration==null].{Name:name,RG:resourceGroup,SKU:sku.name,Allocation:publicIpAllocationMethod}" \
  -o table | tee -a $OUTPUT_FILE

# ── 4. Empty Resource Groups ──────────────────────────────────────────────────
echo "" | tee -a $OUTPUT_FILE
echo "📁 Empty resource groups:" | tee -a $OUTPUT_FILE
az group list --query "[].name" -o tsv | while read RG; do
  COUNT=$(az resource list --resource-group "$RG" --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ "$COUNT" == "0" ]]; then
    echo "  📁 $RG (empty)" | tee -a $OUTPUT_FILE
  fi
done

# ── 5. Old Snapshots ──────────────────────────────────────────────────────────
echo "" | tee -a $OUTPUT_FILE
echo "📸 Disk snapshots older than 30 days:" | tee -a $OUTPUT_FILE
CUTOFF=$(date -d "30 days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -v-30d +%Y-%m-%dT%H:%M:%SZ)
az snapshot list \
  --query "[?timeCreated<'$CUTOFF'].{Name:name,RG:resourceGroup,Size:diskSizeGb,Created:timeCreated}" \
  -o table | tee -a $OUTPUT_FILE

# ── 6. Underutilized App Service Plans ───────────────────────────────────────
echo "" | tee -a $OUTPUT_FILE
echo "⚙️  App Service Plans with no apps:" | tee -a $OUTPUT_FILE
az appservice plan list \
  --query "[?numberOfSites==\`0\`].{Name:name,RG:resourceGroup,SKU:sku.name,Workers:numberOfWorkers}" \
  -o table | tee -a $OUTPUT_FILE

# ── 7. Storage accounts with no recent activity ───────────────────────────────
echo "" | tee -a $OUTPUT_FILE
echo "💾 Storage accounts (check for unused ones):" | tee -a $OUTPUT_FILE
az storage account list \
  --query "[].{Name:name,RG:resourceGroup,SKU:sku.name,Kind:kind,Tier:accessTier}" \
  -o table | tee -a $OUTPUT_FILE

# ── 8. Reserved Instance Opportunities ───────────────────────────────────────
echo "" | tee -a $OUTPUT_FILE
echo "💰 VMs that could benefit from Reserved Instances (running > 30 days):" | tee -a $OUTPUT_FILE
az vm list \
  --query "[].{Name:name,RG:resourceGroup,Size:hardwareProfile.vmSize,OS:storageProfile.osDisk.osType}" \
  -o table | tee -a $OUTPUT_FILE
echo "  💡 Tip: 1-year RI = ~40% savings, 3-year RI = ~60-72% savings" | tee -a $OUTPUT_FILE

# ── 9. Azure Advisor Recommendations ─────────────────────────────────────────
echo "" | tee -a $OUTPUT_FILE
echo "🎯 Azure Advisor Cost Recommendations:" | tee -a $OUTPUT_FILE
az advisor recommendation list \
  --category Cost \
  --query "[].{Impact:impact,Resource:resourceMetadata.resourceId,Recommendation:shortDescription.solution}" \
  -o table 2>/dev/null | head -20 | tee -a $OUTPUT_FILE

# ── 10. Summary ───────────────────────────────────────────────────────────────
echo "" | tee -a $OUTPUT_FILE
echo "================================================" | tee -a $OUTPUT_FILE
echo "📊 Summary" | tee -a $OUTPUT_FILE
echo "  Report saved to: $OUTPUT_FILE" | tee -a $OUTPUT_FILE
echo "" | tee -a $OUTPUT_FILE
echo "🔧 Quick wins:" | tee -a $OUTPUT_FILE
echo "  1. Deallocate stopped VMs" | tee -a $OUTPUT_FILE
echo "  2. Delete orphaned disks" | tee -a $OUTPUT_FILE
echo "  3. Release unused public IPs" | tee -a $OUTPUT_FILE
echo "  4. Delete empty resource groups" | tee -a $OUTPUT_FILE
echo "  5. Delete old snapshots" | tee -a $OUTPUT_FILE
echo "  6. Delete empty App Service Plans" | tee -a $OUTPUT_FILE
echo "  7. Purchase Reserved Instances for always-on VMs" | tee -a $OUTPUT_FILE
echo "  8. Enable storage lifecycle policies" | tee -a $OUTPUT_FILE

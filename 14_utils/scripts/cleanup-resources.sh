#!/bin/bash
# Azure Resource Cleanup Script
# Safely removes resources with confirmation prompts

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Options ───────────────────────────────────────────────────────────────────
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"
ENVIRONMENT="${ENVIRONMENT:-}"
OLDER_THAN_DAYS="${OLDER_THAN_DAYS:-}"

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --resource-group RG    Delete specific resource group"
  echo "  --environment ENV      Delete all RGs for environment (dev/staging)"
  echo "  --older-than DAYS      Delete RGs older than N days"
  echo "  --dry-run              Show what would be deleted without deleting"
  echo "  --force                Skip confirmation prompts"
  echo ""
  echo "Examples:"
  echo "  $0 --resource-group rg-myapp-dev-eastus"
  echo "  $0 --environment dev --dry-run"
  echo "  $0 --older-than 7 --environment dev"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --resource-group) TARGET_RG="$2"; shift 2 ;;
    --environment)    ENVIRONMENT="$2"; shift 2 ;;
    --older-than)     OLDER_THAN_DAYS="$2"; shift 2 ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --force)          FORCE=true; shift ;;
    --help)           usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 1 ;;
  esac
done

[[ "$DRY_RUN" == "true" ]] && warn "DRY RUN MODE — no resources will be deleted"

# ── Delete specific resource group ───────────────────────────────────────────
delete_rg() {
  local RG="$1"

  # Check if exists
  if ! az group show --name "$RG" &>/dev/null; then
    warn "Resource group '$RG' not found"
    return
  fi

  # Get resource count
  RESOURCE_COUNT=$(az resource list --resource-group "$RG" --query "length(@)" --output tsv)
  log "Resource group: $RG ($RESOURCE_COUNT resources)"

  # List resources
  az resource list --resource-group "$RG" \
    --query "[].{Type:type,Name:name}" \
    --output table

  if [[ "$FORCE" != "true" ]]; then
    read -p "Delete resource group '$RG' and all $RESOURCE_COUNT resources? (yes/no): " CONFIRM
    [[ "$CONFIRM" != "yes" ]] && { log "Skipped: $RG"; return; }
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY RUN] Would delete: $RG"
  else
    log "Deleting resource group: $RG"
    az group delete --name "$RG" --yes --no-wait
    log "Deletion initiated for: $RG (running in background)"
  fi
}

# ── Delete by environment ─────────────────────────────────────────────────────
if [[ -n "${ENVIRONMENT:-}" ]]; then
  # Safety check — never delete prod without explicit flag
  if [[ "$ENVIRONMENT" == "prod" ]] && [[ "$FORCE" != "true" ]]; then
    err "Cannot delete production environment without --force flag"
    exit 1
  fi

  log "Finding resource groups for environment: $ENVIRONMENT"
  RGS=$(az group list \
    --query "[?tags.Environment=='$ENVIRONMENT'].name" \
    --output tsv)

  if [[ -z "$RGS" ]]; then
    log "No resource groups found for environment: $ENVIRONMENT"
    exit 0
  fi

  # Filter by age if specified
  if [[ -n "${OLDER_THAN_DAYS:-}" ]]; then
    CUTOFF=$(date -d "$OLDER_THAN_DAYS days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
             date -v-${OLDER_THAN_DAYS}d +%Y-%m-%dT%H:%M:%SZ)
    log "Filtering RGs older than $OLDER_THAN_DAYS days (before $CUTOFF)"
    FILTERED_RGS=""
    while IFS= read -r RG; do
      CREATED=$(az group show --name "$RG" --query "properties.provisioningState" --output tsv 2>/dev/null || echo "")
      # Note: RG creation time not directly available, use tags
      DEPLOY_DATE=$(az group show --name "$RG" --query "tags.DeployedAt" --output tsv 2>/dev/null || echo "")
      if [[ -n "$DEPLOY_DATE" ]] && [[ "$DEPLOY_DATE" < "$CUTOFF" ]]; then
        FILTERED_RGS="$FILTERED_RGS $RG"
      fi
    done <<< "$RGS"
    RGS="$FILTERED_RGS"
  fi

  echo ""
  log "Resource groups to delete:"
  echo "$RGS" | tr ' ' '\n' | grep -v '^$' | while read -r RG; do
    echo "  - $RG"
  done
  echo ""

  echo "$RGS" | tr ' ' '\n' | grep -v '^$' | while read -r RG; do
    delete_rg "$RG"
  done

elif [[ -n "${TARGET_RG:-}" ]]; then
  delete_rg "$TARGET_RG"
else
  usage
  exit 1
fi

# ── Cleanup orphaned resources ────────────────────────────────────────────────
if [[ "${CLEANUP_ORPHANS:-false}" == "true" ]]; then
  log "Cleaning up orphaned resources..."

  # Orphaned disks
  ORPHAN_DISKS=$(az disk list --query "[?managedBy==null].id" --output tsv)
  if [[ -n "$ORPHAN_DISKS" ]]; then
    warn "Found orphaned disks:"
    az disk list --query "[?managedBy==null].{Name:name,RG:resourceGroup,Size:diskSizeGb}" --output table
    if [[ "$DRY_RUN" != "true" ]] && [[ "$FORCE" == "true" ]]; then
      echo "$ORPHAN_DISKS" | xargs -I {} az disk delete --ids {} --yes --no-wait
      log "Orphaned disk deletion initiated"
    fi
  fi

  # Unused public IPs
  UNUSED_IPS=$(az network public-ip list --query "[?ipConfiguration==null].id" --output tsv)
  if [[ -n "$UNUSED_IPS" ]]; then
    warn "Found unused public IPs:"
    az network public-ip list --query "[?ipConfiguration==null].{Name:name,RG:resourceGroup}" --output table
    if [[ "$DRY_RUN" != "true" ]] && [[ "$FORCE" == "true" ]]; then
      echo "$UNUSED_IPS" | xargs -I {} az network public-ip delete --ids {} --no-wait
      log "Unused IP deletion initiated"
    fi
  fi
fi

log "Cleanup script complete"

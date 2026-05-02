# Azure Disaster Recovery — Strategies, RTO/RPO & Implementation

## DR Fundamentals

```
RPO (Recovery Point Objective): Maximum acceptable data loss
  → How much data can we afford to lose?
  → Drives: backup frequency, replication lag

RTO (Recovery Time Objective): Maximum acceptable downtime
  → How long can we be down?
  → Drives: DR strategy, automation level

Availability = (MTBF) / (MTBF + MTTR)
  MTBF = Mean Time Between Failures
  MTTR = Mean Time To Recovery
```

### DR Strategy Comparison

| Strategy | RPO | RTO | Cost | Complexity |
|----------|-----|-----|------|-----------|
| Backup & Restore | Hours | Hours | $ | Low |
| Pilot Light | Minutes | 30-60 min | $$ | Medium |
| Warm Standby | Seconds | 5-15 min | $$$ | High |
| Active-Active | ~0 | ~0 | $$$$ | Very High |

---

## Azure Site Recovery (ASR)

ASR replicates VMs to a secondary region for disaster recovery.

```
Primary Region (eastus)          Secondary Region (westus2)
├── VM (running)          →      ├── VM (replicated, stopped)
├── Managed Disks         →      ├── Managed Disks (replica)
└── VNet                  →      └── VNet (pre-created)

On failover:
  1. ASR starts VMs in secondary region
  2. Traffic switches (DNS/Traffic Manager update)
  3. RTO: typically 15-30 minutes
```

```bash
# Create Recovery Services Vault
az backup vault create \
  --name rsv-dr-prod \
  --resource-group $RG \
  --location $LOCATION

# Enable replication for VM
az site-recovery replication-protected-item create \
  --resource-group $RG \
  --vault-name rsv-dr-prod \
  --fabric-name "asr-fabric-eastus" \
  --protection-container-name "asr-container-eastus" \
  --name "vm-web-prod-replication" \
  --policy-name "24-hour-retention-policy" \
  --recoverable-vm-id $VM_ID \
  --target-resource-group-id $TARGET_RG_ID \
  --target-virtual-machine-name "vm-web-prod-dr" \
  --target-network-id $TARGET_VNET_ID

# Test failover (non-disruptive)
az site-recovery replication-protected-item planned-failover \
  --resource-group $RG \
  --vault-name rsv-dr-prod \
  --fabric-name "asr-fabric-eastus" \
  --protection-container-name "asr-container-eastus" \
  --name "vm-web-prod-replication" \
  --failover-direction PrimaryToRecovery

# Actual failover (during disaster)
az site-recovery replication-protected-item unplanned-failover \
  --resource-group $RG \
  --vault-name rsv-dr-prod \
  --fabric-name "asr-fabric-eastus" \
  --protection-container-name "asr-container-eastus" \
  --name "vm-web-prod-replication" \
  --failover-direction PrimaryToRecovery \
  --source-site-operations-status NotRequired
```

---

## Azure SQL — Business Continuity

### Active Geo-Replication

```bash
# Create geo-replica in secondary region
az sql db replica create \
  --name myapp-db \
  --resource-group $RG \
  --server sql-prod-eastus \
  --partner-resource-group $RG_DR \
  --partner-server sql-dr-westus2 \
  --secondary-type Geo

# Manual failover (planned)
az sql db replica set-primary \
  --name myapp-db \
  --resource-group $RG_DR \
  --server sql-dr-westus2

# Check replication lag
az sql db show \
  --name myapp-db \
  --resource-group $RG_DR \
  --server sql-dr-westus2 \
  --query "replicationLinks[0].replicationLag"
```

### Auto-Failover Groups (Recommended)

```bash
# Create failover group (automatic failover)
az sql failover-group create \
  --name fg-myapp-prod \
  --resource-group $RG \
  --server sql-prod-eastus \
  --partner-server sql-dr-westus2 \
  --partner-resource-group $RG_DR \
  --failover-policy Automatic \
  --grace-period 1 \
  --add-db myapp-db

# Connection strings use failover group endpoint:
# Primary:   fg-myapp-prod.database.windows.net (read-write)
# Secondary: fg-myapp-prod.secondary.database.windows.net (read-only)

# Manual failover (for planned maintenance)
az sql failover-group set-primary \
  --name fg-myapp-prod \
  --resource-group $RG_DR \
  --server sql-dr-westus2
```

---

## Multi-Region Active-Active Architecture

```
Azure Traffic Manager (performance routing)
├── Primary: East US
│   ├── App Service (auto-scale)
│   ├── Azure SQL (primary, read-write)
│   └── Redis Cache (primary)
└── Secondary: West Europe
    ├── App Service (auto-scale)
    ├── Azure SQL (geo-replica, read-write after failover)
    └── Redis Cache (geo-replica)

Data sync:
  SQL: Active geo-replication (async, ~1s lag)
  Blob: GRS/GZRS (async replication)
  Redis: Geo-replication (Premium tier)
```

```bash
# Traffic Manager profile
az network traffic-manager profile create \
  --name tm-myapp-prod \
  --resource-group $RG \
  --routing-method Performance \
  --unique-dns-name myapp-prod \
  --ttl 30 \
  --protocol HTTPS \
  --port 443 \
  --path /health

# Add endpoints
az network traffic-manager endpoint create \
  --name endpoint-eastus \
  --profile-name tm-myapp-prod \
  --resource-group $RG \
  --type azureEndpoints \
  --target-resource-id $APP_SERVICE_EASTUS_ID \
  --endpoint-status Enabled \
  --priority 1

az network traffic-manager endpoint create \
  --name endpoint-westeurope \
  --profile-name tm-myapp-prod \
  --resource-group $RG \
  --type azureEndpoints \
  --target-resource-id $APP_SERVICE_WESTEUROPE_ID \
  --endpoint-status Enabled \
  --priority 2
```

---

## Azure Backup

```bash
# Create Recovery Services Vault
az backup vault create \
  --name rsv-backup-prod \
  --resource-group $RG \
  --location $LOCATION

# Set storage redundancy (GRS for cross-region restore)
az backup vault backup-properties set \
  --name rsv-backup-prod \
  --resource-group $RG \
  --backup-storage-redundancy GeoRedundant \
  --cross-region-restore-flag true

# Enable VM backup
az backup protection enable-for-vm \
  --resource-group $RG \
  --vault-name rsv-backup-prod \
  --vm $VM_NAME \
  --policy-name DefaultPolicy

# Create custom backup policy (daily, 30-day retention)
az backup policy create \
  --resource-group $RG \
  --vault-name rsv-backup-prod \
  --name "DailyPolicy30Days" \
  --policy '{
    "schedulePolicy": {
      "schedulePolicyType": "SimpleSchedulePolicy",
      "scheduleRunFrequency": "Daily",
      "scheduleRunTimes": ["2024-01-01T02:00:00Z"]
    },
    "retentionPolicy": {
      "retentionPolicyType": "LongTermRetentionPolicy",
      "dailySchedule": {
        "retentionTimes": ["2024-01-01T02:00:00Z"],
        "retentionDuration": {"count": 30, "durationType": "Days"}
      },
      "weeklySchedule": {
        "daysOfTheWeek": ["Sunday"],
        "retentionTimes": ["2024-01-01T02:00:00Z"],
        "retentionDuration": {"count": 12, "durationType": "Weeks"}
      },
      "monthlySchedule": {
        "retentionScheduleFormatType": "Weekly",
        "retentionScheduleWeekly": {
          "daysOfTheWeek": ["Sunday"],
          "weeksOfTheMonth": ["First"]
        },
        "retentionTimes": ["2024-01-01T02:00:00Z"],
        "retentionDuration": {"count": 12, "durationType": "Months"}
      }
    },
    "backupManagementType": "AzureIaasVM",
    "workLoadType": "VM"
  }'

# Restore VM from backup
az backup restore restore-disks \
  --resource-group $RG \
  --vault-name rsv-backup-prod \
  --container-name $VM_NAME \
  --item-name $VM_NAME \
  --rp-name $RECOVERY_POINT \
  --storage-account $RESTORE_STORAGE_ACCOUNT \
  --target-resource-group $TARGET_RG
```

---

## DR Runbook Template

```markdown
# DR Runbook — [Application Name]

## Trigger Conditions
- Primary region unavailable > 15 minutes
- Azure Service Health alert for region outage
- Application health check failing in primary

## RTO Target: 30 minutes
## RPO Target: 5 minutes

## Step 1: Declare Incident (5 min)
- [ ] Notify on-call team via PagerDuty
- [ ] Create incident channel in Teams
- [ ] Confirm primary region outage via Azure Status page

## Step 2: Initiate Failover (10 min)
- [ ] Trigger SQL failover group: `az sql failover-group set-primary ...`
- [ ] Verify secondary SQL is accepting writes
- [ ] Update Traffic Manager to route to secondary: `az network traffic-manager endpoint update --endpoint-status Enabled`
- [ ] Disable primary endpoint: `az network traffic-manager endpoint update --endpoint-status Disabled`

## Step 3: Verify (10 min)
- [ ] Test application URL in secondary region
- [ ] Verify database connectivity
- [ ] Check Application Insights for errors
- [ ] Confirm monitoring alerts are firing correctly

## Step 4: Communicate (5 min)
- [ ] Update status page
- [ ] Notify stakeholders
- [ ] Document timeline

## Failback Procedure (after primary recovery)
1. Verify primary region is stable
2. Re-sync data from secondary to primary
3. Test primary environment
4. Switch Traffic Manager back to primary
5. Monitor for 30 minutes
6. Close incident
```

---

## Interview Q&A

### Q1: What is the difference between RPO and RTO?
**RPO (Recovery Point Objective)**: Maximum acceptable data loss measured in time. "How much data can we afford to lose?" RPO=1hr means you can lose up to 1 hour of data. Drives backup frequency and replication strategy.
**RTO (Recovery Time Objective)**: Maximum acceptable downtime. "How long can we be down?" RTO=30min means you must be back online within 30 minutes. Drives DR strategy choice (backup/restore vs active-active).

### Q2: What is the difference between Azure Backup and Azure Site Recovery?
**Azure Backup**: Protects against data loss. Creates point-in-time snapshots/backups of VMs, SQL, files. Restore individual files or entire VMs. RPO: hours (backup frequency). RTO: hours (restore time).
**Azure Site Recovery**: Protects against region/datacenter failure. Continuously replicates VMs to secondary region. Failover in minutes. RPO: minutes (replication lag). RTO: 15-30 minutes. Use Backup for data protection, ASR for business continuity.

### Q3: How do SQL Failover Groups work?
Failover Groups provide a single connection endpoint that automatically redirects to the current primary. The primary endpoint (`fg-name.database.windows.net`) always points to the read-write primary. On failover (automatic or manual), the secondary becomes primary and the endpoint updates automatically — no connection string changes needed. Automatic failover triggers after the grace period (default 1 hour) if primary is unreachable.

### Q4: How do you design for zero RPO?
Zero RPO requires synchronous replication — every write is confirmed on both primary and secondary before acknowledging to the client. Azure options: (1) Azure SQL Business Critical tier — synchronous replication within a region (3 replicas), (2) Cosmos DB multi-region writes — synchronous writes to multiple regions, (3) Storage ZRS — synchronous replication across 3 AZs. Trade-off: synchronous replication adds latency (especially cross-region). True zero RPO cross-region is impractical due to speed of light constraints.

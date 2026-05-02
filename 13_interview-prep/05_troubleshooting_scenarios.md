# Troubleshooting Scenarios — Azure Interview Questions

## Compute Troubleshooting

### T1: VM is unreachable via SSH/RDP. Walk through your troubleshooting steps.

```bash
# Step 1: Check VM status
az vm get-instance-view \
  --resource-group $RG \
  --name $VM_NAME \
  --query "instanceView.statuses[*].displayStatus"

# Step 2: Check effective NSG rules
az network nic list-effective-nsg \
  --resource-group $RG \
  --name $NIC_NAME \
  --output table

# Step 3: Check effective routes
az network nic show-effective-route-table \
  --resource-group $RG \
  --name $NIC_NAME \
  --output table

# Step 4: Use Network Watcher IP flow verify
az network watcher test-ip-flow \
  --resource-group $RG \
  --vm $VM_NAME \
  --direction Inbound \
  --protocol TCP \
  --local 10.0.1.4:22 \
  --remote 203.0.113.0:12345

# Step 5: Check boot diagnostics
az vm boot-diagnostics get-boot-log \
  --resource-group $RG \
  --name $VM_NAME

# Step 6: Run command on VM (if agent running)
az vm run-command invoke \
  --resource-group $RG \
  --name $VM_NAME \
  --command-id RunShellScript \
  --scripts "systemctl status sshd && ss -tlnp | grep 22"
```

**Common causes and fixes:**
| Cause | Fix |
|-------|-----|
| NSG blocking port 22/3389 | Add inbound rule or use Azure Bastion |
| VM deallocated | Start VM |
| OS firewall blocking | Use Run Command to disable temporarily |
| SSH service not running | Use Run Command to start sshd |
| Wrong private key | Reset SSH key via portal |
| VM in bad state | Redeploy VM to different host |

---

### T2: App Service returns 502/503 errors intermittently.

```bash
# Check App Service metrics
az monitor metrics list \
  --resource $WEBAPP_ID \
  --metric "Http5xx" "ResponseTime" "Requests" \
  --interval PT1M \
  --output table

# Stream live logs
az webapp log tail \
  --name $APP_NAME \
  --resource-group $RG

# Check recent deployments
az webapp deployment list \
  --name $APP_NAME \
  --resource-group $RG \
  --output table

# Check auto-scale events
az monitor activity-log list \
  --resource-group $RG \
  --resource-id $PLAN_ID \
  --start-time $(date -d "1 hour ago" +%Y-%m-%dT%H:%M:%SZ) \
  --output table
```

**KQL query for App Insights:**
```kusto
requests
| where timestamp > ago(1h)
| where resultCode startswith "5"
| summarize count() by resultCode, name, bin(timestamp, 5m)
| render timechart

exceptions
| where timestamp > ago(1h)
| summarize count() by type, outerMessage
| order by count_ desc
```

**Common causes:**
- Memory leak → increase plan or fix leak
- Database connection pool exhausted → increase pool size
- Dependency timeout → add circuit breaker, increase timeout
- Cold start on scale-out → use Always On, pre-warmed instances
- Recent bad deployment → swap back to previous slot

---

### T3: Azure Function is not triggering from Service Bus.

```bash
# Check function app status
az functionapp show \
  --name $FUNC_APP \
  --resource-group $RG \
  --query "state"

# Check app settings
az functionapp config appsettings list \
  --name $FUNC_APP \
  --resource-group $RG \
  --query "[?name=='ServiceBusConnection']"

# Check Service Bus queue
az servicebus queue show \
  --name $QUEUE_NAME \
  --namespace-name $SB_NAMESPACE \
  --resource-group $RG \
  --query "{messageCount:countDetails.activeMessageCount,deadLetter:countDetails.deadLetterMessageCount}"

# Check dead-letter queue
az servicebus queue show \
  --name "${QUEUE_NAME}/$DeadLetterQueue" \
  --namespace-name $SB_NAMESPACE \
  --resource-group $RG
```

**Checklist:**
- [ ] Connection string correct and has `Listen` permission
- [ ] Queue name matches exactly (case-sensitive)
- [ ] Function app is running (not stopped)
- [ ] No exceptions in Application Insights
- [ ] Messages not in dead-letter queue
- [ ] Managed Identity has Service Bus Data Receiver role
- [ ] Function host.json `maxConcurrentCalls` not set too low

---

## Networking Troubleshooting

### T4: Two VMs in different VNets cannot communicate.

```bash
# Check VNet peering status
az network vnet peering list \
  --resource-group $RG \
  --vnet-name $VNET1 \
  --output table

# Verify both sides of peering exist
az network vnet peering show \
  --name peer-vnet1-to-vnet2 \
  --resource-group $RG \
  --vnet-name $VNET1 \
  --query "peeringState"

# Check effective routes on VM NIC
az network nic show-effective-route-table \
  --resource-group $RG \
  --name $NIC_NAME \
  --output table

# Test connectivity with Network Watcher
az network watcher test-connectivity \
  --source-resource $VM1_ID \
  --dest-address $VM2_PRIVATE_IP \
  --dest-port 80 \
  --protocol TCP
```

**Common causes:**
| Cause | Fix |
|-------|-----|
| Peering only one-way | Create peering on both VNets |
| Address spaces overlap | Cannot peer — redesign IP scheme |
| NSG blocking traffic | Add allow rule for source VNet CIDR |
| UDR routing to NVA | Check NVA is forwarding traffic |
| `allowVirtualNetworkAccess` false | Update peering to allow VNet access |

---

### T5: Private Endpoint not resolving to private IP.

```bash
# Check private endpoint status
az network private-endpoint show \
  --name $PE_NAME \
  --resource-group $RG \
  --query "provisioningState"

# Check private DNS zone
az network private-dns zone show \
  --name "privatelink.blob.core.windows.net" \
  --resource-group $RG

# Check DNS zone link to VNet
az network private-dns link vnet list \
  --resource-group $RG \
  --zone-name "privatelink.blob.core.windows.net" \
  --output table

# Check DNS record
az network private-dns record-set a list \
  --resource-group $RG \
  --zone-name "privatelink.blob.core.windows.net" \
  --output table

# Test DNS resolution from VM
az vm run-command invoke \
  --resource-group $RG \
  --name $VM_NAME \
  --command-id RunShellScript \
  --scripts "nslookup mystorageaccount.blob.core.windows.net"
```

**Checklist:**
- [ ] Private DNS zone created with correct name
- [ ] DNS zone linked to VNet (registration not required)
- [ ] A record exists pointing to private endpoint IP
- [ ] DNS zone group created on private endpoint
- [ ] Custom DNS server forwards to Azure DNS (168.63.129.16)

---

## Database Troubleshooting

### T6: Azure SQL Database queries are slow.

```sql
-- Find top slow queries
SELECT TOP 10
    qs.total_elapsed_time / qs.execution_count AS avg_elapsed_time,
    qs.execution_count,
    SUBSTRING(qt.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(qt.text)
          ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1) AS query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY avg_elapsed_time DESC;

-- Check missing indexes
SELECT
    migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans) AS improvement_measure,
    mid.statement AS table_name,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns
FROM sys.dm_db_missing_index_groups mig
JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
ORDER BY improvement_measure DESC;

-- Check blocking
SELECT
    blocking_session_id,
    session_id,
    wait_type,
    wait_time,
    last_wait_type,
    status
FROM sys.dm_exec_requests
WHERE blocking_session_id > 0;
```

```bash
# Check DTU/vCore utilization
az monitor metrics list \
  --resource $SQL_DB_ID \
  --metric "dtu_consumption_percent" "cpu_percent" "physical_data_read_percent" \
  --interval PT1M \
  --output table

# Check Query Performance Insight (portal)
# Azure portal → SQL Database → Query Performance Insight
```

---

## AKS Troubleshooting

### T7: AKS pods are in CrashLoopBackOff.

```bash
# Get pod details
kubectl describe pod $POD_NAME -n $NAMESPACE

# Get logs (current and previous)
kubectl logs $POD_NAME -n $NAMESPACE
kubectl logs $POD_NAME -n $NAMESPACE --previous

# Get events
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -20

# Check resource usage
kubectl top pods -n $NAMESPACE
kubectl top nodes

# Exec into pod (if it starts briefly)
kubectl exec -it $POD_NAME -n $NAMESPACE -- /bin/sh

# Check node conditions
kubectl describe node $NODE_NAME | grep -A 10 Conditions

# Check if image can be pulled
kubectl describe pod $POD_NAME -n $NAMESPACE | grep -A 5 "Events:"
```

**Common causes and fixes:**
| Error | Cause | Fix |
|-------|-------|-----|
| `OOMKilled` | Memory limit too low | Increase memory limit |
| `ImagePullBackOff` | Can't pull image | Check ACR credentials, image tag |
| `CrashLoopBackOff` | App crashes on start | Check logs, env vars, secrets |
| `Pending` | No nodes available | Check node resources, taints |
| `CreateContainerConfigError` | Missing secret/configmap | Create missing resources |
| `RunContainerError` | Container can't start | Check security context, volumes |

---

## Cost Troubleshooting

### T8: Unexpected spike in Azure costs. Investigation approach.

```bash
# 1. Check cost by service (last 7 days)
az consumption usage list \
  --start-date $(date -d "7 days ago" +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --query "sort_by([].{Service:instanceName,Cost:pretaxCost,Date:usageStart}, &Cost) | reverse(@)" \
  --output table | head -20

# 2. Check for new resources
az monitor activity-log list \
  --start-time $(date -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ) \
  --filter "eventName eq 'Write'" \
  --query "[?status.value=='Succeeded'].{Time:eventTimestamp,Caller:caller,Operation:operationName.value,Resource:resourceId}" \
  --output table | head -30

# 3. Check data transfer costs
az monitor metrics list \
  --resource $STORAGE_ID \
  --metric "Egress" \
  --interval P1D \
  --output table

# 4. Check auto-scale events
az monitor activity-log list \
  --start-time $(date -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ) \
  --filter "resourceProvider eq 'Microsoft.Insights' and operationName eq 'microsoft.insights/autoscalesettings/scaleaction/action'" \
  --output table
```

**Investigation checklist:**
- [ ] New resources deployed (check activity log)
- [ ] Auto-scaling triggered unexpectedly
- [ ] Data transfer costs (cross-region, egress to internet)
- [ ] Reserved Instances expired
- [ ] Storage tier not optimized
- [ ] Dev/test resources left running over weekend
- [ ] Backup retention increased
- [ ] Log Analytics ingestion spike

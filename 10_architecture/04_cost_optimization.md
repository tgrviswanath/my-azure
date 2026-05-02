# Architecture for Cost Optimization

## FinOps Framework on Azure

```
FinOps = Financial Operations — cloud cost management discipline

Three Phases:
  Inform:    Visibility into spending (tagging, dashboards, reports)
  Optimize:  Reduce waste (right-sizing, reserved instances, lifecycle)
  Operate:   Continuous improvement (budgets, policies, culture)

Azure FinOps Tools:
  Azure Cost Management + Billing
  Azure Advisor (cost recommendations)
  Azure Policy (enforce tagging, restrict SKUs)
  Azure Budgets (alerts and actions)
  Microsoft Cost Management Power BI app
```

## Tagging Strategy

```bash
# Mandatory tags (enforced via Azure Policy)
REQUIRED_TAGS=(
  "Environment:dev|staging|prod"
  "Application:app-name"
  "Team:team-name"
  "CostCenter:cost-center-code"
  "Owner:owner-email"
)

# Apply tags to all resources in a group
az resource list --resource-group $RG --query "[].id" -o tsv | \
  xargs -I {} az resource tag --ids {} --tags \
    Environment=prod \
    Application=myapp \
    Team=platform \
    CostCenter=ENG-001 \
    Owner=platform@company.com

# Azure Policy: deny resources without required tags
az policy definition create \
  --name "require-tags" \
  --display-name "Require mandatory tags" \
  --rules '{
    "if": {
      "anyOf": [
        {"field": "tags[Environment]", "exists": "false"},
        {"field": "tags[Application]", "exists": "false"},
        {"field": "tags[CostCenter]", "exists": "false"}
      ]
    },
    "then": {"effect": "deny"}
  }' \
  --mode All
```

## Right-Sizing Automation

```bash
# Get Azure Advisor cost recommendations
az advisor recommendation list \
  --category Cost \
  --query "[?impactedField=='Microsoft.Compute/virtualMachines'].{
    VM:impactedValue,
    Impact:impact,
    Recommendation:shortDescription.solution,
    Savings:extendedProperties.annualSavingsAmount
  }" \
  --output table

# Find underutilized VMs (CPU < 5% for 7 days)
# Use Azure Monitor metrics
az monitor metrics list \
  --resource $VM_ID \
  --metric "Percentage CPU" \
  --interval P1D \
  --start-time $(date -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date +%Y-%m-%dT%H:%M:%SZ) \
  --aggregation Average \
  --query "value[0].timeseries[0].data[*].average" \
  --output tsv | awk '{sum+=$1; count++} END {print "Avg CPU:", sum/count "%"}'
```

## Auto-Scaling Patterns

```yaml
# KEDA — Kubernetes Event-Driven Autoscaling
# Scale to zero when no messages in queue
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: order-processor-scaler
  namespace: production
spec:
  scaleTargetRef:
    name: order-processor
  minReplicaCount: 0    # scale to zero!
  maxReplicaCount: 50
  cooldownPeriod: 300
  triggers:
  - type: azure-servicebus
    metadata:
      queueName: orders-queue
      namespace: sbns-myapp-prod
      messageCount: "5"   # 1 replica per 5 messages
    authenticationRef:
      name: servicebus-auth
```

```bash
# App Service scheduled scaling (off-hours)
# Scale down at 7 PM, scale up at 8 AM
az monitor autoscale profile create \
  --resource-group $RG \
  --autoscale-name autoscale-webapp \
  --name "BusinessHours" \
  --min-count 2 --max-count 10 --count 2 \
  --recurrence week mon tue wed thu fri \
  --timezone "Eastern Standard Time" \
  --start 08:00 --end 19:00

az monitor autoscale profile create \
  --resource-group $RG \
  --autoscale-name autoscale-webapp \
  --name "OffHours" \
  --min-count 1 --max-count 2 --count 1 \
  --recurrence week mon tue wed thu fri \
  --timezone "Eastern Standard Time" \
  --start 19:00 --end 08:00

az monitor autoscale profile create \
  --resource-group $RG \
  --autoscale-name autoscale-webapp \
  --name "Weekend" \
  --min-count 1 --max-count 2 --count 1 \
  --recurrence week sat sun \
  --timezone "Eastern Standard Time" \
  --start 00:00 --end 23:59
```

## Storage Cost Optimization

```bash
# Lifecycle policy: auto-tier and delete
cat > lifecycle.json << 'EOF'
{
  "rules": [
    {
      "name": "auto-tier-logs",
      "enabled": true,
      "type": "Lifecycle",
      "definition": {
        "filters": {"blobTypes": ["blockBlob"], "prefixMatch": ["logs/"]},
        "actions": {
          "baseBlob": {
            "tierToCool":    {"daysAfterModificationGreaterThan": 30},
            "tierToArchive": {"daysAfterModificationGreaterThan": 90},
            "delete":        {"daysAfterModificationGreaterThan": 365}
          },
          "snapshot": {"delete": {"daysAfterCreationGreaterThan": 90}},
          "version":  {"delete": {"daysAfterCreationGreaterThan": 90}}
        }
      }
    },
    {
      "name": "delete-temp",
      "enabled": true,
      "type": "Lifecycle",
      "definition": {
        "filters": {"blobTypes": ["blockBlob"], "prefixMatch": ["temp/"]},
        "actions": {
          "baseBlob": {"delete": {"daysAfterModificationGreaterThan": 7}}
        }
      }
    }
  ]
}
EOF

az storage account management-policy create \
  --account-name $STORAGE_NAME \
  --resource-group $RG \
  --policy @lifecycle.json
```

## Reserved Instance Strategy

```
When to buy Reserved Instances:
  ✅ VM running > 8 hours/day consistently
  ✅ Workload predictable for 1+ years
  ✅ Same VM size for extended period
  ✅ Production databases (SQL, Redis)

When NOT to buy:
  ❌ Dev/test environments (use auto-shutdown instead)
  ❌ Workloads that change size frequently
  ❌ Short-term projects (< 6 months)
  ❌ Highly variable traffic (use auto-scaling)

RI Exchange and Cancellation:
  - Can exchange for different size/region (once per year)
  - Can cancel with 12% early termination fee
  - Scope: single subscription or shared (across subscriptions)
```

```bash
# View RI recommendations
az reservations reservation-order list \
  --output table

# Check RI utilization
az consumption reservation-detail list \
  --reservation-order-id $ORDER_ID \
  --start-date 2024-01-01 \
  --end-date 2024-01-31 \
  --output table
```

## Cost Anomaly Detection

```bash
# Enable cost anomaly alerts
az costmanagement alert create \
  --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --name "cost-anomaly-alert" \
  --type Budget \
  --amount 1000 \
  --time-grain Monthly \
  --start-date 2024-01-01 \
  --end-date 2024-12-31 \
  --notification-enabled true \
  --notification-threshold 90 \
  --notification-contact-emails "finops@company.com"

# KQL: detect cost spikes
# In Azure Cost Management → Cost Analysis → Anomaly Detection
```

## Interview Questions

### Q1: How do you implement a FinOps practice in Azure?
**Answer:**
1. **Visibility**: Enable cost allocation tags, create dashboards in Cost Management, set up chargeback/showback reports
2. **Accountability**: Separate subscriptions per team, monthly cost reviews, budget alerts per team
3. **Optimization**: Azure Advisor recommendations, Reserved Instances for stable workloads, lifecycle policies for storage, auto-scaling
4. **Governance**: Azure Policy to enforce tagging, restrict expensive SKUs in dev, require approval for large resources
5. **Culture**: Share cost dashboards with engineering teams, celebrate cost savings

### Q2: A production workload costs $10,000/month. How do you reduce it by 30%?
**Answer:**
1. **Reserved Instances** (biggest impact): Convert PAYG VMs and SQL to 1-year RI → ~40% savings on compute
2. **Azure Hybrid Benefit**: Apply existing Windows/SQL licenses → additional 40-55% on those resources
3. **Right-sizing**: Use Azure Advisor to identify over-provisioned VMs → downsize
4. **Storage lifecycle**: Move old data to Cool/Archive tiers → 50-90% storage savings
5. **Auto-scaling**: Scale down during off-hours → 30-50% compute savings
6. **Delete waste**: Orphaned disks, unused IPs, empty resource groups

### Q3: What is the difference between Azure Budgets and Azure Cost Alerts?
**Answer:**
- **Azure Budgets**: Set spending limits with notifications at thresholds (50%, 80%, 100%). Can trigger action groups (email, webhook, Logic App). Can also trigger automated responses (stop VMs, send Teams message).
- **Cost Anomaly Alerts**: AI-powered detection of unusual spending patterns. Automatically detects spikes without manual threshold setting.
- Use both: Budgets for known limits, Anomaly Alerts for unexpected spikes.

# Steps — Project 8.3 Azure Policy Compliance Automation

## Phase 1 — Create Policy Definition

```bash
# Create custom policy requiring Project tag
az policy definition create \
  --name "require-project-tag" \
  --display-name "Require Project tag on resource groups" \
  --description "All resource groups must have a Project tag" \
  --rules '{"if":{"allOf":[{"field":"type","equals":"Microsoft.Resources/subscriptions/resourceGroups"},{"field":"tags[Project]","exists":"false"}]},"then":{"effect":"Audit"}}' \
  --mode All
```

---

## Phase 2 — Assign Policy to Subscription

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

az policy assignment create \
  --name "require-project-tag" \
  --display-name "Require Project tag" \
  --policy "require-project-tag" \
  --scope /subscriptions/$SUBSCRIPTION_ID
```

---

## Phase 3 — Check Compliance

```bash
# Trigger compliance scan
az policy state trigger-scan --subscription $SUBSCRIPTION_ID

# Check compliance summary
az policy state summarize --subscription $SUBSCRIPTION_ID

# List non-compliant resources
az policy state list \
  --filter "complianceState eq 'NonCompliant'" \
  --query "[].{Resource:resourceId, Policy:policyDefinitionName}" \
  --output table
```

---

## Phase 4 — Create Remediation Task

```bash
# For DeployIfNotExists policies, create remediation task
az policy remediation create \
  --name "remediate-tags" \
  --policy-assignment "require-project-tag" \
  --resource-discovery-mode ReEvaluateCompliance
```

---

## Phase 5 — View Compliance Dashboard

```
Azure Portal → Policy → Compliance
- Overall compliance percentage
- Non-compliant policies
- Non-compliant resources
- Remediation tasks
```

---

## Screenshots to Take
- [ ] Policy definition created
- [ ] Policy assigned to subscription
- [ ] Compliance dashboard showing non-compliant resources
- [ ] Remediation task running

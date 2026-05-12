# Steps — Project 10.1 Multi-subscription Azure Landing Zone

## Phase 1 — Create Management Group Hierarchy

```bash
TENANT_ID=$(az account show --query tenantId -o tsv)

# Create top-level management groups
az account management-group create --name "platform" --display-name "Platform"
az account management-group create --name "landing-zones" --display-name "Landing Zones"
az account management-group create --name "corp" --display-name "Corp" --parent "landing-zones"
az account management-group create --name "online" --display-name "Online" --parent "landing-zones"

# Move subscriptions into management groups
az account management-group subscription add \
  --name "corp" \
  --subscription <dev-subscription-id>
```

---

## Phase 2 — Assign Policy Initiatives

```bash
# Assign Azure Security Benchmark initiative at Landing Zones MG
az policy assignment create \
  --name "azure-security-benchmark" \
  --display-name "Azure Security Benchmark" \
  --policy-set-definition "1f3afdf9-d0c9-4c3d-847f-89da613e70a8" \
  --scope /providers/Microsoft.Management/managementGroups/landing-zones

# Assign allowed locations policy
az policy assignment create \
  --name "allowed-locations" \
  --policy "e56962a6-4747-49cd-b67b-bf8b01975c4c" \
  --scope /providers/Microsoft.Management/managementGroups/landing-zones \
  --params '{"listOfAllowedLocations":{"value":["eastus","westus","eastus2"]}}'
```

---

## Phase 3 — Configure RBAC at MG Level

```bash
# Assign Owner role to platform team at Platform MG
az role assignment create \
  --assignee platform-team@company.com \
  --role Owner \
  --scope /providers/Microsoft.Management/managementGroups/platform

# Assign Contributor to dev team at Corp MG
az role assignment create \
  --assignee dev-team@company.com \
  --role Contributor \
  --scope /providers/Microsoft.Management/managementGroups/corp
```

---

## Phase 4 — Enable Defender for Cloud at Scale

```bash
# Enable Defender for all subscriptions in Landing Zones MG
az security pricing create --name VirtualMachines --tier Standard
az security pricing create --name StorageAccounts --tier Standard
```

---

## Phase 5 — Set Up Cost Management

```bash
# Create budget at MG level
az consumption budget create \
  --budget-name "landing-zones-budget" \
  --amount 1000 \
  --time-grain Monthly \
  --scope /providers/Microsoft.Management/managementGroups/landing-zones \
  --notifications '[{"enabled":true,"operator":"GreaterThan","threshold":80,"contactEmails":["finance@company.com"]}]'
```

---

## Screenshots to Take
- [ ] Management Group hierarchy in Azure Portal
- [ ] Policy assignments at MG level
- [ ] RBAC assignments inherited by child subscriptions
- [ ] Cost Management budget at MG level

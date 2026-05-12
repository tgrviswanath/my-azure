# Steps — Project 0.4 Azure Cost Management & Billing

## Phase 1 — Enable Cost Management

### 1.1 Verify Cost Management access
```bash
az login
az account show
az costmanagement --help
```

### 1.2 View current month spend
```bash
az consumption usage list \
  --start-date $(date -d "$(date +%Y-%m-01)" +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --output table
```

### 1.3 View spend by service
```bash
az consumption usage list \
  --start-date 2024-01-01 \
  --end-date 2024-01-31 \
  --query "[].{Service:instanceName, Cost:pretaxCost, Currency:currency}" \
  --output table
```

---

## Phase 2 — Create Budget with Alert

### 2.1 Get your subscription ID
```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo $SUBSCRIPTION_ID
```

### 2.2 Create a budget via Azure CLI
```bash
az consumption budget create \
  --budget-name "monthly-lab-budget" \
  --amount 20 \
  --time-grain Monthly \
  --start-date "2024-01-01" \
  --end-date "2025-12-31" \
  --category Cost \
  --notification-key "alert-80" \
  --notification-enabled true \
  --notification-operator GreaterThan \
  --notification-threshold 80 \
  --contact-emails "your-email@example.com"
```

### 2.3 Deploy with Terraform (recommended)
```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### 2.4 Verify budget was created
```bash
az consumption budget list --output table
```

---

## Phase 3 — Set Up Cost Anomaly Alert

### 3.1 Create anomaly alert via Azure Portal
- Go to: Cost Management + Billing → Cost alerts → + Add
- Alert type: Anomaly
- Scope: Your subscription
- Email: your-email@example.com

### 3.2 Or via Azure CLI (preview feature)
```bash
az costmanagement alert create \
  --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --name "anomaly-alert" \
  --type "Budget"
```

---

## Phase 4 — Tag Resources

### 4.1 Tag an existing resource group
```bash
az group update \
  --name my-resource-group \
  --tags environment=dev project=azure-lab owner=myname cost-center=engineering
```

### 4.2 Tag a specific resource
```bash
az resource tag \
  --ids /subscriptions/$SUBSCRIPTION_ID/resourceGroups/my-rg/providers/Microsoft.Compute/virtualMachines/my-vm \
  --tags environment=dev project=azure-lab
```

### 4.3 List all resources with a specific tag
```bash
az resource list --tag environment=dev --output table
```

### 4.4 Enforce tagging with Azure Policy (optional)
```bash
# Assign built-in policy: "Require a tag on resources"
az policy assignment create \
  --name "require-environment-tag" \
  --policy "871b6d14-10aa-478d-b590-94f262ecfa99" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
```

---

## Phase 5 — View Cost Analysis

### 5.1 Open Cost Analysis in portal
- Azure Portal → Cost Management + Billing → Cost analysis
- Group by: Service name
- Filter by: Tag = environment:dev

### 5.2 Run billing monitor script
```bash
pip install azure-mgmt-costmanagement azure-identity
python code/billing_monitor.py
```

### 5.3 Export cost data to CSV
```bash
az consumption usage list \
  --start-date 2024-01-01 \
  --end-date 2024-01-31 \
  --output json > cost_export.json
```

---

## Screenshots to Take
- [ ] Budget created in Azure Portal with 80% alert
- [ ] Cost analysis chart grouped by service
- [ ] Tagged resources in resource list
- [ ] billing_monitor.py output showing current spend

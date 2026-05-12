# Steps — Project 6.3 Azure DevOps + Terraform Pipeline

## Phase 1 — Create State Backend

```bash
az group create --name rg-terraform-state --location eastus

az storage account create \
  --name tfstateado001 \
  --resource-group rg-terraform-state \
  --sku Standard_LRS \
  --kind StorageV2

az storage container create \
  --name tfstate \
  --account-name tfstateado001
```

---

## Phase 2 — Create Service Principal for ADO

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

az ad sp create-for-rbac \
  --name "ado-terraform-sp" \
  --role Contributor \
  --scopes /subscriptions/$SUBSCRIPTION_ID \
  --sdk-auth
# Save the JSON output — needed for ADO service connection
```

---

## Phase 3 — Configure Azure DevOps

```bash
# Install ADO CLI extension
az extension add --name azure-devops

# Set org and project
az devops configure --defaults organization=https://dev.azure.com/myorg project=my-project

# Create service connection (via portal: Project Settings → Service Connections → New → Azure Resource Manager)
```

---

## Phase 4 — Create Pipeline

```bash
# Create pipeline from YAML file
az pipelines create \
  --name "terraform-pipeline" \
  --yaml-path code/azure-pipelines.yml \
  --repository my-repo \
  --branch main
```

---

## Phase 5 — Test Pipeline

```bash
# Trigger a run manually
az pipelines run --name "terraform-pipeline"

# Watch the run
az pipelines runs list --pipeline-name "terraform-pipeline" --top 1
```

---

## Screenshots to Take
- [ ] Pipeline running on PR (plan output as comment)
- [ ] Approval gate before apply
- [ ] Terraform apply succeeded
- [ ] State file in Azure Storage

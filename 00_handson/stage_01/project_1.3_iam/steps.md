# Steps — Project 1.3 Azure AD RBAC & Identity Management

## Phase 1 — Create Azure AD Groups

### 1.1 Get your tenant ID
```bash
az account show --query tenantId -o tsv
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

### 1.2 Create security groups
```bash
# Developers group
az ad group create \
  --display-name "azure-lab-developers" \
  --mail-nickname "azure-lab-developers"

# Read-only group
az ad group create \
  --display-name "azure-lab-readers" \
  --mail-nickname "azure-lab-readers"

# List groups
az ad group list --display-name "azure-lab" --output table
```

### 1.3 Create a test user (optional — requires Azure AD admin)
```bash
az ad user create \
  --display-name "Lab Developer" \
  --user-principal-name "labdev@yourtenant.onmicrosoft.com" \
  --password "TempPass123!" \
  --force-change-password-next-sign-in true
```

### 1.4 Add user to group
```bash
USER_ID=$(az ad user show --id "labdev@yourtenant.onmicrosoft.com" --query id -o tsv)
GROUP_ID=$(az ad group show --group "azure-lab-developers" --query id -o tsv)

az ad group member add \
  --group $GROUP_ID \
  --member-id $USER_ID
```

---

## Phase 2 — Assign RBAC Roles

### 2.1 Create a resource group for the lab
```bash
az group create --name iam-lab-rg --location eastus
```

### 2.2 Assign Contributor role to developers group
```bash
DEV_GROUP_ID=$(az ad group show --group "azure-lab-developers" --query id -o tsv)

az role assignment create \
  --assignee $DEV_GROUP_ID \
  --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/iam-lab-rg"
```

### 2.3 Assign Reader role to readers group
```bash
READER_GROUP_ID=$(az ad group show --group "azure-lab-readers" --query id -o tsv)

az role assignment create \
  --assignee $READER_GROUP_ID \
  --role "Reader" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/iam-lab-rg"
```

### 2.4 List role assignments on the resource group
```bash
az role assignment list \
  --resource-group iam-lab-rg \
  --output table
```

---

## Phase 3 — Create Managed Identity

### 3.1 Create user-assigned managed identity
```bash
az identity create \
  --name lab-managed-identity \
  --resource-group iam-lab-rg \
  --location eastus
```

### 3.2 Get the identity's principal ID
```bash
IDENTITY_PRINCIPAL=$(az identity show \
  --name lab-managed-identity \
  --resource-group iam-lab-rg \
  --query principalId -o tsv)

echo "Principal ID: $IDENTITY_PRINCIPAL"
```

### 3.3 Assign Storage Blob Data Reader to the managed identity
```bash
STORAGE_ID=$(az storage account show \
  --name mystorageaccount \
  --resource-group iam-lab-rg \
  --query id -o tsv)

az role assignment create \
  --assignee $IDENTITY_PRINCIPAL \
  --role "Storage Blob Data Reader" \
  --scope $STORAGE_ID
```

---

## Phase 4 — Test Access

### 4.1 Verify role assignments
```bash
az role assignment list \
  --assignee $IDENTITY_PRINCIPAL \
  --output table
```

### 4.2 Test with the Python script
```bash
python code/rbac_setup.py
```

### 4.3 Check Azure AD audit logs
```bash
az monitor activity-log list \
  --resource-group iam-lab-rg \
  --start-time $(date -d "1 hour ago" +%Y-%m-%dT%H:%M:%SZ) \
  --output table
```

---

## Phase 5 — Enable MFA (Azure AD P1 required)

### 5.1 Enable Security Defaults (free MFA for all users)
- Azure Portal → Azure Active Directory → Properties
- Manage Security Defaults → Enable Security Defaults → Yes

### 5.2 Or configure Conditional Access (requires P1)
- Azure Portal → Azure AD → Security → Conditional Access
- New policy → Require MFA for all users

---

## Screenshots to Take
- [ ] Azure AD groups created
- [ ] Role assignments on resource group
- [ ] Managed identity created with principal ID
- [ ] rbac_setup.py output showing role assignments

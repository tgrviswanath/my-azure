# Azure Security — AAD, RBAC, Key Vault & Zero Trust

## Azure Active Directory (Azure AD / Entra ID)

```
Azure AD = Microsoft's cloud identity platform
├── Users, Groups, Service Principals, Managed Identities
├── Authentication: OAuth 2.0, OpenID Connect, SAML
├── MFA, Conditional Access, Identity Protection
└── B2B (external users), B2C (customer identities)

Identity Types:
  User:               Human identity (employee, admin)
  Group:              Collection of users/service principals
  Service Principal:  App identity (non-human, has credentials)
  Managed Identity:   Azure-managed service principal (no credentials to manage)
    System-assigned:  Tied to resource lifecycle, deleted with resource
    User-assigned:    Independent lifecycle, shared across resources
```

## RBAC (Role-Based Access Control)

```
RBAC Model:
  Security Principal (who)  → Role Definition (what) → Scope (where)

Built-in Roles:
  Owner:       Full access + manage access
  Contributor: Full access, cannot manage access
  Reader:      Read-only access
  User Access Administrator: Manage access only

Scope Hierarchy (inheritance flows down):
  Management Group
    └── Subscription
          └── Resource Group
                └── Resource

Best Practices:
  1. Principle of least privilege
  2. Assign roles to groups, not individuals
  3. Use built-in roles before custom
  4. Prefer resource group scope over subscription
  5. Use PIM (Privileged Identity Management) for admin roles
```

```bash
# List role assignments
az role assignment list \
  --resource-group $RG \
  --output table

# Assign role
az role assignment create \
  --assignee "user@company.com" \
  --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG"

# Assign to managed identity
az role assignment create \
  --assignee $MANAGED_IDENTITY_PRINCIPAL_ID \
  --role "Storage Blob Data Reader" \
  --scope $STORAGE_ACCOUNT_ID

# Create custom role
az role definition create --role-definition '{
  "Name": "VM Operator",
  "Description": "Can start and stop VMs",
  "Actions": [
    "Microsoft.Compute/virtualMachines/start/action",
    "Microsoft.Compute/virtualMachines/deallocate/action",
    "Microsoft.Compute/virtualMachines/read"
  ],
  "NotActions": [],
  "AssignableScopes": ["/subscriptions/'$SUBSCRIPTION_ID'"]
}'
```

## Managed Identities

```bash
# Create user-assigned managed identity
az identity create \
  --name mi-myapp-prod \
  --resource-group $RG \
  --location $LOCATION

# Get principal ID
PRINCIPAL_ID=$(az identity show \
  --name mi-myapp-prod \
  --resource-group $RG \
  --query principalId \
  --output tsv)

# Assign to VM
az vm identity assign \
  --resource-group $RG \
  --name $VM_NAME \
  --identities mi-myapp-prod

# Assign to App Service
az webapp identity assign \
  --name $APP_NAME \
  --resource-group $RG \
  --identities mi-myapp-prod

# Grant Key Vault access
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Key Vault Secrets User" \
  --scope $KV_ID

# Use in code (no credentials needed!)
# Node.js example:
# const { DefaultAzureCredential } = require('@azure/identity');
# const { SecretClient } = require('@azure/keyvault-secrets');
# const credential = new DefaultAzureCredential();
# const client = new SecretClient(vaultUrl, credential);
# const secret = await client.getSecret('MySecret');
```

## Key Vault

```bash
# Create Key Vault with RBAC
az keyvault create \
  --name $KV_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku standard \
  --enable-rbac-authorization true \
  --enable-soft-delete true \
  --soft-delete-retention-days 90 \
  --enable-purge-protection true

# Secrets
az keyvault secret set --vault-name $KV_NAME --name "DbPassword" --value "secret123"
az keyvault secret show --vault-name $KV_NAME --name "DbPassword"
az keyvault secret list --vault-name $KV_NAME --output table

# Keys (for encryption)
az keyvault key create \
  --vault-name $KV_NAME \
  --name "DataEncryptionKey" \
  --kty RSA \
  --size 2048 \
  --ops encrypt decrypt

# Certificates
az keyvault certificate create \
  --vault-name $KV_NAME \
  --name "AppCert" \
  --policy "$(az keyvault certificate get-default-policy)"

# Rotate secret (create new version)
az keyvault secret set \
  --vault-name $KV_NAME \
  --name "DbPassword" \
  --value "newSecret456"

# Disable old version
az keyvault secret set-attributes \
  --vault-name $KV_NAME \
  --name "DbPassword" \
  --version $OLD_VERSION \
  --enabled false
```

## Zero Trust Security Model

```
Zero Trust Principles:
  1. Verify explicitly:    Always authenticate and authorize
  2. Least privilege:      Limit access to minimum needed
  3. Assume breach:        Design as if already compromised

Azure Zero Trust Implementation:
  Identity:    Azure AD + MFA + Conditional Access
  Devices:     Intune + Defender for Endpoint
  Applications: App Proxy + MCAS
  Data:        Information Protection + DLP
  Infrastructure: Defender for Cloud + JIT VM access
  Network:     Micro-segmentation + NSG + Azure Firewall

Conditional Access Policies:
  ├── Require MFA for all admin access
  ├── Block legacy authentication protocols
  ├── Require compliant device for sensitive apps
  ├── Block access from risky sign-in locations
  └── Require approved apps for mobile access
```

## Microsoft Defender for Cloud

```bash
# Enable Defender for Cloud
az security pricing create \
  --name VirtualMachines \
  --tier Standard

az security pricing create \
  --name SqlServers \
  --tier Standard

az security pricing create \
  --name AppServices \
  --tier Standard

# Get security recommendations
az security assessment list \
  --resource-group $RG \
  --output table

# Get secure score
az security secure-score-controls list \
  --output table
```

## Interview Questions

### Q1: What is the difference between Authentication and Authorization in Azure?
**Answer:**
- **Authentication (AuthN)**: Verifying identity — "Who are you?" Azure AD handles this via OAuth 2.0/OIDC.
- **Authorization (AuthZ)**: Verifying permissions — "What can you do?" RBAC handles this.
- Azure AD authenticates, RBAC authorizes.

### Q2: What is a Managed Identity and why is it better than service principals with credentials?
**Answer:**
Managed Identity is an Azure AD identity automatically managed by Azure. Benefits over service principals:
1. **No credentials to manage**: no passwords, certificates, or rotation
2. **No credential leakage**: credentials never exist in code or config
3. **Automatic rotation**: Azure handles the underlying credentials
4. **Integrated**: works seamlessly with Azure services
Use system-assigned for single-resource identity, user-assigned for shared identity across resources.

### Q3: What is the difference between Key Vault access policies and RBAC?
**Answer:**
- **Access Policies** (legacy): Vault-level permissions. Coarse-grained. Cannot use Azure Policy. Being deprecated.
- **RBAC** (recommended): Standard Azure RBAC. Fine-grained (per secret/key/certificate). Supports Azure Policy, PIM, audit logs. Use RBAC for new deployments.

### Q4: How do you implement the principle of least privilege in Azure?
**Answer:**
1. Assign roles at the lowest scope needed (resource > resource group > subscription)
2. Use built-in roles with minimum permissions
3. Assign to groups, not individuals
4. Use PIM for just-in-time privileged access
5. Regular access reviews
6. Use Managed Identities (no standing credentials)
7. Enable Conditional Access for sensitive operations
8. Monitor with Azure AD Identity Protection

### Q5: What is Conditional Access and give an example policy?
**Answer:**
Conditional Access evaluates signals (user, device, location, app, risk) and enforces access controls. Example: "Require MFA when accessing Azure portal from outside corporate network":
- Assignments: All users, Azure Management app
- Conditions: Location = outside named locations
- Grant: Require MFA

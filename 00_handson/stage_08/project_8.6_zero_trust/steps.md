# Steps — Project 8.6: Zero Trust Security on Azure

## Phase 1: Enable Conditional Access (Require MFA)

```bash
# Variables
RG="rg-zero-trust-lab"
LOCATION="eastus"
TENANT_ID=$(az account show --query tenantId -o tsv)

# Create resource group
az group create --name $RG --location $LOCATION --tags project=zero-trust stage=08

# Conditional Access requires Azure AD P2 license
# Check current license
az ad user list --query "[].assignedLicenses" --output table

# Create Conditional Access policy via Microsoft Graph API
# Requires: Global Admin or Security Admin role
TOKEN=$(az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv)

# Policy: Require MFA for all users accessing Azure Management
curl -X POST \
  "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "Require MFA for Azure Management",
    "state": "enabled",
    "conditions": {
      "users": {
        "includeUsers": ["All"],
        "excludeUsers": ["break-glass-account-object-id"]
      },
      "applications": {
        "includeApplications": ["797f4846-ba00-4fd7-ba43-dac1f8f63013"]
      },
      "locations": {
        "includeLocations": ["All"]
      }
    },
    "grantControls": {
      "operator": "OR",
      "builtInControls": ["mfa"]
    }
  }'

# Policy: Block legacy authentication (SMTP, IMAP, POP3)
curl -X POST \
  "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "Block Legacy Authentication",
    "state": "enabled",
    "conditions": {
      "users": {"includeUsers": ["All"]},
      "applications": {"includeApplications": ["All"]},
      "clientAppTypes": ["exchangeActiveSync", "other"]
    },
    "grantControls": {
      "operator": "OR",
      "builtInControls": ["block"]
    }
  }'

# List all CA policies
curl -X GET \
  "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" \
  -H "Authorization: Bearer $TOKEN" | python -m json.tool
```

## Phase 2: Configure PIM for JIT Access

```bash
# PIM requires Azure AD P2 license
# Enable PIM for Global Administrator role

# List eligible role assignments
az rest \
  --method GET \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01" \
  --query "value[].{Principal:properties.principalId, Role:properties.roleDefinitionId, Expiry:properties.scheduleInfo.expiration.endDateTime}" \
  --output table

# Activate PIM role (JIT access) — requires eligible assignment first
# In Portal: Azure AD → PIM → My roles → Activate
# Via API:
PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
ROLE_DEF_ID="b24988ac-6180-42a0-ab88-20f7382dd24c"  # Contributor

az rest \
  --method PUT \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/$(uuidgen)?api-version=2020-10-01" \
  --body '{
    "properties": {
      "principalId": "'"$PRINCIPAL_ID"'",
      "roleDefinitionId": "/subscriptions/'"$SUBSCRIPTION_ID"'/providers/Microsoft.Authorization/roleDefinitions/'"$ROLE_DEF_ID"'",
      "requestType": "SelfActivate",
      "scheduleInfo": {
        "startDateTime": null,
        "expiration": {
          "type": "AfterDuration",
          "duration": "PT8H"
        }
      },
      "justification": "Deploying Zero Trust lab infrastructure"
    }
  }'

echo "PIM activation requested. Check Azure AD PIM portal for approval status."
```

## Phase 3: Replace Public Endpoints with Private Endpoints

```bash
# Deploy VNet and Private Endpoints via Terraform
cd terraform
terraform init
terraform apply -auto-approve

# Verify Key Vault private endpoint
KV_NAME=$(terraform output -raw key_vault_name)
PE_NAME="pe-keyvault-lab"

az network private-endpoint show \
  --name $PE_NAME \
  --resource-group $RG \
  --query "{Name:name, ProvisioningState:provisioningState, PrivateIP:customDnsConfigs[0].ipAddresses[0]}" \
  --output table

# Verify DNS resolution goes through private endpoint (not public)
# From within the VNet, this should resolve to 10.0.2.x
nslookup $KV_NAME.vault.azure.net

# Disable public access on Key Vault
az keyvault update \
  --name $KV_NAME \
  --resource-group $RG \
  --public-network-access Disabled

# Verify Key Vault is no longer accessible from public internet
curl -I "https://$KV_NAME.vault.azure.net/" 
# Should return: Connection refused or timeout

# Disable public access on Storage Account
STORAGE_NAME=$(terraform output -raw storage_account_name)
az storage account update \
  --name $STORAGE_NAME \
  --resource-group $RG \
  --public-network-access Disabled \
  --default-action Deny

echo "Public access disabled. Resources only accessible via Private Endpoints."
```

## Phase 4: Enable Microsoft Defender for Cloud

```bash
# Enable Defender for Cloud on subscription
az security pricing create \
  --name VirtualMachines \
  --tier Standard

az security pricing create \
  --name SqlServers \
  --tier Standard

az security pricing create \
  --name StorageAccounts \
  --tier Standard

az security pricing create \
  --name KeyVaults \
  --tier Standard

az security pricing create \
  --name Containers \
  --tier Standard

# Enable auto-provisioning of Log Analytics agent
az security auto-provisioning-setting update \
  --name mma \
  --auto-provision On

# Set security contact
az security contact create \
  --name "security-contact" \
  --email "security@yourdomain.com" \
  --phone "+1-555-0100" \
  --alert-notifications On \
  --alerts-to-admins On

# Check Defender status
az security pricing list --output table
```

## Phase 5: Audit Secure Score

```bash
# Get current Secure Score
az security secure-score list --output table

# Get Secure Score controls breakdown
az security secure-score-control-definitions list --output table

# Get specific recommendations
az security assessment list \
  --query "[?properties.status.code=='Unhealthy'].{Name:displayName, Severity:properties.metadata.severity, Score:properties.score.max}" \
  --output table

# Run the Zero Trust checker script
cd ../code
python zero_trust_checker.py

# Check NSG rules for open ports
az network nsg list \
  --resource-group $RG \
  --query "[].{NSG:name, Rules:securityRules[?access=='Allow' && direction=='Inbound' && sourceAddressPrefix=='*'].{Port:destinationPortRange, Protocol:protocol}}" \
  --output json

# Check storage accounts with public access
az storage account list \
  --query "[?allowBlobPublicAccess==true].{Name:name, RG:resourceGroup, PublicAccess:allowBlobPublicAccess}" \
  --output table

# Check for unencrypted disks
az disk list \
  --query "[?encryptionSettingsCollection.enabled!=true].{Name:name, RG:resourceGroup}" \
  --output table

# Cleanup
az group delete --name $RG --yes --no-wait
```

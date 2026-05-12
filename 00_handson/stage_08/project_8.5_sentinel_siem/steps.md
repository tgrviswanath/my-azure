# Steps — Project 8.5: Microsoft Sentinel SIEM

## Phase 1: Enable Sentinel on Log Analytics

```bash
# Variables
RG="rg-sentinel-lab"
LOCATION="eastus"
WORKSPACE="law-sentinel-lab"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Create resource group
az group create \
  --name $RG \
  --location $LOCATION \
  --tags project=sentinel-lab stage=08

# Create Log Analytics Workspace (Sentinel requires this)
az monitor log-analytics workspace create \
  --resource-group $RG \
  --workspace-name $WORKSPACE \
  --location $LOCATION \
  --sku PerGB2018 \
  --retention-time 90

# Get workspace ID and key
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group $RG \
  --workspace-name $WORKSPACE \
  --query customerId -o tsv)

WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
  --resource-group $RG \
  --workspace-name $WORKSPACE \
  --query primarySharedKey -o tsv)

echo "Workspace ID: $WORKSPACE_ID"

# Enable Microsoft Sentinel on the workspace
az sentinel onboarding-state create \
  --resource-group $RG \
  --workspace-name $WORKSPACE \
  --name default

# Verify Sentinel is enabled
az sentinel onboarding-state show \
  --resource-group $RG \
  --workspace-name $WORKSPACE \
  --name default
```

## Phase 2: Connect Data Sources

```bash
# Enable Azure Activity Log connector
# Get workspace resource ID
WORKSPACE_RESOURCE_ID=$(az monitor log-analytics workspace show \
  --resource-group $RG \
  --workspace-name $WORKSPACE \
  --query id -o tsv)

# Connect Azure Activity Log via Diagnostic Settings
az monitor diagnostic-settings create \
  --name "sentinel-activity-log" \
  --resource "/subscriptions/$SUBSCRIPTION_ID" \
  --workspace $WORKSPACE_RESOURCE_ID \
  --logs '[{"category": "Administrative", "enabled": true},
           {"category": "Security", "enabled": true},
           {"category": "ServiceHealth", "enabled": true},
           {"category": "Alert", "enabled": true},
           {"category": "Policy", "enabled": true}]'

# Enable Azure AD connector (requires Azure AD P2 or Microsoft 365 E5)
# In Portal: Sentinel → Data connectors → Azure Active Directory → Connect
# Via CLI (preview):
az sentinel data-connector create \
  --resource-group $RG \
  --workspace-name $WORKSPACE \
  --data-connector-id "AzureActiveDirectory" \
  --name "AzureAD-Connector" \
  --kind AzureActiveDirectory \
  --tenant-id $(az account show --query tenantId -o tsv)

# Verify data is flowing (wait 5-10 minutes after connecting)
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "AzureActivity | take 10" \
  --output table

# Check SigninLogs are flowing
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "SigninLogs | summarize count() by bin(TimeGenerated, 1h) | order by TimeGenerated desc | take 24" \
  --output table
```

## Phase 3: Create Scheduled Analytics Rule

```bash
# Create analytics rule via Terraform (see terraform/main.tf)
# Or via REST API:

# Get access token
TOKEN=$(az account get-access-token --query accessToken -o tsv)

# Create scheduled analytics rule for brute force detection
curl -X PUT \
  "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE/providers/Microsoft.SecurityInsights/alertRules/brute-force-rule-001?api-version=2023-02-01" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "kind": "Scheduled",
    "properties": {
      "displayName": "Brute Force Attack - Multiple Failed Logins",
      "description": "Detects more than 10 failed login attempts from same IP in 5 minutes",
      "severity": "High",
      "enabled": true,
      "query": "SigninLogs | where ResultType != \"0\" | summarize FailedAttempts = count(), Users = dcount(UserPrincipalName) by IPAddress, bin(TimeGenerated, 5m) | where FailedAttempts > 10",
      "queryFrequency": "PT5M",
      "queryPeriod": "PT5M",
      "triggerOperator": "GreaterThan",
      "triggerThreshold": 0,
      "suppressionDuration": "PT1H",
      "suppressionEnabled": false,
      "tactics": ["CredentialAccess"],
      "techniques": ["T1110"]
    }
  }'

# Verify rule was created
az sentinel alert-rule list \
  --resource-group $RG \
  --workspace-name $WORKSPACE \
  --output table
```

## Phase 4: Simulate Brute Force Attack

```bash
# Install required tools
pip install azure-identity msal requests

# Simulate failed logins using Python script
cat > /tmp/simulate_brute_force.py << 'EOF'
import requests
import time

# This simulates failed authentication attempts for testing
# Uses a non-existent user to generate SigninLogs entries
tenant_id = "YOUR_TENANT_ID"
client_id = "YOUR_APP_CLIENT_ID"

for i in range(15):
    response = requests.post(
        f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token",
        data={
            "grant_type": "password",
            "client_id": client_id,
            "username": f"testuser{i}@yourdomain.com",
            "password": "WrongPassword123!",
            "scope": "https://graph.microsoft.com/.default"
        }
    )
    print(f"Attempt {i+1}: Status {response.status_code} - {response.json().get('error_description', '')[:50]}")
    time.sleep(2)

print("Simulation complete. Check Sentinel incidents in 5-10 minutes.")
EOF

python /tmp/simulate_brute_force.py

# Query for failed logins in Log Analytics
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "SigninLogs | where ResultType != '0' | summarize count() by IPAddress, UserPrincipalName | order by count_ desc" \
  --output table
```

## Phase 5: Investigate Incident

```bash
# List all incidents
az sentinel incident list \
  --resource-group $RG \
  --workspace-name $WORKSPACE \
  --output table

# Get specific incident details
INCIDENT_ID="<incident-id-from-above>"

az sentinel incident show \
  --resource-group $RG \
  --workspace-name $WORKSPACE \
  --incident-id $INCIDENT_ID

# List incident entities (IPs, users, hosts)
az sentinel incident entity list \
  --resource-group $RG \
  --workspace-name $WORKSPACE \
  --incident-id $INCIDENT_ID \
  --output table

# Add comment to incident
az sentinel incident comment create \
  --resource-group $RG \
  --workspace-name $WORKSPACE \
  --incident-id $INCIDENT_ID \
  --comment-id "investigation-001" \
  --message "Investigated: IP 1.2.3.4 confirmed malicious. User account disabled. Blocking at firewall."

# Update incident status to Closed
az sentinel incident update \
  --resource-group $RG \
  --workspace-name $WORKSPACE \
  --incident-id $INCIDENT_ID \
  --status Closed \
  --classification TruePositive \
  --classification-reason SuspiciousActivity

# Run the Python analyzer for full report
cd code
python sentinel_analyzer.py

# Cleanup (to avoid costs)
az group delete --name $RG --yes --no-wait
```

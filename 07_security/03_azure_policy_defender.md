# Azure Policy, Defender for Cloud & Sentinel

## Azure Policy

Azure Policy enforces organizational standards and assesses compliance at scale. It evaluates resources against business rules expressed as policy definitions.

```
Policy Definition → Policy Assignment → Compliance Evaluation
     (rules)           (scope)              (results)

Effects (in order of restrictiveness):
  Deny:     Block non-compliant resource creation/update
  Audit:    Allow but flag as non-compliant
  Append:   Add fields to resource (e.g., tags)
  Modify:   Add/replace/remove properties
  DeployIfNotExists: Deploy related resource if missing
  AuditIfNotExists:  Audit if related resource missing
  Disabled: Policy not evaluated
```

### Built-in Policy Examples

```bash
# List built-in policies
az policy definition list \
  --query "[?policyType=='BuiltIn'].{Name:displayName, ID:name}" \
  --output table | head -20

# Assign "Require a tag on resources" policy
az policy assignment create \
  --name "require-environment-tag" \
  --display-name "Require Environment tag on all resources" \
  --policy "871b6d14-10aa-478d-b590-94f262ecfa99" \
  --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --params '{"tagName": {"value": "Environment"}}'

# Assign "Allowed locations" policy
az policy assignment create \
  --name "allowed-locations" \
  --display-name "Allowed Azure regions" \
  --policy "e56962a6-4747-49cd-b67b-bf8b01975c4c" \
  --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --params '{
    "listOfAllowedLocations": {
      "value": ["eastus", "eastus2", "westus2", "westeurope"]
    }
  }'

# Assign "Require HTTPS on App Service"
az policy assignment create \
  --name "require-https-appservice" \
  --policy "a4af4a39-4135-47fb-b175-47fbdf85311d" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG"
```

### Custom Policy Definition

```bash
# Custom policy: require specific VM SKUs only
az policy definition create \
  --name "allowed-vm-skus-prod" \
  --display-name "Allowed VM SKUs for production" \
  --description "Restricts VM sizes to approved list" \
  --mode All \
  --rules '{
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Compute/virtualMachines"
        },
        {
          "not": {
            "field": "Microsoft.Compute/virtualMachines/sku.name",
            "in": ["Standard_D2s_v5", "Standard_D4s_v5", "Standard_D8s_v5",
                   "Standard_E4s_v5", "Standard_E8s_v5"]
          }
        }
      ]
    },
    "then": {
      "effect": "Deny"
    }
  }'

# Custom policy: auto-tag resources with creator
az policy definition create \
  --name "auto-tag-creator" \
  --display-name "Auto-tag resources with creator" \
  --mode Indexed \
  --rules '{
    "if": {
      "field": "tags[Creator]",
      "exists": "false"
    },
    "then": {
      "effect": "Modify",
      "details": {
        "roleDefinitionIds": [
          "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
        ],
        "operations": [{
          "operation": "addOrReplace",
          "field": "tags[Creator]",
          "value": "[requestContext().apiVersion]"
        }]
      }
    }
  }'
```

### Policy Initiatives (Groups of Policies)

```bash
# Create initiative (policy set)
az policy set-definition create \
  --name "production-baseline" \
  --display-name "Production Security Baseline" \
  --definitions '[
    {
      "policyDefinitionId": "/providers/Microsoft.Authorization/policyDefinitions/a4af4a39-4135-47fb-b175-47fbdf85311d",
      "policyDefinitionReferenceId": "require-https"
    },
    {
      "policyDefinitionId": "/providers/Microsoft.Authorization/policyDefinitions/404c3081-a854-4457-ae30-26a93ef643f9",
      "policyDefinitionReferenceId": "require-secure-transfer-storage"
    },
    {
      "policyDefinitionId": "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c",
      "policyDefinitionReferenceId": "allowed-locations",
      "parameters": {
        "listOfAllowedLocations": {
          "value": ["eastus", "westeurope"]
        }
      }
    }
  ]'

# Assign initiative
az policy assignment create \
  --name "prod-baseline-assignment" \
  --policy-set-definition "production-baseline" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

# Check compliance
az policy state summarize \
  --subscription $SUBSCRIPTION_ID \
  --query "results.policyAssignments[*].{Policy:policyAssignmentId,Compliant:results.compliantResources,NonCompliant:results.nonCompliantResources}" \
  --output table
```

---

## Microsoft Defender for Cloud

Defender for Cloud provides unified security management and advanced threat protection across Azure, on-premises, and multi-cloud.

```
Defender for Cloud
├── CSPM (Cloud Security Posture Management)
│   ├── Secure Score (0-100)
│   ├── Security recommendations
│   └── Regulatory compliance (CIS, PCI-DSS, ISO 27001)
└── CWP (Cloud Workload Protection)
    ├── Defender for Servers
    ├── Defender for SQL
    ├── Defender for Storage
    ├── Defender for Containers
    ├── Defender for App Service
    ├── Defender for Key Vault
    └── Defender for DNS
```

### Enable and Configure

```bash
# Enable Defender for Cloud (free tier — CSPM)
az security pricing create \
  --name VirtualMachines \
  --tier Free

# Enable Defender plans (paid — CWP)
PLANS=("VirtualMachines" "SqlServers" "AppServices" "StorageAccounts" \
       "Containers" "KeyVaults" "Dns" "Arm")

for PLAN in "${PLANS[@]}"; do
  az security pricing create \
    --name $PLAN \
    --tier Standard
  echo "Enabled Defender for $PLAN"
done

# Enable auto-provisioning of monitoring agents
az security auto-provisioning-setting update \
  --name mma \
  --auto-provision On

# Get Secure Score
az security secure-score-controls list \
  --query "[*].{Control:displayName, Score:score.current, Max:score.max}" \
  --output table

# Get security recommendations
az security assessment list \
  --query "[?status.code=='Unhealthy'].{Resource:resourceDetails.id, Recommendation:displayName, Severity:metadata.severity}" \
  --output table | head -20

# Get alerts
az security alert list \
  --query "[*].{Alert:alertDisplayName, Severity:severity, Time:timeGeneratedUtc, Resource:compromisedEntity}" \
  --output table
```

### JIT VM Access

```bash
# Enable JIT access on VM
az security jit-policy create \
  --resource-group $RG \
  --location $LOCATION \
  --name default \
  --virtual-machines '[{
    "id": "'$VM_ID'",
    "ports": [
      {
        "number": 22,
        "protocol": "TCP",
        "allowedSourceAddressPrefix": "*",
        "maxRequestAccessDuration": "PT3H"
      },
      {
        "number": 3389,
        "protocol": "TCP",
        "allowedSourceAddressPrefix": "*",
        "maxRequestAccessDuration": "PT3H"
      }
    ]
  }]'

# Request JIT access (opens port for 3 hours)
az security jit-policy initiate \
  --resource-group $RG \
  --location $LOCATION \
  --name default \
  --virtual-machines '[{
    "id": "'$VM_ID'",
    "ports": [{
      "number": 22,
      "duration": "PT3H",
      "allowedSourceAddressPrefix": "'$MY_IP'"
    }]
  }]'
```

---

## Microsoft Sentinel

Sentinel is a cloud-native SIEM (Security Information and Event Management) and SOAR (Security Orchestration, Automation, and Response).

```
Data Sources → Sentinel Workspace → Analytics Rules → Incidents → Playbooks
(Azure AD,       (Log Analytics)    (detect threats)  (alerts)   (auto-respond)
 Office 365,
 Firewalls,
 Custom logs)
```

### Setup

```bash
# Enable Sentinel on Log Analytics Workspace
az sentinel workspace create \
  --workspace-name $LAW_NAME \
  --resource-group $RG

# Connect Azure AD data connector
az sentinel data-connector create \
  --workspace-name $LAW_NAME \
  --resource-group $RG \
  --data-connector-id AzureActiveDirectory \
  --kind AzureActiveDirectory \
  --tenant-id $TENANT_ID

# Connect Azure Activity
az sentinel data-connector create \
  --workspace-name $LAW_NAME \
  --resource-group $RG \
  --data-connector-id AzureActivity \
  --kind AzureActivity \
  --subscription-id $SUBSCRIPTION_ID
```

### Analytics Rules (KQL-based threat detection)

```bash
# Create scheduled analytics rule
az sentinel alert-rule create \
  --workspace-name $LAW_NAME \
  --resource-group $RG \
  --rule-id "brute-force-detection" \
  --kind Scheduled \
  --display-name "Brute Force Attack Detected" \
  --description "Detects multiple failed login attempts" \
  --severity High \
  --enabled true \
  --query-frequency PT1H \
  --query-period PT1H \
  --trigger-operator GreaterThan \
  --trigger-threshold 0 \
  --query '
    SigninLogs
    | where TimeGenerated > ago(1h)
    | where ResultType != "0"
    | summarize FailedAttempts = count(), 
                DistinctIPs = dcount(IPAddress)
      by UserPrincipalName, bin(TimeGenerated, 5m)
    | where FailedAttempts > 10
    | project TimeGenerated, UserPrincipalName, FailedAttempts, DistinctIPs
  '
```

### Playbooks (Automated Response)

```json
// Logic App playbook: auto-block IP on alert
{
  "definition": {
    "triggers": {
      "When_a_response_to_an_Azure_Sentinel_alert_is_triggered": {
        "type": "ApiConnectionWebhook",
        "inputs": {
          "host": { "connection": { "name": "@parameters('$connections')['azuresentinel']['connectionId']" } },
          "body": { "callback_url": "@{listCallbackUrl()}" },
          "path": "/subscribe"
        }
      }
    },
    "actions": {
      "Get_alert_details": { "type": "ApiConnection" },
      "Block_IP_in_NSG": {
        "type": "ApiConnection",
        "inputs": {
          "host": { "connection": { "name": "@parameters('$connections')['arm']['connectionId']" } },
          "method": "put",
          "path": "/subscriptions/@{variables('subscriptionId')}/resourceGroups/@{variables('rgName')}/providers/Microsoft.Network/networkSecurityGroups/@{variables('nsgName')}/securityRules/BlockMaliciousIP",
          "body": {
            "properties": {
              "priority": 100,
              "protocol": "*",
              "access": "Deny",
              "direction": "Inbound",
              "sourceAddressPrefix": "@{triggerBody()?['Entities']?[0]?['Address']}",
              "destinationAddressPrefix": "*",
              "sourcePortRange": "*",
              "destinationPortRange": "*"
            }
          }
        }
      },
      "Send_Teams_notification": {
        "type": "ApiConnection",
        "inputs": {
          "body": {
            "messageBody": "🚨 Security Alert: Blocked IP @{triggerBody()?['Entities']?[0]?['Address']} due to brute force attack"
          }
        }
      }
    }
  }
}
```

---

## Interview Q&A

### Q1: What is Azure Policy and how does it differ from RBAC?
**RBAC**: Controls *who* can perform *actions* on Azure resources (identity-based access control). Example: "Alice can create VMs."
**Azure Policy**: Controls *what* resources can look like (resource compliance). Example: "All VMs must use Premium SSD" or "Resources must have an Environment tag." RBAC prevents unauthorized actions; Policy ensures resources meet standards even when authorized users create them. Use both together.

### Q2: What is Secure Score in Defender for Cloud?
Secure Score is a numeric representation (0-100) of your security posture. It's calculated based on security recommendations — each recommendation has a score impact. Completing recommendations increases your score. Use it to: prioritize security improvements, track progress over time, compare across subscriptions. Target: > 70 for production environments.

### Q3: What is the difference between Defender for Cloud and Microsoft Sentinel?
**Defender for Cloud**: Focuses on Azure resource security posture (CSPM) and threat protection for specific workloads (VMs, SQL, containers). Generates security recommendations and alerts for Azure resources.
**Sentinel**: Full SIEM/SOAR platform. Collects logs from any source (Azure, on-premises, other clouds, SaaS). Correlates events across sources, detects complex attack patterns, automates responses. Sentinel ingests Defender for Cloud alerts as one of many data sources.

### Q4: How do you implement a "deny by default" security posture in Azure?
1. **Azure Policy**: Deny resource creation outside approved regions, SKUs, configurations
2. **NSG**: Default deny-all inbound rule on all subnets
3. **Azure Firewall**: Default deny, explicit allow rules for required traffic
4. **Private Endpoints**: Disable public access on all PaaS services
5. **RBAC**: No standing privileged access — use PIM for just-in-time
6. **Conditional Access**: Block access unless MFA + compliant device
7. **Storage**: `--public-network-access Disabled` on all storage accounts
8. **Key Vault**: Network ACLs deny all, allow only specific VNets

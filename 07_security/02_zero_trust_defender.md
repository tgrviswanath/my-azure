# Azure Security — Zero Trust, Defender & Compliance

## Zero Trust Implementation

```
Zero Trust = "Never trust, always verify"
├── Verify explicitly:  Authenticate + authorize every request
├── Least privilege:    Minimum access needed
└── Assume breach:      Design as if already compromised

Pillars:
  Identity:       Azure AD + MFA + Conditional Access + PIM
  Devices:        Intune + Defender for Endpoint + Compliance policies
  Applications:   App Proxy + MCAS + App permissions
  Data:           Purview + Information Protection + DLP
  Infrastructure: Defender for Cloud + JIT VM access + Bastion
  Network:        Micro-segmentation + NSG + Azure Firewall + Private Endpoints
```

## Conditional Access Policies

```bash
# Example policies (configured via Azure AD portal or Graph API)

# Policy 1: Require MFA for all users accessing Azure portal
# Assignments: All users
# Cloud apps: Microsoft Azure Management
# Conditions: Any location
# Grant: Require MFA

# Policy 2: Block legacy authentication
# Assignments: All users
# Cloud apps: All cloud apps
# Conditions: Client apps = Exchange ActiveSync, Other clients
# Grant: Block

# Policy 3: Require compliant device for sensitive apps
# Assignments: All users
# Cloud apps: Salesforce, SAP
# Conditions: Any platform
# Grant: Require device to be marked as compliant

# Policy 4: Block risky sign-ins
# Assignments: All users
# Cloud apps: All cloud apps
# Conditions: Sign-in risk = High
# Grant: Block (or require MFA + password change)
```

## Microsoft Defender for Cloud

```bash
# Enable all Defender plans
PLANS=("VirtualMachines" "SqlServers" "AppServices" "StorageAccounts" \
       "Containers" "KeyVaults" "Dns" "Arm" "OpenSourceRelationalDatabases")

for PLAN in "${PLANS[@]}"; do
  az security pricing create \
    --name "$PLAN" \
    --tier Standard
done

# Get security recommendations
az security assessment list \
  --resource-group $RG \
  --query "[?status.code=='Unhealthy'].{Name:displayName,Severity:metadata.severity}" \
  --output table

# Get secure score
az security secure-score-controls list \
  --query "[].{Control:displayName,Score:score.current,Max:score.max}" \
  --output table

# Enable auto-provisioning (installs agents on VMs)
az security auto-provisioning-setting update \
  --name mma \
  --auto-provision On

# Configure email notifications
az security contact create \
  --name "security-contact" \
  --email "security@company.com" \
  --phone "+1-555-0100" \
  --alert-notifications On \
  --alerts-to-admins On
```

## Azure Sentinel (Microsoft Sentinel)

```bash
# Enable Sentinel on Log Analytics workspace
az sentinel workspace create \
  --workspace-name law-sentinel-prod \
  --resource-group $RG \
  --location $LOCATION

# Connect data sources
az sentinel data-connector create \
  --workspace-name law-sentinel-prod \
  --resource-group $RG \
  --data-connector-id AzureActiveDirectory \
  --kind AzureActiveDirectory

# Create analytics rule (detect brute force)
az sentinel alert-rule create \
  --workspace-name law-sentinel-prod \
  --resource-group $RG \
  --rule-id "brute-force-detection" \
  --kind Scheduled \
  --display-name "Brute Force Attack Detection" \
  --severity High \
  --enabled true \
  --query "SigninLogs | where ResultType != '0' | summarize count() by UserPrincipalName, IPAddress | where count_ > 10" \
  --query-frequency PT1H \
  --query-period PT1H \
  --trigger-operator GreaterThan \
  --trigger-threshold 0
```

## Network Security Best Practices

```bash
# 1. Enable DDoS Protection Standard
az network ddos-protection create \
  --name ddos-prod \
  --resource-group $RG \
  --location $LOCATION

az network vnet update \
  --name $VNET_NAME \
  --resource-group $RG \
  --ddos-protection true \
  --ddos-protection-plan ddos-prod

# 2. Azure Firewall with threat intelligence
az network firewall create \
  --name fw-hub-prod \
  --resource-group $RG \
  --location $LOCATION \
  --sku-name AZFW_VNet \
  --sku-tier Premium \
  --threat-intel-mode Alert

# Firewall policy with IDPS
az network firewall policy create \
  --name fwpol-prod \
  --resource-group $RG \
  --location $LOCATION \
  --sku Premium \
  --idps-mode Alert \
  --threat-intel-mode Alert

# 3. Just-in-time VM access
az security jit-policy create \
  --resource-group $RG \
  --vm-name $VM_NAME \
  --location $LOCATION \
  --ports '[{"number":22,"protocol":"TCP","allowedSourceAddressPrefix":"*","maxRequestAccessDuration":"PT3H"}]'

# Request JIT access
az security jit-policy initiate \
  --resource-group $RG \
  --vm-name $VM_NAME \
  --ports '[{"number":22,"duration":"PT1H","allowedSourceAddressPrefix":"203.0.113.0/24"}]'
```

## Compliance & Governance

```bash
# Assign Azure Policy initiative (CIS benchmark)
az policy assignment create \
  --name "cis-benchmark" \
  --display-name "CIS Microsoft Azure Foundations Benchmark" \
  --policy-set-definition "/providers/Microsoft.Authorization/policySetDefinitions/1a5bb27d-173f-493e-9568-eb56638dde4d" \
  --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --enforcement-mode Default

# Create custom policy: require tags
az policy definition create \
  --name "require-environment-tag" \
  --display-name "Require Environment tag on resources" \
  --description "Requires the Environment tag on all resources" \
  --rules '{
    "if": {
      "field": "tags[Environment]",
      "exists": "false"
    },
    "then": {
      "effect": "deny"
    }
  }' \
  --mode All

# Assign policy
az policy assignment create \
  --name "require-env-tag" \
  --policy "require-environment-tag" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG"

# Check compliance
az policy state list \
  --resource-group $RG \
  --filter "complianceState eq 'NonCompliant'" \
  --query "[].{Resource:resourceId,Policy:policyDefinitionName}" \
  --output table
```

## Security Checklist

```
Identity:
  ✅ MFA enabled for all users
  ✅ Conditional Access policies configured
  ✅ PIM for privileged roles
  ✅ Regular access reviews
  ✅ No service accounts with passwords (use Managed Identity)

Network:
  ✅ No public IPs on VMs (use Bastion)
  ✅ NSGs on all subnets with deny-all default
  ✅ Private endpoints for PaaS services
  ✅ Azure Firewall in hub VNet
  ✅ DDoS Protection Standard enabled
  ✅ WAF on Application Gateway / Front Door

Data:
  ✅ Encryption at rest (SSE with CMK for sensitive data)
  ✅ Encryption in transit (TLS 1.2+, HTTPS only)
  ✅ Soft delete enabled on storage and Key Vault
  ✅ Backup configured and tested
  ✅ No public access on storage accounts

Monitoring:
  ✅ Defender for Cloud enabled (all plans)
  ✅ Diagnostic settings on all resources
  ✅ Security alerts configured
  ✅ Log Analytics workspace with 90-day retention
  ✅ Microsoft Sentinel for SIEM

Governance:
  ✅ Azure Policy for compliance
  ✅ Resource tagging enforced
  ✅ Budget alerts configured
  ✅ Regular security assessments
```

## Interview Questions

### Q1: What is the Zero Trust security model?
**Answer:** Zero Trust assumes no implicit trust — every request must be authenticated and authorized regardless of network location. Three principles: (1) Verify explicitly — always authenticate/authorize using all available data points. (2) Use least privilege access — limit user access with JIT/JEA. (3) Assume breach — minimize blast radius, segment access, encrypt everything, use analytics to detect threats.

### Q2: What is Microsoft Defender for Cloud and what does it protect?
**Answer:** Defender for Cloud is a unified security management and threat protection platform. It provides: security posture assessment (Secure Score), threat detection, regulatory compliance dashboard, and recommendations. Protects: VMs, containers (AKS), databases, storage, App Service, Key Vault, DNS, ARM. Requires enabling per-service plans (Standard tier).

### Q3: How do you implement network micro-segmentation in Azure?
**Answer:**
1. **NSGs**: subnet-level and NIC-level rules, deny all by default
2. **Azure Firewall**: centralized policy, FQDN filtering, IDPS
3. **Network policies in AKS**: pod-to-pod communication control
4. **Private endpoints**: services only accessible from VNet
5. **Service endpoints**: restrict storage/SQL to specific subnets
6. **Application Security Groups**: group VMs logically for NSG rules

### Q4: What is Just-in-Time VM access?
**Answer:** JIT VM access (via Defender for Cloud) locks down inbound ports (RDP/SSH) by default. When access is needed, users request it for a specific time period (e.g., 1 hour) from specific IPs. Defender for Cloud temporarily opens the NSG rule, then closes it automatically. Eliminates standing access to management ports, reducing attack surface.

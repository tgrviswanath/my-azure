# Project 8.5 — Microsoft Sentinel SIEM

## What This Does

Microsoft Sentinel is Azure's cloud-native SIEM (Security Information and Event Management) and SOAR (Security Orchestration, Automation, and Response) platform. This project sets up a full threat detection pipeline: collect logs from Azure AD and Activity Log, write KQL analytics rules to detect brute force attacks, generate incidents, and auto-respond with Logic App playbooks.

## Services Used

| Service | Purpose | SKU |
|---|---|---|
| Microsoft Sentinel | SIEM/SOAR platform | Pay-per-GB |
| Log Analytics Workspace | Central log store | Pay-per-GB |
| Azure Active Directory | Identity log source | Free tier |
| Azure Activity Log | Subscription audit log | Free |
| Logic Apps | Automated playbook response | Consumption |
| Azure Monitor | Metrics and alerting | Free tier |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Microsoft Sentinel                           │
│                                                                 │
│  Data Connectors          Analytics Rules       Incidents       │
│  ┌──────────────┐         ┌──────────────┐     ┌───────────┐   │
│  │ Azure AD     │──logs──▶│ Brute Force  │────▶│ Incident  │   │
│  │ Activity Log │         │ Detection    │     │ #1234     │   │
│  │ Defender     │         │ (KQL)        │     └─────┬─────┘   │
│  └──────────────┘         └──────────────┘           │         │
│                                                       ▼         │
│  Log Analytics Workspace                    Playbooks           │
│  ┌──────────────────────┐                  ┌───────────────┐   │
│  │ SecurityEvent        │                  │ Logic App     │   │
│  │ SigninLogs           │                  │ - Block user  │   │
│  │ AuditLogs            │                  │ - Send email  │   │
│  │ AzureActivity        │                  │ - Create ITSM │   │
│  └──────────────────────┘                  └───────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## How to Run

### Prerequisites
```bash
az extension add --name sentinel
az login
export RG="rg-sentinel-lab"
export LOCATION="eastus"
export WORKSPACE="law-sentinel-lab"
```

### Deploy
```bash
# 1. Create resource group and Log Analytics workspace
az group create --name $RG --location $LOCATION
az monitor log-analytics workspace create \
  --resource-group $RG \
  --workspace-name $WORKSPACE \
  --location $LOCATION \
  --sku PerGB2018

# 2. Enable Sentinel on the workspace
az sentinel onboarding-state create \
  --resource-group $RG \
  --workspace-name $WORKSPACE \
  --name default

# 3. Run Terraform
cd terraform
terraform init
terraform apply -auto-approve

# 4. Run the analyzer
cd ../code
pip install azure-identity azure-mgmt-securityinsight
python sentinel_analyzer.py
```

## Lessons Learned

- **KQL is powerful**: Sentinel's query language lets you correlate events across tables in seconds — `SigninLogs | join SecurityEvent on AccountName` is a single query.
- **Data connector costs add up**: Every GB ingested costs ~$2.46 on top of Log Analytics. Filter noisy sources before enabling.
- **Playbooks need permissions**: Logic Apps need explicit API connections and managed identity roles to take action (block user, update firewall).
- **Incident tuning takes time**: New analytics rules generate false positives. Tune thresholds and add entity exclusions over the first 2 weeks.
- **Free data sources first**: Azure Activity Log and Azure AD audit logs are free — enable these before paid sources.

## Code

See `code/sentinel_analyzer.py` — uses `azure-mgmt-securityinsight` to list incidents by severity, retrieve incident details, and list active analytics rules.

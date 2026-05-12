# Architecture — Project 8.5: Microsoft Sentinel SIEM

## ASCII Diagram

```
                        MICROSOFT SENTINEL ARCHITECTURE
                        ================================

  DATA SOURCES                    COLLECTION                    DETECTION
  ┌─────────────┐                ┌──────────────────┐          ┌──────────────────┐
  │ Azure AD    │──SigninLogs───▶│                  │          │ Analytics Rules  │
  │ (Identity)  │──AuditLogs────▶│  Log Analytics   │─KQL────▶│                  │
  └─────────────┘                │  Workspace       │  query  │ • Brute Force    │
                                 │                  │          │ • Impossible     │
  ┌─────────────┐                │  Tables:         │          │   Travel         │
  │ Azure       │──AzureActivity▶│  • SigninLogs    │          │ • Anomalous      │
  │ Activity    │                │  • AuditLogs     │          │   Login          │
  │ Log         │                │  • AzureActivity │          │ • Mass Download  │
  └─────────────┘                │  • SecurityEvent │          └────────┬─────────┘
                                 │  • Syslog        │                   │
  ┌─────────────┐                │  • CommonSecurity│                   │ Alert
  │ Azure       │──SecurityAlert▶│    Log           │                   ▼
  │ Defender    │                └──────────────────┘          ┌──────────────────┐
  └─────────────┘                                              │    INCIDENTS     │
                                                               │                  │
  ┌─────────────┐                                              │ • Severity: High │
  │ Windows     │──SecurityEvent▶                              │ • Entities:      │
  │ VMs         │                                              │   - IP: 1.2.3.4  │
  └─────────────┘                                              │   - User: john   │
                                                               │   - Host: vm-01  │
                                                               └────────┬─────────┘
                                                                        │
                                                                        │ Trigger
                                                                        ▼
  RESPONSE                                                     ┌──────────────────┐
  ┌─────────────────────────────────────────────────┐          │   PLAYBOOKS      │
  │ Logic App Playbook                              │◀─────────│  (Logic Apps)    │
  │                                                 │          └──────────────────┘
  │  1. Parse incident entities                     │
  │  2. Block IP in NSG / Firewall                  │
  │  3. Disable compromised user account            │
  │  4. Send Teams/Email notification               │
  │  5. Create ServiceNow/Jira ticket               │
  │  6. Update incident status → In Progress        │
  └─────────────────────────────────────────────────┘

  INVESTIGATION
  ┌─────────────────────────────────────────────────┐
  │ Sentinel Investigation Graph                    │
  │                                                 │
  │  IP 1.2.3.4 ──▶ User john@corp.com             │
  │       │              │                          │
  │       ▼              ▼                          │
  │  15 failed      Accessed                        │
  │  logins         SharePoint                      │
  │                 at 3am                          │
  └─────────────────────────────────────────────────┘
```

## Key Concepts

| Concept | Description | KQL Example |
|---|---|---|
| **Data Connector** | Plugin that routes logs from a source into Log Analytics | Azure AD → SigninLogs table |
| **Analytics Rule** | KQL query that runs on schedule and creates alerts | `SigninLogs \| where ResultType != "0" \| summarize count() > 10` |
| **Incident** | Grouped alerts representing a single attack scenario | Multiple brute force alerts → 1 incident |
| **Entity** | Extracted objects from alerts (IP, user, host, URL) | IP: 1.2.3.4, User: john@corp.com |
| **Playbook** | Logic App triggered by incident for automated response | Block IP, disable user, send email |
| **Hunting Query** | Proactive KQL query to find threats not yet alerted | Search for lateral movement patterns |
| **Watchlist** | CSV list of known-bad IPs/users for correlation | ThreatIntel IP blocklist |
| **UEBA** | User Entity Behavior Analytics — baseline + anomaly detection | Unusual login time/location |
| **Fusion** | ML-based correlation of low-fidelity signals into high-confidence incidents | Combines 5 weak signals → 1 strong incident |

## KQL Query Examples

```kql
// Brute force detection
SigninLogs
| where ResultType != "0"
| summarize FailedAttempts = count(), 
            Users = dcount(UserPrincipalName),
            FirstAttempt = min(TimeGenerated),
            LastAttempt = max(TimeGenerated)
  by IPAddress, bin(TimeGenerated, 5m)
| where FailedAttempts > 10
| project TimeGenerated, IPAddress, FailedAttempts, Users

// Impossible travel detection
SigninLogs
| where ResultType == "0"
| project TimeGenerated, UserPrincipalName, Location, IPAddress
| sort by UserPrincipalName, TimeGenerated asc
| extend PrevLocation = prev(Location), PrevTime = prev(TimeGenerated)
| where UserPrincipalName == prev(UserPrincipalName)
| extend TimeDiff = datetime_diff('minute', TimeGenerated, PrevTime)
| where Location != PrevLocation and TimeDiff < 60

// Top failed login IPs
SigninLogs
| where TimeGenerated > ago(24h)
| where ResultType != "0"
| summarize FailedLogins = count() by IPAddress
| top 10 by FailedLogins
```

## Data Flow Timing

```
Event occurs → Log Analytics ingestion: ~2-5 minutes
Analytics rule runs: every 5 minutes (configurable)
Incident created: within 1 minute of alert
Playbook triggered: within 2 minutes of incident
Total detection-to-response: ~10-15 minutes
```

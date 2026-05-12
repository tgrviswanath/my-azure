# Architecture — Project 8.6: Zero Trust Security on Azure

## ASCII Diagram

```
                         ZERO TRUST ARCHITECTURE
                         ========================

  IDENTITY PLANE (Who are you?)
  ┌─────────────────────────────────────────────────────────────────┐
  │                      Azure Active Directory                     │
  │                                                                 │
  │  User Login                Conditional Access Policy            │
  │  ┌──────────┐             ┌─────────────────────────────────┐  │
  │  │ User     │──request───▶│ Conditions:                     │  │
  │  │ + Device │             │  • User: All users              │  │
  │  └──────────┘             │  • App: Azure Management        │  │
  │                           │  • Location: Any                │  │
  │                           │  • Sign-in risk: Medium/High    │  │
  │                           │                                 │  │
  │                           │ Grant Controls:                 │  │
  │                           │  ✅ Require MFA                 │  │
  │                           │  ✅ Require compliant device    │  │
  │                           │  ✅ Require hybrid AD join      │  │
  │                           └─────────────────────────────────┘  │
  │                                                                 │
  │  PIM (Just-In-Time Access)                                      │
  │  ┌─────────────────────────────────────────────────────────┐   │
  │  │ Standing Access: NONE                                   │   │
  │  │ Eligible: Global Admin, Contributor (8hr max)           │   │
  │  │ Activation: Requires justification + approval           │   │
  │  └─────────────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────────────┘

  NETWORK PLANE (Where are you connecting from?)
  ┌─────────────────────────────────────────────────────────────────┐
  │  Virtual Network: 10.0.0.0/16                                   │
  │                                                                 │
  │  ┌──────────────────┐    ┌──────────────────────────────────┐  │
  │  │ App Subnet       │    │ Private Endpoint Subnet          │  │
  │  │ 10.0.1.0/24      │    │ 10.0.2.0/24                      │  │
  │  │                  │    │                                  │  │
  │  │ ┌─────────────┐  │    │ ┌──────────────────────────────┐ │  │
  │  │ │ App Service │──┼────┼▶│ Key Vault PE  (10.0.2.4)     │ │  │
  │  │ │ or VM       │  │    │ │ Storage PE   (10.0.2.5)      │ │  │
  │  │ └─────────────┘  │    │ │ SQL PE       (10.0.2.6)      │ │  │
  │  └──────────────────┘    │ └──────────────────────────────┘ │  │
  │                          └──────────────────────────────────┘  │
  │                                                                 │
  │  NSG Rules (Micro-segmentation):                                │
  │  • App → PE Subnet: ALLOW (443 only)                           │
  │  • Internet → App: DENY (use Application Gateway)              │
  │  • Any → Port 22/3389: DENY (use Azure Bastion)                │
  └─────────────────────────────────────────────────────────────────┘

  DATA PLANE (What can you access?)
  ┌─────────────────────────────────────────────────────────────────┐
  │                                                                 │
  │  Key Vault          Storage Account       Azure SQL             │
  │  ┌──────────┐       ┌──────────────┐     ┌──────────────┐     │
  │  │ Public   │       │ Public       │     │ Public       │     │
  │  │ Access:  │       │ Access:      │     │ Access:      │     │
  │  │ DISABLED │       │ DISABLED     │     │ DISABLED     │     │
  │  │          │       │              │     │              │     │
  │  │ Access   │       │ Firewall:    │     │ Firewall:    │     │
  │  │ via PE   │       │ VNet only    │     │ VNet only    │     │
  │  │ only     │       │              │     │              │     │
  │  └──────────┘       └──────────────┘     └──────────────┘     │
  │                                                                 │
  │  Private DNS Zones (resolve to private IPs):                   │
  │  • privatelink.vaultcore.azure.net → 10.0.2.4                  │
  │  • privatelink.blob.core.windows.net → 10.0.2.5                │
  │  • privatelink.database.windows.net → 10.0.2.6                 │
  └─────────────────────────────────────────────────────────────────┘

  MONITORING PLANE (What happened?)
  ┌─────────────────────────────────────────────────────────────────┐
  │  Defender for Cloud → Secure Score → Recommendations           │
  │  Sentinel → Incidents → Playbooks → Auto-remediation           │
  │  Azure Monitor → Alerts → Action Groups → Notifications        │
  └─────────────────────────────────────────────────────────────────┘
```

## Key Concepts

| Concept | Zero Trust Principle | Implementation |
|---|---|---|
| **Conditional Access** | Verify explicitly | MFA + device compliance + location check on every login |
| **PIM** | Use least privilege | No standing admin roles; JIT activation with time limit |
| **Private Endpoints** | Assume breach | Services unreachable from internet; VNet-only access |
| **Private DNS Zones** | Verify explicitly | DNS resolves to private IP, not public IP |
| **NSG Micro-segmentation** | Assume breach | Subnet-level firewall rules; deny all except required ports |
| **Defender for Cloud** | Assume breach | Continuous threat detection and Secure Score tracking |
| **Azure Bastion** | Least privilege | No public RDP/SSH; browser-based access via Azure portal |
| **Managed Identity** | Verify explicitly | Apps authenticate with Azure AD identity, no passwords |
| **RBAC** | Least privilege | Minimum required permissions per resource, not subscription-wide |

## Zero Trust Score Calculation

```
Score = (Passed Checks / Total Checks) × 100

Checks:
  Identity (30 points):
    [10] MFA enforced via Conditional Access
    [10] No users with standing Global Admin
    [10] Legacy authentication blocked

  Network (30 points):
    [10] No NSG rules allowing 0.0.0.0/0 on 22/3389
    [10] Key Vault has private endpoint
    [10] Storage accounts have no public access

  Data (20 points):
    [10] All disks encrypted
    [10] Key Vault used for secrets (no hardcoded creds)

  Monitoring (20 points):
    [10] Defender for Cloud enabled
    [10] Sentinel connected and rules active
```

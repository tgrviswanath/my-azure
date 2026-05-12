# Project 8.6 — Zero Trust Security on Azure

## What This Does

Implements Zero Trust security architecture on Azure: "Never trust, always verify." This project replaces implicit network trust (VPN-based perimeter) with identity-based access control, eliminates public endpoints using Private Endpoints, enforces MFA via Conditional Access, and implements Just-In-Time privileged access with PIM. Includes an automated audit script that scores your Zero Trust posture 0–100.

## Services Used

| Service | Purpose | SKU |
|---|---|---|
| Azure AD Conditional Access | Enforce MFA, device compliance, location policies | Azure AD P2 |
| Azure AD PIM | Just-In-Time privileged access (no standing admin) | Azure AD P2 |
| Azure Private Endpoints | Replace public service endpoints with private IPs | Standard |
| Azure Private DNS Zones | DNS resolution for private endpoints | Pay-per-zone |
| Microsoft Defender for Cloud | Threat protection + Secure Score | Standard |
| Azure Key Vault | Secrets management with private endpoint | Standard |
| Azure Virtual Network | Network isolation | Free |
| Network Security Groups | Micro-segmentation | Free |

## Architecture

```
ZERO TRUST: NEVER TRUST, ALWAYS VERIFY
=======================================

  OLD MODEL (Perimeter-based):
  Internet → Firewall → VPN → "Trusted" Internal Network → Resources
  Problem: Once inside VPN, lateral movement is easy

  NEW MODEL (Zero Trust):
  Every Request → Identity Verification → Device Check → Policy Evaluation → Resource

  ┌─────────────────────────────────────────────────────────────────┐
  │                    ZERO TRUST CONTROL PLANE                    │
  │                                                                 │
  │  User/Device          Azure AD              Policy Engine       │
  │  ┌─────────┐         ┌──────────┐          ┌──────────────┐   │
  │  │ User    │──auth──▶│ Cond.    │──allow──▶│ Resource     │   │
  │  │ + MFA   │         │ Access   │          │ (Key Vault,  │   │
  │  │ + Comp. │         │ Policy   │          │  Storage,    │   │
  │  │   Device│         └──────────┘          │  SQL, etc.)  │   │
  │  └─────────┘                               └──────────────┘   │
  │                                                                 │
  │  DATA PLANE: Private Endpoints (no public internet access)     │
  │  ┌──────────────────────────────────────────────────────────┐  │
  │  │ VNet (10.0.0.0/16)                                       │  │
  │  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │  │
  │  │  │ App Subnet  │    │ PE Subnet   │    │ Mgmt Subnet │  │  │
  │  │  │ 10.0.1.0/24 │    │ 10.0.2.0/24 │    │ 10.0.3.0/24 │  │  │
  │  │  └─────────────┘    └──────┬──────┘    └─────────────┘  │  │
  │  │                            │                              │  │
  │  │                    Private Endpoints                      │  │
  │  │                    ┌───────┴──────┐                       │  │
  │  │                    │ Key Vault PE │ 10.0.2.4              │  │
  │  │                    │ Storage PE   │ 10.0.2.5              │  │
  │  │                    │ SQL PE       │ 10.0.2.6              │  │
  │  │                    └──────────────┘                       │  │
  │  └──────────────────────────────────────────────────────────┘  │
  └─────────────────────────────────────────────────────────────────┘
```

## How to Run

### Prerequisites
```bash
az login
export RG="rg-zero-trust-lab"
export LOCATION="eastus"
```

### Deploy
```bash
# Create infrastructure
cd terraform
terraform init
terraform apply -auto-approve

# Run Zero Trust audit
cd ../code
pip install azure-identity azure-mgmt-network azure-mgmt-storage azure-mgmt-keyvault
python zero_trust_checker.py
```

### Expected Output
```
Zero Trust Score: 72/100
Findings:
  ✅ MFA enforced via Conditional Access
  ✅ Key Vault has private endpoint
  ❌ Storage account 'stdata001' has public access enabled
  ❌ NSG 'nsg-app' allows 0.0.0.0/0 on port 22
  ⚠️  3 users have standing Global Admin role (use PIM)
```

## Lessons Learned

- **Private Endpoints break DNS**: After creating a PE, you must also create a Private DNS Zone and link it to your VNet, or DNS still resolves to the public IP.
- **Conditional Access needs P2**: Basic MFA enforcement needs Azure AD P1. Risk-based CA (sign-in risk, user risk) requires P2.
- **PIM activation takes time**: JIT access has an approval workflow. Build this into your runbooks — don't wait until an incident to test it.
- **Secure Score is a lagging indicator**: It takes 24-48 hours to reflect changes. Don't expect immediate feedback.
- **NSG rules compound**: Multiple NSGs (subnet + NIC level) can conflict. Use Network Watcher's IP flow verify to debug.

## Code

See `code/zero_trust_checker.py` — audits your Azure environment and produces a Zero Trust score 0–100 with specific findings and remediation steps.

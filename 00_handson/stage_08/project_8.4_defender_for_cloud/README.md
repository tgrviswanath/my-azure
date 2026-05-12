# Project 8.4 — Microsoft Defender for Cloud

## What This Does
Enables Microsoft Defender for Cloud to improve security posture, detect threats, and get vulnerability assessments across Azure resources.

## Services Used
| Service | Purpose |
|---------|---------|
| Defender for Cloud | Security posture management + threat protection |
| Security Score | Measure and track security posture |
| Recommendations | Actionable security improvements |
| Security Alerts | Real-time threat detection |

## Architecture
```
Azure Resources
    │ continuous assessment
    ▼
Defender for Cloud
    ├── Security Score (0-100)
    ├── Recommendations (prioritized by impact)
    ├── Security Alerts (threat detection)
    └── Regulatory Compliance (CIS, PCI-DSS, ISO 27001)
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve
python code/security_monitor.py
```

## Lessons Learned
- Free tier: basic recommendations + security score (no cost)
- Defender plans: per-resource pricing (~$15/server/month)
- Enable Defender for Servers for VM vulnerability assessment
- Security Score: track improvement over time

## Code

### `code/security_monitor.py` — Fetch security alerts and recommendations

```bash
pip install azure-identity azure-mgmt-security
python code/security_monitor.py
python code/security_monitor.py --severity HIGH
```

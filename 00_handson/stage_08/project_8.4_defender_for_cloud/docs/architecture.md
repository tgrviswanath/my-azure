# Architecture — Project 8.4 Microsoft Defender for Cloud

## Diagram

```
Azure Resources (VMs, SQL, Storage, AKS, etc.)
    │ continuous assessment
    ▼
Microsoft Defender for Cloud
    │
    ├── CSPM (Cloud Security Posture Management)
    │     ├── Security Score (0-100)
    │     ├── Recommendations (prioritized)
    │     └── Regulatory Compliance (CIS, PCI-DSS)
    │
    ├── CWP (Cloud Workload Protection)
    │     ├── Defender for Servers (EDR, vulnerability scan)
    │     ├── Defender for SQL (SQL injection detection)
    │     ├── Defender for Storage (malware scan)
    │     └── Defender for Containers (AKS threat detection)
    │
    └── Security Alerts
          │ real-time threat detection
          ▼
    Action Group → Email / SIEM / Logic App
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Security Score | 0-100 score based on implemented recommendations |
| CSPM | Assess and improve security posture |
| CWP | Runtime threat protection for workloads |
| Just-in-Time VM Access | Open VM ports only when needed |

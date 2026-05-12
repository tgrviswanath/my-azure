# Architecture — Project 8.2 WAF Application Protection

## Diagram

```
Internet
    │ HTTP/HTTPS
    ▼
Application Gateway WAF v2
    │
    ├── WAF Policy (Prevention mode)
    │     ├── OWASP 3.2 Core Rule Set
    │     │     ├── SQL Injection rules
    │     │     ├── XSS rules
    │     │     ├── LFI/RFI rules
    │     │     └── Protocol enforcement
    │     │
    │     ├── Bot Manager ruleset
    │     │     ├── Known bad bots blocked
    │     │     └── Good bots allowed (Googlebot, etc.)
    │     │
    │     └── Custom rules
    │           ├── IP allow/block lists
    │           └── Rate limiting
    │
    ├── PASS → Backend Pool (App Service / AKS)
    │
    └── BLOCK → 403 Forbidden
          │
          ▼
    WAF Logs → Log Analytics → KQL queries → Alerts
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Prevention mode | Blocks malicious requests (production) |
| Detection mode | Logs only — use for tuning before Prevention |
| OWASP 3.2 | Open Web Application Security Project ruleset |
| Custom rules | IP-based, geo-based, rate limiting |
| WAF exclusions | Exclude specific rules for false positives |

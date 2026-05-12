# Project 8.2 — WAF Application Protection

## What This Does
Deploys Azure Application Gateway with WAF v2 to protect web applications against SQL injection, XSS, and bot attacks.

## Services Used
| Service | Purpose |
|---------|---------|
| Application Gateway WAF v2 | Layer 7 load balancer + Web Application Firewall |
| WAF Policy | OWASP 3.2 ruleset + custom rules |
| Log Analytics | WAF log analysis |

## Architecture
```
Internet
    │ HTTPS
    ▼
Application Gateway WAF v2
    ├── WAF Policy (Prevention mode)
    │     ├── OWASP 3.2 Core Rule Set
    │     ├── Bot Manager ruleset
    │     └── Custom rules (IP allow/block lists)
    ▼
Backend Pool (App Service / AKS)
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve
python code/waf_tester.py --url https://$(terraform output -raw app_gateway_ip)
```

## Lessons Learned
- WAF Prevention mode: blocks malicious requests. Detection mode: logs only
- OWASP 3.2 ruleset covers top 10 web vulnerabilities
- Custom rules: IP-based allow/block lists, rate limiting
- WAF logs go to Log Analytics — query with KQL for analysis

## Code

### `code/waf_tester.py` — Test WAF rules

```bash
pip install requests
python code/waf_tester.py --url https://your-app-gateway-ip
```

# Steps — Project 8.2 WAF Application Protection

## Phase 1 — Deploy Application Gateway WAF

```bash
cd terraform && terraform init && terraform apply -auto-approve
APP_GW_IP=$(terraform output -raw app_gateway_ip)
echo "App Gateway IP: $APP_GW_IP"
```

---

## Phase 2 — Configure WAF Policy (Prevention Mode)

```bash
# Create WAF policy
az network application-gateway waf-policy create \
  --name waf-policy-handson \
  --resource-group rg-waf \
  --type OWASP \
  --version 3.2

# Set to Prevention mode
az network application-gateway waf-policy policy-setting update \
  --policy-name waf-policy-handson \
  --resource-group rg-waf \
  --mode Prevention \
  --state Enabled
```

---

## Phase 3 — Test SQL Injection Blocked

```bash
# Legitimate request — should return 200
curl -s -o /dev/null -w "%{http_code}" http://$APP_GW_IP/

# SQL injection — should return 403
curl -s -o /dev/null -w "%{http_code}" "http://$APP_GW_IP/?id=1' OR '1'='1"

# XSS — should return 403
curl -s -o /dev/null -w "%{http_code}" "http://$APP_GW_IP/?q=<script>alert(1)</script>"
```

---

## Phase 4 — Review WAF Logs

```bash
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group rg-waf \
  --workspace-name law-waf \
  --query customerId -o tsv)

# Query WAF blocked requests
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "AzureDiagnostics | where Category == 'ApplicationGatewayFirewallLog' | where action_s == 'Blocked' | project TimeGenerated, clientIP_s, requestUri_s, ruleId_s | order by TimeGenerated desc | take 20"
```

---

## Phase 5 — Add Custom Rule (IP Block)

```bash
az network application-gateway waf-policy custom-rule create \
  --policy-name waf-policy-handson \
  --resource-group rg-waf \
  --name BlockBadIP \
  --priority 10 \
  --rule-type MatchRule \
  --action Block \
  --match-conditions '[{"matchVariables":[{"variableName":"RemoteAddr"}],"operator":"IPMatch","matchValues":["1.2.3.4/32"]}]'
```

---

## Screenshots to Take
- [ ] WAF policy in Prevention mode
- [ ] SQL injection request blocked (403)
- [ ] WAF logs showing blocked requests
- [ ] Custom rule blocking specific IP

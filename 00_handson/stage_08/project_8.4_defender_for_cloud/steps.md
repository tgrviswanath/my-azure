# Steps — Project 8.4 Microsoft Defender for Cloud

## Phase 1 — Enable Defender Plans

```bash
# Enable Defender for Servers (Plan 2)
az security pricing create --name VirtualMachines --tier Standard

# Enable Defender for SQL
az security pricing create --name SqlServers --tier Standard

# Enable Defender for Storage
az security pricing create --name StorageAccounts --tier Standard
```

---

## Phase 2 — Review Security Score

```bash
az security secure-score list --output table
az security secure-score-controls list --output table
```

---

## Phase 3 — Remediate Recommendations

```bash
# List high-severity recommendations
az security assessment list \
  --query "[?status.code=='Unhealthy']" \
  --output table
```

---

## Phase 4 — Configure Security Contact

```bash
az security contact create \
  --name default \
  --email security@example.com \
  --phone "+1-555-0100" \
  --alert-notifications On \
  --alerts-to-admins On
```

---

## Phase 5 — Review Threat Protection

```
Azure Portal → Defender for Cloud → Security Alerts
- View active alerts
- Investigate alert details
- Dismiss false positives
```

---

## Screenshots to Take
- [ ] Security Score dashboard
- [ ] Top recommendations by impact
- [ ] Security alerts list
- [ ] Regulatory compliance dashboard

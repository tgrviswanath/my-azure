# Steps — Project 7.5 Grafana + Prometheus Monitoring

## Phase 1 — Enable Azure Monitor for AKS

```bash
# Enable Azure Monitor metrics addon on existing AKS cluster
az aks update \
  --resource-group rg-aks \
  --name aks-handson \
  --enable-azure-monitor-metrics \
  --azure-monitor-workspace-resource-id /subscriptions/<sub>/resourceGroups/rg-monitoring/providers/microsoft.monitor/accounts/prometheus-handson
```

---

## Phase 2 — Deploy Azure Managed Prometheus

```bash
cd terraform && terraform init && terraform apply -auto-approve

# Verify Prometheus is scraping
kubectl get pods -n kube-system | grep ama-metrics
```

---

## Phase 3 — Access Managed Grafana

```bash
# Get Grafana endpoint
GRAFANA_URL=$(terraform output -raw grafana_endpoint)
echo "Grafana: https://$GRAFANA_URL"

# Open in browser — login with Azure AD
```

---

## Phase 4 — Import Kubernetes Dashboards

```
1. Grafana UI → Dashboards → Import
2. Import dashboard ID 15760 (Kubernetes cluster overview)
3. Import dashboard ID 14205 (Kubernetes pod monitoring)
4. Select Azure Monitor data source
```

---

## Phase 5 — Create Alerts

```bash
# Create alert rule in Grafana UI:
# Alerting → Alert rules → New alert rule
# Query: rate(http_requests_total{status=~"5.."}[5m]) > 0.01
# Condition: IS ABOVE 0.01
# Notification: contact point (email/Teams)
```

---

## Screenshots to Take
- [ ] Grafana dashboard showing AKS cluster metrics
- [ ] Prometheus targets page showing scraped pods
- [ ] RED method dashboard (rate, errors, duration)
- [ ] Alert firing and notification received

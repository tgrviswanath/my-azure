# Steps — Project 10.5 Production-grade Microservices Platform

## Phase 1 — Deploy AKS + API Management

```bash
cd terraform && terraform init && terraform apply -auto-approve

# Get AKS credentials
az aks get-credentials --resource-group rg-platform --name aks-platform

# Verify APIM is running
az apim show --name apim-platform-001 --resource-group rg-platform --query "provisioningState"
```

---

## Phase 2 — Deploy Microservices

```bash
# Deploy all services
kubectl apply -f k8s/

# Check all pods are running
kubectl get pods -n platform

# Verify services
kubectl get svc -n platform
```

---

## Phase 3 — Configure Event Hubs

```bash
# Create Event Hubs namespace and hub
az eventhubs namespace create \
  --name evhns-platform-001 \
  --resource-group rg-platform \
  --sku Standard

az eventhubs eventhub create \
  --name orders-events \
  --namespace-name evhns-platform-001 \
  --resource-group rg-platform \
  --partition-count 4
```

---

## Phase 4 — Add Redis Cache

```bash
# Verify Redis is accessible from AKS
kubectl run redis-test --image=redis --rm -it -- \
  redis-cli -h redis-platform-001.redis.cache.windows.net -p 6380 --tls ping
```

---

## Phase 5 — Enable Monitoring + Security

```bash
# Enable Application Insights on all services
kubectl set env deployment/order-service \
  APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=xxx" \
  -n platform

# Verify Defender for Cloud is enabled
az security pricing list --query "[?pricingTier=='Standard']" --output table
```

---

## Screenshots to Take
- [ ] All microservices running in AKS
- [ ] API Management showing all APIs
- [ ] Event Hubs receiving order events
- [ ] Application Insights showing distributed traces
- [ ] Grafana dashboard showing platform health

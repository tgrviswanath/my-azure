# Steps — Project 10.4 Kubernetes on AKS

## Phase 1 — Deploy AKS Cluster

```bash
cd terraform && terraform init && terraform apply -auto-approve

# Get credentials
az aks get-credentials \
  --resource-group rg-aks-prod \
  --name aks-handson \
  --overwrite-existing

kubectl get nodes
kubectl get nodes -o wide
```

---

## Phase 2 — Deploy Application

```bash
# Create namespace
kubectl create namespace handson

# Apply manifests
kubectl apply -f k8s/deployment.yaml

# Check status
kubectl get pods -n handson
kubectl get svc -n handson
kubectl get ingress -n handson
```

---

## Phase 3 — Configure Ingress

```bash
# Get Application Gateway public IP
kubectl get ingress -n handson -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'

# Test the endpoint
curl http://<ingress-ip>/health
curl http://<ingress-ip>/api/orders
```

---

## Phase 4 — Set Up HPA

```bash
# Apply HPA
kubectl apply -f k8s/deployment.yaml

# Check HPA status
kubectl get hpa -n handson

# Generate load to trigger scaling
kubectl run load-test --image=busybox --rm -it -- \
  sh -c "while true; do wget -q -O- http://handson-api/api/orders; done"

# Watch pods scale
kubectl get pods -n handson -w
```

---

## Phase 5 — Test Autoscaling

```bash
# Watch HPA metrics
kubectl describe hpa handson-api -n handson

# Check node autoscaler
kubectl get nodes -w

# Clean up load test
kubectl delete pod load-test
```

---

## Screenshots to Take
- [ ] AKS cluster with system + user node pools
- [ ] Pods running in handson namespace
- [ ] Ingress with Application Gateway IP
- [ ] HPA scaling pods under load

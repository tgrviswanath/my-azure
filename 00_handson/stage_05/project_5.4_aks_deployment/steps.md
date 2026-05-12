# Steps — Project 5.4 AKS Deployment

## Phase 1 — Create AKS Cluster
```bash
cd terraform && terraform init && terraform apply -auto-approve
az aks get-credentials --resource-group rg-aks --name aks-handson
kubectl get nodes
```

## Phase 2 — Deploy App
```bash
kubectl apply -f k8s/deployment.yaml
kubectl get pods -w
kubectl get svc
```

## Phase 3 — Scale and Monitor
```bash
kubectl scale deployment myapp --replicas=4
kubectl top pods
kubectl describe hpa myapp-hpa
```

## Phase 4 — Cleanup (saves cost)
```bash
terraform destroy -auto-approve
```

## Screenshots to Take
- [ ] AKS nodes running
- [ ] Pods deployed and healthy
- [ ] HPA configured

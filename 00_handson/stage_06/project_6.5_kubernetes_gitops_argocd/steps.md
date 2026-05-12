# Steps — Project 6.5 Kubernetes GitOps with ArgoCD

## Phase 1 — Deploy AKS

```bash
cd terraform && terraform init && terraform apply -auto-approve

# Get credentials
az aks get-credentials \
  --resource-group rg-gitops \
  --name aks-gitops \
  --overwrite-existing

kubectl get nodes
```

---

## Phase 2 — Install ArgoCD

```bash
kubectl create namespace argocd

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# Get initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
```

---

## Phase 3 — Access ArgoCD UI

```bash
# Port-forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login via CLI
argocd login localhost:8080 --username admin --password <password> --insecure

# Change password
argocd account update-password
```

---

## Phase 4 — Deploy Application via GitOps

```bash
# Apply the ArgoCD Application manifest
kubectl apply -f argocd/application.yaml

# Watch sync
argocd app get handson-app
argocd app sync handson-app

# Check pods
kubectl get pods -n handson
```

---

## Phase 5 — Test GitOps Loop

```bash
# Make a change to k8s/base/deployment.yaml (e.g. change replicas)
git add k8s/base/deployment.yaml
git commit -m "feat: scale to 3 replicas"
git push

# ArgoCD detects change within 3 minutes (or trigger webhook)
argocd app get handson-app --watch
```

---

## Screenshots to Take
- [ ] ArgoCD UI showing app in sync
- [ ] Git push triggering automatic sync
- [ ] ArgoCD showing diff before sync
- [ ] Rollback to previous version

# Project 6.5 — Kubernetes GitOps with ArgoCD

## What This Does
Implements GitOps on AKS using ArgoCD. Git is the single source of truth — ArgoCD continuously syncs the cluster state to match what's in the repository.

## Services Used
| Service | Purpose |
|---------|---------|
| AKS | Kubernetes cluster |
| ArgoCD | GitOps controller |
| Azure Container Registry | Container image storage |
| GitHub | Git repository (source of truth) |

## Architecture
```
Developer pushes k8s manifests to Git
    │
    ▼
ArgoCD (running in AKS)
    │ polls Git every 3 minutes (or webhook)
    ▼
Detects drift between Git and cluster
    │
    ▼
Syncs cluster to match Git state
    │
    ▼
Pods updated, services configured
```

## How to Run
```bash
# Deploy AKS + install ArgoCD
cd terraform && terraform init && terraform apply -auto-approve

# Get AKS credentials
az aks get-credentials --resource-group rg-gitops --name aks-gitops

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080

# Apply ArgoCD Application
kubectl apply -f argocd/application.yaml
```

## Lessons Learned
- GitOps: cluster state is always derived from Git — no manual kubectl apply
- ArgoCD auto-sync: detects and corrects drift automatically
- Kustomize overlays: manage dev/qa/prod differences without duplication
- ArgoCD RBAC: control who can sync/delete applications

## Code

### `argocd/application.yaml` — ArgoCD Application manifest
### `k8s/base/deployment.yaml` — Kubernetes base manifests

```bash
# Watch sync status
argocd app get handson-app
argocd app sync handson-app
argocd app history handson-app
```

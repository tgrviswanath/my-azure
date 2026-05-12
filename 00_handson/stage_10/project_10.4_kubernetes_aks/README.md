# Project 10.4 — Kubernetes on AKS

## What This Does
Deploys a production-grade AKS cluster with system and user node pools, Application Gateway Ingress Controller (AGIC), HPA, and workload identity.

## Services Used
| Service | Purpose |
|---------|---------|
| AKS | Managed Kubernetes cluster |
| Application Gateway | Ingress controller (AGIC) |
| Azure Container Registry | Container image storage |
| Workload Identity | Pods authenticate to Azure without secrets |

## Architecture
```
Internet → Application Gateway (AGIC)
    │ path-based routing
    ▼
AKS Cluster
    ├── System node pool (Standard_D2s_v3 x1)
    │     └── kube-system, monitoring pods
    └── User node pool (Standard_D2s_v3 x2)
          └── handson namespace
                ├── Deployment (3 replicas)
                ├── Service (ClusterIP)
                ├── Ingress (AGIC)
                └── HPA (CPU-based, 2-10 replicas)
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve
az aks get-credentials --resource-group rg-aks-prod --name aks-handson
kubectl apply -f k8s/deployment.yaml
kubectl get pods -n handson
```

## Lessons Learned
- System node pool: reserved for Kubernetes system pods — don't run workloads here
- User node pool: for application workloads — can scale to 0
- AGIC: Application Gateway Ingress Controller — native Azure integration
- HPA: scales pods based on CPU/memory — set requests correctly
- Workload Identity: pods get Azure AD identity — no stored credentials

## Code

### `k8s/deployment.yaml` — Kubernetes manifests

```bash
kubectl apply -f k8s/deployment.yaml
kubectl get pods,svc,ingress,hpa -n handson
kubectl top pods -n handson
```

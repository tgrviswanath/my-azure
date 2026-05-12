# Project 5.4 — AKS Deployment

## What This Does
Deploys a containerized application to Azure Kubernetes Service (AKS) with Application Gateway ingress, Managed Identity for ACR access, and HPA for autoscaling.

## Services Used
| Service | Purpose |
|---------|---------|
| AKS | Managed Kubernetes cluster |
| Application Gateway | Layer 7 ingress controller (AGIC) |
| Azure Container Registry | Container image source |
| Managed Identity | AKS pulls from ACR without credentials |

## Architecture
```
Internet → Application Gateway (AGIC)
    │ path-based routing
    ▼
AKS Cluster (aks-handson)
    └── default namespace
          ├── Deployment: myapp (2 replicas)
          ├── Service: myapp (ClusterIP)
          └── Ingress: myapp (AGIC → App Gateway)
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve

# Get credentials
az aks get-credentials --resource-group rg-aks --name aks-handson

# Deploy application
kubectl apply -f k8s/

# Check status
kubectl get pods,svc,ingress

# Deploy new image
python code/aks_deploy.py deploy --image acrhandson001.azurecr.io/myapp:v2.0
```

## Lessons Learned
- AKS Managed Identity pulls from ACR without credentials — use `AcrPull` role
- Use HPA (Horizontal Pod Autoscaler) for CPU-based autoscaling
- Namespaces isolate workloads within the cluster
- AGIC: Application Gateway Ingress Controller — native Azure integration
- Set resource requests/limits on all containers — required for HPA

## Code

### `code/aks_deploy.py` — Deploy, check status, rollback

```bash
pip install azure-identity azure-mgmt-containerservice

# Deploy new image
python code/aks_deploy.py deploy --image acrhandson001.azurecr.io/myapp:v2.0

# Check deployment status
python code/aks_deploy.py status

# Rollback to previous version
python code/aks_deploy.py rollout --image acrhandson001.azurecr.io/myapp:v1.0
```

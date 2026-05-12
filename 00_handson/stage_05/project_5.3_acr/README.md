# Project 5.3 — Push Containers to Azure Container Registry

## What This Does
Creates Azure Container Registry (ACR) and pushes Docker images to it. ACR is the private container registry for Azure — integrates natively with AKS, Container Apps, and Azure DevOps.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure Container Registry | Private Docker image registry |
| ACR Tasks | Cloud-based image builds (no local Docker needed) |
| Managed Identity | AKS pulls images without stored credentials |

## Architecture
```
Developer
    │ docker build + push (or ACR Tasks)
    ▼
Azure Container Registry (acrhandson001.azurecr.io)
    ├── myapp:v1.0
    ├── myapp:v2.0
    └── myapp:latest
          │ AcrPull (Managed Identity)
          ▼
    AKS / Container Apps
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve

# Option A: Build locally and push
az acr login --name acrhandson001
docker build -t acrhandson001.azurecr.io/myapp:v1.0 .
docker push acrhandson001.azurecr.io/myapp:v1.0

# Option B: Build in ACR cloud (no local Docker needed)
az acr build --registry acrhandson001 --image myapp:v1.0 .

# Manage images
python code/acr_manager.py list  --registry acrhandson001
python code/acr_manager.py clean --registry acrhandson001 --repo myapp --keep 5
```

## Lessons Learned
- ACR integrates natively with AKS via Managed Identity — no credentials needed
- ACR Tasks: build images in the cloud — no Docker Desktop required
- Enable geo-replication for multi-region deployments (Premium SKU)
- Use content trust for image signing in production
- Vulnerability scanning: enable Microsoft Defender for Containers

## Code

### `code/acr_manager.py` — Build, push, list, and clean ACR images

```bash
pip install azure-identity azure-mgmt-containerregistry

# Push image
python code/acr_manager.py push  --registry acrhandson001 --repo myapp --tag v1.0

# Build in cloud (no local Docker)
python code/acr_manager.py build --registry acrhandson001 --repo myapp --tag v1.0 --context .

# List all tags
python code/acr_manager.py list  --registry acrhandson001 --repo myapp

# Delete old tags, keep 5 most recent
python code/acr_manager.py clean --registry acrhandson001 --repo myapp --keep 5
```

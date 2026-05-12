# Project 5.6 — Azure Container Apps Deployment

## What This Does
Deploys a containerized application to Azure Container Apps — serverless Kubernetes without managing clusters. Scales to zero when idle, scales out automatically under load.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure Container Apps | Serverless container hosting |
| Container Apps Environment | Shared networking + Log Analytics |
| Azure Container Registry | Container image source |
| Log Analytics | Container logs and metrics |

## Architecture
```
Internet → Container Apps Environment
    │ HTTPS (automatic TLS)
    ▼
Container App: ca-myapp
    ├── Revision: latest (active)
    ├── Scale: 0 → 10 replicas (HTTP-based)
    ├── CPU: 0.25 vCPU | Memory: 0.5Gi
    └── Image: acrhandson001.azurecr.io/myapp:v1.0
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve

# Get app URL
terraform output app_url

# Deploy new version
python code/container_apps_deploy.py deploy \
  --app ca-myapp \
  --image acrhandson001.azurecr.io/myapp:v2.0

# Check status
python code/container_apps_deploy.py status --app ca-myapp
```

## Lessons Learned
- Container Apps = serverless AKS — no cluster management, no node pools
- Scales to zero by default — no idle cost (unlike AKS)
- Built-in Dapr support for microservices patterns (service discovery, pub/sub)
- Revisions: each deployment creates a new revision — easy rollback
- Use for simple containerized workloads; use AKS for complex orchestration

## Code

### `code/container_apps_deploy.py` — Deploy and manage Container Apps

```bash
pip install azure-identity azure-mgmt-appcontainers

# Deploy new image
python code/container_apps_deploy.py deploy --app ca-myapp --image acrhandson001.azurecr.io/myapp:v2.0

# Check status
python code/container_apps_deploy.py status --app ca-myapp

# Get URL
python code/container_apps_deploy.py url --app ca-myapp
```

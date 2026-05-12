# Project 6.1 — GitHub Actions CI/CD Pipeline Deploying to AKS

## What This Does

Builds a complete CI/CD pipeline using GitHub Actions that automatically builds a Docker image, pushes it to Azure Container Registry (ACR), and deploys it to Azure Kubernetes Service (AKS) on every push to the main branch. Includes automated testing, image scanning, and rollback capability.

## Services Used

| Service | SKU / Tier | Purpose |
|---|---|---|
| GitHub Actions | Free (2000 min/month public) | CI/CD orchestration |
| Azure Container Registry | Basic | Docker image storage |
| Azure Kubernetes Service | Standard (1 node pool) | Container orchestration |
| Azure AD Service Principal | — | GitHub → Azure authentication |
| Azure Resource Group | — | Logical container |

## Architecture

```
Developer pushes to GitHub
         │
         ▼
  GitHub Actions Workflow
  ┌──────────────────────────────────────────────────────┐
  │  Job: build-and-push                                 │
  │    1. Checkout code                                  │
  │    2. Run unit tests                                 │
  │    3. docker build -t myapp:$SHA .                   │
  │    4. docker push → Azure Container Registry (ACR)  │
  │                                                      │
  │  Job: deploy (needs: build-and-push)                 │
  │    5. az aks get-credentials                         │
  │    6. kubectl set image deployment/myapp ...         │
  │    7. kubectl rollout status deployment/myapp        │
  └──────────────────────────────────────────────────────┘
         │
         ▼
  Azure Container Registry
  myacr.azurecr.io/myapp:abc1234
         │
         ▼
  Azure Kubernetes Service
  Deployment → ReplicaSet → Pods (running new image)
         │
         ▼
  LoadBalancer Service → External IP → Users
```

## How to Run

```bash
# 1. Deploy ACR + AKS via Terraform
cd terraform
terraform init
terraform apply -auto-approve

# 2. Create service principal with AcrPush + AKS deploy permissions
ACR_ID=$(terraform output -raw acr_id)
AKS_ID=$(terraform output -raw aks_id)

az ad sp create-for-rbac \
  --name "sp-github-actions-proj61" \
  --role "AcrPush" \
  --scopes $ACR_ID \
  --sdk-auth > sp_credentials.json

# Also grant AKS cluster access
SP_ID=$(cat sp_credentials.json | jq -r .clientId)
az role assignment create \
  --assignee $SP_ID \
  --role "Azure Kubernetes Service Cluster User Role" \
  --scope $AKS_ID

# 3. Add GitHub repository secrets
#    AZURE_CREDENTIALS  → contents of sp_credentials.json
#    ACR_LOGIN_SERVER   → $(terraform output -raw acr_login_server)
#    AKS_CLUSTER_NAME   → $(terraform output -raw aks_cluster_name)
#    AKS_RESOURCE_GROUP → $(terraform output -raw resource_group_name)

# 4. Push the workflow file to .github/workflows/deploy.yml
#    (see code/deploy.yml)

# 5. Push a code change to trigger the pipeline
git add .
git commit -m "trigger CI/CD pipeline"
git push origin main

# 6. Monitor the pipeline
gh run watch

# 7. Verify deployment
cd ../code
python deploy_check.py
```

## Lessons Learned

- The `AcrPull` role must be assigned to the AKS kubelet identity (not the control plane SP) so nodes can pull images from ACR without storing credentials in Kubernetes secrets.
- Using `${{ github.sha }}` as the image tag ensures every build is uniquely tagged and rollbacks are trivial (`kubectl rollout undo`).
- `kubectl rollout status` blocks the workflow until the deployment is healthy — if pods crash, the step fails and GitHub marks the run as failed.
- Separating build and deploy into distinct jobs allows re-running only the deploy job if infrastructure was the issue.
- Store `AZURE_CREDENTIALS` as a GitHub secret, never in the repository. Rotate the SP secret every 90 days.

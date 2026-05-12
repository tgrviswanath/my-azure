# Project 6.4 — Multi-subscription CI/CD Pipeline

## What This Does
Deploys workloads across multiple Azure subscriptions from a single GitHub Actions pipeline. Uses OIDC federated credentials per subscription — no stored secrets.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure AD App Registrations | One per subscription/environment |
| Federated Identity Credentials | OIDC trust per subscription |
| GitHub Actions | Matrix pipeline across subscriptions |
| AKS / App Service | Target deployment resources |

## Architecture
```
GitHub Actions (matrix strategy)
    ├── env: dev  → OIDC → Dev Subscription   → deploy
    ├── env: qa   → OIDC → QA Subscription    → deploy
    └── env: prod → OIDC → Prod Subscription  → deploy (with approval)
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve
# Creates App Registrations + federated credentials per subscription
```

## Lessons Learned
- Use GitHub Environments for per-environment secrets and approval gates
- Matrix strategy deploys to all subscriptions in parallel
- Each subscription gets its own App Registration — least privilege
- Use `azure/login@v2` with environment-specific secrets

## Code

### `code/cross_subscription_deploy.py` — Deploy to target subscription

```bash
pip install azure-identity azure-mgmt-resource
python code/cross_subscription_deploy.py --subscription-id <id> --resource-group rg-app
```

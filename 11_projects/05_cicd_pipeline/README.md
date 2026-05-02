# Project 05 — CI/CD Pipeline Setup

## Architecture
```
Developer → GitHub/Azure Repos
                ↓
         Azure Pipelines / GitHub Actions
         ├── Build Stage:
         │   ├── Install dependencies
         │   ├── Run unit tests
         │   ├── Code coverage check (>80%)
         │   ├── Security scan (Snyk/Trivy)
         │   ├── Build Docker image
         │   └── Push to ACR
         ├── Deploy Staging:
         │   ├── Deploy to staging slot
         │   ├── Run integration tests
         │   └── Smoke tests
         └── Deploy Production:
             ├── Manual approval gate
             ├── Swap staging → production
             ├── Health check
             └── Rollback on failure
```

## Pipeline Features
- **Branch strategy**: main → production, develop → staging, feature/* → PR
- **Quality gates**: tests, coverage, security scan must pass
- **Zero-downtime**: deployment slots + swap
- **Automatic rollback**: health check failure triggers swap back
- **Notifications**: Teams/Slack on success/failure
- **Audit trail**: all deployments logged with who/when/what

## Files
- `azure-pipelines.yml` — Azure DevOps pipeline
- `.github/workflows/deploy.yml` — GitHub Actions pipeline
- `scripts/smoke-test.sh` — Post-deployment verification
- `scripts/rollback.sh` — Manual rollback script

## Setup
```bash
# 1. Create service connection in Azure DevOps
az ad sp create-for-rbac \
  --name "sp-azuredevops-prod" \
  --role Contributor \
  --scopes /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG \
  --sdk-auth

# 2. Store in Azure DevOps as service connection
# Project Settings → Service Connections → New → Azure Resource Manager

# 3. Create variable groups
az pipelines variable-group create \
  --name "prod-variables" \
  --variables \
    APP_NAME=myapp \
    RESOURCE_GROUP=rg-myapp-prod \
    ACR_NAME=myregistry

# 4. Link Key Vault to variable group
az pipelines variable-group create \
  --name "prod-secrets" \
  --authorize true \
  --variables placeholder=placeholder
# Then link to Key Vault in Azure DevOps UI
```

## Deployment Environments
| Environment | Branch | Approval | Auto-deploy |
|-------------|--------|----------|-------------|
| Development | feature/* | None | Yes |
| Staging | develop | None | Yes |
| Production | main | Required | No |

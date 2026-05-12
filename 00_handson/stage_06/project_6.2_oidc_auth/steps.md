# Steps — Project 6.2 Secure OIDC GitHub Authentication

## Phase 1 — Create App Registration

```bash
# Create App Registration
APP_ID=$(az ad app create --display-name "github-actions-oidc" --query appId -o tsv)
echo "App ID: $APP_ID"

# Create Service Principal
az ad sp create --id $APP_ID

# Get Object ID of the SP
SP_OID=$(az ad sp show --id $APP_ID --query id -o tsv)
echo "SP Object ID: $SP_OID"
```

---

## Phase 2 — Add Federated Credential

```bash
# Add federated credential for main branch
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:myorg/my-app:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Add federated credential for pull requests
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-pr",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:myorg/my-app:pull_request",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

---

## Phase 3 — Assign RBAC Role

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Assign Contributor role at subscription scope
az role assignment create \
  --assignee $SP_OID \
  --role Contributor \
  --scope /subscriptions/$SUBSCRIPTION_ID
```

---

## Phase 4 — Configure GitHub Secrets

Add these secrets to your GitHub repository (Settings → Secrets → Actions):
```
AZURE_CLIENT_ID     = <APP_ID from Phase 1>
AZURE_TENANT_ID     = <az account show --query tenantId -o tsv>
AZURE_SUBSCRIPTION_ID = <SUBSCRIPTION_ID from Phase 3>
```

---

## Phase 5 — GitHub Actions Workflow

Create `.github/workflows/deploy.yml`:
```yaml
name: Deploy to Azure

on:
  push:
    branches: [main]

permissions:
  id-token: write   # Required for OIDC
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Deploy
        run: az group list --output table
```

---

## Screenshots to Take
- [ ] App Registration in Azure AD portal
- [ ] Federated credentials tab showing GitHub issuer
- [ ] GitHub Actions workflow running successfully
- [ ] No stored secrets in GitHub — only client_id, tenant_id, subscription_id

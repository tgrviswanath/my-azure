# Steps — Project 6.4 Multi-subscription CI/CD Pipeline

## Phase 1 — Create App Registrations per Subscription

```bash
# For each subscription (dev, qa, prod):
for ENV in dev qa prod; do
  APP_ID=$(az ad app create --display-name "github-actions-$ENV" --query appId -o tsv)
  SP_OID=$(az ad sp create --id $APP_ID --query id -o tsv)

  # Add federated credential
  az ad app federated-credential create --id $APP_ID --parameters "{
    \"name\": \"github-$ENV\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:myorg/my-app:environment:$ENV\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"

  echo "$ENV: CLIENT_ID=$APP_ID"
done
```

---

## Phase 2 — Assign Roles per Subscription

```bash
# Switch to each subscription and assign role
for SUB_ID in $DEV_SUB $QA_SUB $PROD_SUB; do
  az account set --subscription $SUB_ID
  az role assignment create \
    --assignee $SP_OID \
    --role Contributor \
    --scope /subscriptions/$SUB_ID
done
```

---

## Phase 3 — Configure GitHub Environments

In GitHub → Settings → Environments, create: `dev`, `qa`, `prod`

For each environment, add secrets:
```
AZURE_CLIENT_ID       = <app registration client id>
AZURE_TENANT_ID       = <tenant id>
AZURE_SUBSCRIPTION_ID = <subscription id>
```

Add approval protection rule to `prod` environment.

---

## Phase 4 — Matrix Workflow

```yaml
# .github/workflows/multi-sub-deploy.yml
jobs:
  deploy:
    strategy:
      matrix:
        environment: [dev, qa, prod]
    environment: ${{ matrix.environment }}
    steps:
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - run: az group list --output table
```

---

## Screenshots to Take
- [ ] Three App Registrations in Azure AD
- [ ] GitHub Environments with per-environment secrets
- [ ] Matrix pipeline running across all subscriptions
- [ ] Prod deployment waiting for approval

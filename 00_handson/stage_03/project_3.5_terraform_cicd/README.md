# Project 3.5 — Terraform CI/CD with GitHub Actions

## What It Does

Automates Terraform deployments using GitHub Actions:
- **PR workflow** — runs `terraform plan` on every pull request, posts results as a comment
- **Merge workflow** — runs `terraform apply` automatically when PR merges to main
- **Service Principal** — GitHub Actions authenticates to Azure using a service principal
- **Remote state** — state stored in Azure Storage (from project 3.4)
- **Secrets** — Azure credentials stored as GitHub repository secrets

## How It Works

```
Developer opens PR
    → GitHub Actions: terraform fmt, validate, plan
    → Plan output posted as PR comment
    → Reviewer approves

PR merged to main
    → GitHub Actions: terraform apply
    → Resources created/updated in Azure
    → Slack/email notification (optional)
```

## Setup Steps

### 1. Create Service Principal
```bash
az ad sp create-for-rbac \
  --name sp-terraform-cicd \
  --role Contributor \
  --scopes /subscriptions/<subscription-id> \
  --sdk-auth
```

### 2. Store Secrets in GitHub
Go to: Repository → Settings → Secrets and variables → Actions

Add these secrets:
- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `TF_STATE_STORAGE_ACCOUNT` (from project 3.4)

### 3. Push the workflow files
```bash
git add .github/workflows/
git commit -m "Add Terraform CI/CD workflows"
git push
```

### 4. Test the pipeline
```bash
pip install requests
python code/pipeline_trigger.py \
  --repo owner/repo-name \
  --workflow terraform-apply.yml \
  --token <github-pat>
```

## Lessons Learned

- **Never store Azure credentials in code** — always use GitHub Secrets
- **`terraform plan` on PR** — catch mistakes before they reach production
- **`-lock=false` in plan** — plan doesn't need a lock; only apply does
- **Workflow concurrency** — use `concurrency: group: terraform` to prevent parallel applies
- **`GITHUB_TOKEN` vs PAT** — `GITHUB_TOKEN` can't trigger other workflows; use a PAT for `workflow_dispatch`
- **Terraform output in PR comments** — use `github-script` action to post plan output as a comment
- **Environment protection rules** — require manual approval before applying to prod

## Code

See `code/pipeline_trigger.py` — triggers GitHub Actions workflow_dispatch, polls for completion, prints result.

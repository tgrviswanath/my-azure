# Deployment Steps — Terraform CI/CD

## Phase 1: Create Service Principal

```bash
# 1.1 Get your subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "Subscription: $SUBSCRIPTION_ID"

# 1.2 Create service principal with Contributor role
az ad sp create-for-rbac \
  --name sp-terraform-cicd \
  --role Contributor \
  --scopes /subscriptions/$SUBSCRIPTION_ID \
  --sdk-auth

# Output (save this — you'll need it for GitHub Secrets):
# {
#   "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#   "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
#   "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#   "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#   ...
# }

# 1.3 Also grant Storage Blob Data Contributor for state storage
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee <clientId-from-above> \
  --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-tfstate

# 1.4 Verify service principal
az ad sp show --id <clientId> --query displayName
```

---

## Phase 2: Store Secrets in GitHub

```bash
# 2.1 Install GitHub CLI (optional, for scripted secret creation)
# winget install GitHub.cli
# gh auth login

# 2.2 Add secrets via GitHub CLI
gh secret set AZURE_CLIENT_ID --body "<clientId>"
gh secret set AZURE_CLIENT_SECRET --body "<clientSecret>"
gh secret set AZURE_TENANT_ID --body "<tenantId>"
gh secret set AZURE_SUBSCRIPTION_ID --body "<subscriptionId>"
gh secret set TF_STATE_STORAGE_ACCOUNT --body "stterraformstateXXXXXX"

# 2.3 Or add manually via GitHub UI:
# Repository → Settings → Secrets and variables → Actions → New repository secret

# 2.4 Verify secrets are set
gh secret list
```

---

## Phase 3: Create Workflow Files

```bash
# 3.1 Create .github/workflows directory
mkdir -p .github/workflows

# 3.2 The workflow files are already in this project:
# .github/workflows/terraform-plan.yml   (runs on PR)
# .github/workflows/terraform-apply.yml  (runs on merge to main)

# 3.3 Commit and push
git add .github/
git commit -m "Add Terraform CI/CD workflows"
git push origin main
```

---

## Phase 4: Test Plan on PR

```bash
# 4.1 Create a feature branch
git checkout -b feature/add-storage-account

# 4.2 Make a change to main.tf (e.g., add a tag)
# Edit terraform/main.tf

# 4.3 Push and create PR
git add terraform/main.tf
git commit -m "Add storage account tag"
git push origin feature/add-storage-account
gh pr create --title "Add storage account tag" --body "Testing CI/CD pipeline"

# 4.4 Watch the workflow run
gh run list --workflow=terraform-plan.yml

# 4.5 View the plan output in the PR comment
gh pr view --web
```

---

## Phase 5: Apply on Merge

```bash
# 5.1 Approve and merge the PR
gh pr merge --squash

# 5.2 Watch the apply workflow
gh run list --workflow=terraform-apply.yml
gh run watch

# 5.3 Trigger manually (for testing)
python code/pipeline_trigger.py \
  --repo <owner>/<repo> \
  --workflow terraform-apply.yml \
  --token <github-pat> \
  --ref main

# 5.4 View workflow run logs
gh run view --log

# 5.5 Cleanup
terraform destroy -auto-approve
az ad sp delete --id <clientId>
```

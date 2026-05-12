# Project 6.2 — Secure OIDC GitHub Authentication

## What This Does
Sets up passwordless authentication between GitHub Actions and Azure using OpenID Connect (OIDC) federated identity. No stored secrets — GitHub exchanges a short-lived OIDC token for an Azure access token at runtime.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure AD App Registration | Identity for GitHub Actions |
| Federated Identity Credentials | Trust GitHub's OIDC issuer |
| Azure RBAC | Grant permissions to the App Registration |
| GitHub Actions | CI/CD pipeline using OIDC |

## Architecture
```
GitHub Actions workflow
    │ requests OIDC token from GitHub
    ▼
GitHub OIDC Provider (token.actions.githubusercontent.com)
    │ issues signed JWT
    ▼
Azure AD (validates JWT against federated credential)
    │ issues Azure access token
    ▼
Azure Resources (deploy, push to ACR, etc.)
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve
# Outputs: client_id, tenant_id — add to GitHub secrets
```

## Lessons Learned
- No stored secrets: OIDC tokens are short-lived (5 min) and scoped to the workflow
- Federated credentials can be scoped to branch, tag, or environment
- Use `azure/login@v2` action with `client-id`, `tenant-id`, `subscription-id`
- More secure than service principal secrets — no rotation needed

## Code

### `code/oidc_setup.py` — Create App Registration + federated credential

```bash
pip install azure-identity azure-mgmt-authorization azure-graphrbac

python code/oidc_setup.py --repo myorg/my-app --role Contributor
```

Prints the `client_id` and `tenant_id` to add as GitHub secrets.

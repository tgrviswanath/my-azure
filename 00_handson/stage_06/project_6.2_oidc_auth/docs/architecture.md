# Architecture — Project 6.2 Secure OIDC GitHub Authentication

## Diagram

```
GitHub Actions Runner
    │
    │ 1. Request OIDC token
    ▼
GitHub OIDC Provider
(token.actions.githubusercontent.com)
    │
    │ 2. Issue signed JWT
    │    sub: repo:myorg/my-app:ref:refs/heads/main
    │    iss: https://token.actions.githubusercontent.com
    │    aud: api://AzureADTokenExchange
    ▼
Azure AD
    │ 3. Validate JWT against federated credential
    │    - Check issuer matches
    │    - Check subject matches (repo + branch)
    │    - Check audience matches
    │
    │ 4. Issue Azure access token (1 hour TTL)
    ▼
Azure Resources
    ├── ACR (push images)
    ├── AKS (deploy workloads)
    ├── Resource Groups (manage infra)
    └── Storage (read/write blobs)
```

## Federated Credential Subjects

| Subject Pattern | Scope |
|----------------|-------|
| `repo:org/repo:ref:refs/heads/main` | Main branch only |
| `repo:org/repo:pull_request` | All pull requests |
| `repo:org/repo:environment:production` | Production environment |
| `repo:org/repo:*` | Any ref (less secure) |

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| OIDC | OpenID Connect — identity layer on top of OAuth 2.0 |
| Federated credential | Trust relationship between Azure AD and external IdP |
| JWT | JSON Web Token — signed, short-lived identity assertion |
| No stored secrets | Token exchanged at runtime — nothing to rotate or leak |

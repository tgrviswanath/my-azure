# Architecture — Project 6.4 Multi-subscription CI/CD Pipeline

## Diagram

```
GitHub Repository
    │
    ▼
GitHub Actions (matrix: dev, qa, prod)
    │
    ├── Job: deploy-dev
    │     │ OIDC → Azure AD (dev App Registration)
    │     ▼
    │   Dev Subscription
    │     └── rg-app-dev → AKS / App Service
    │
    ├── Job: deploy-qa
    │     │ OIDC → Azure AD (qa App Registration)
    │     ▼
    │   QA Subscription
    │     └── rg-app-qa → AKS / App Service
    │
    └── Job: deploy-prod (requires approval)
          │ OIDC → Azure AD (prod App Registration)
          ▼
        Prod Subscription
          └── rg-app-prod → AKS / App Service
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| GitHub Environments | Per-environment secrets + approval gates |
| Matrix strategy | Run same job across multiple environments in parallel |
| Subscription isolation | Each env in separate subscription — blast radius control |
| OIDC per subscription | Each App Registration scoped to one subscription |

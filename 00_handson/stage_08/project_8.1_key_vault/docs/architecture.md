# Architecture — Project 8.1 Key Vault Integration

## Diagram

```
Application (Azure Function / App Service)
    │ Managed Identity (no password)
    ▼
Azure AD
    │ validates identity, issues token
    ▼
Azure Key Vault (RBAC: Key Vault Secrets User)
    ├── GET secret/db-password → "MySecurePass123!"
    ├── GET secret/api-key → "sk-abc123..."
    └── GET secret/connection-string → "Server=..."
          │
          ▼
    Application uses secret value
    (never stored in code or config)
```

## Secret Access Patterns

| Pattern | How |
|---------|-----|
| Direct SDK | `SecretClient.get_secret("name")` |
| Key Vault Reference | `@Microsoft.KeyVault(SecretUri=...)` in App Settings |
| CSI Driver | Mount secrets as files in AKS pods |
| Environment variable | Set at deploy time from Key Vault |

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| RBAC model | Role-based access (preferred over access policies) |
| Soft delete | Secrets recoverable for 7-90 days after deletion |
| Purge protection | Prevents permanent deletion during retention period |
| Secret versioning | Each update creates a new version — old versions kept |
| Managed Identity | App authenticates with Azure AD — no stored credentials |

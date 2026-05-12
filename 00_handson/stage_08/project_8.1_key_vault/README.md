# Project 8.1 — Key Vault Integration

## What This Does
Stores secrets, keys, and certificates in Azure Key Vault. Applications access secrets using Managed Identity — no credentials in code or config files.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure Key Vault | Secrets, keys, certificates store |
| Managed Identity | Passwordless authentication to Key Vault |
| Azure Functions | App that reads secrets at runtime |
| Key Vault References | App Service/Functions native integration |

## Architecture
```
Azure Function (Managed Identity)
    │ no password — identity-based auth
    ▼
Azure Key Vault
    ├── Secrets: DB passwords, API keys, connection strings
    ├── Keys: encryption keys (HSM-backed)
    └── Certificates: TLS certificates
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve
export KEY_VAULT_URL=$(terraform output -raw key_vault_uri)
python code/secrets_client.py --vault-url $KEY_VAULT_URL
```

## Lessons Learned
- Never store secrets in code, env vars, or config files — always Key Vault
- Use Managed Identity — no credentials to rotate or leak
- Key Vault References: `@Microsoft.KeyVault(SecretUri=...)` in App Settings
- Enable soft-delete and purge protection in production
- Use RBAC model (not access policies) for new deployments

## Code

### `code/secrets_client.py` — Get/set/list secrets from Key Vault

```bash
pip install azure-identity azure-keyvault-secrets
export KEY_VAULT_URL=https://kv-handson-001.vault.azure.net/
python code/secrets_client.py --vault-url $KEY_VAULT_URL
```

# Steps — Project 8.1 Key Vault Integration

## Phase 1 — Create Key Vault

```bash
az group create --name rg-key-vault --location eastus

az keyvault create \
  --name kv-handson-001 \
  --resource-group rg-key-vault \
  --location eastus \
  --enable-rbac-authorization true \
  --enable-soft-delete true \
  --soft-delete-retention-days 7
```

---

## Phase 2 — Store Secrets

```bash
# Assign yourself Key Vault Secrets Officer role
MY_OID=$(az ad signed-in-user show --query id -o tsv)
KV_ID=$(az keyvault show --name kv-handson-001 --query id -o tsv)

az role assignment create \
  --assignee $MY_OID \
  --role "Key Vault Secrets Officer" \
  --scope $KV_ID

# Store secrets
az keyvault secret set --vault-name kv-handson-001 --name "db-password" --value "MySecurePass123!"
az keyvault secret set --vault-name kv-handson-001 --name "api-key" --value "sk-abc123def456"
az keyvault secret set --vault-name kv-handson-001 --name "connection-string" --value "Server=mydb.database.windows.net;..."
```

---

## Phase 3 — Assign Access to Managed Identity

```bash
# Get managed identity principal ID
MI_OID=$(az identity show --name mi-app --resource-group rg-key-vault --query principalId -o tsv)

# Assign Key Vault Secrets User role
az role assignment create \
  --assignee $MI_OID \
  --role "Key Vault Secrets User" \
  --scope $KV_ID
```

---

## Phase 4 — Access from Python

```bash
pip install azure-identity azure-keyvault-secrets
export KEY_VAULT_URL=https://kv-handson-001.vault.azure.net/
python code/secrets_client.py --vault-url $KEY_VAULT_URL
```

---

## Phase 5 — Rotate a Secret

```bash
# Create new version of secret
az keyvault secret set --vault-name kv-handson-001 --name "db-password" --value "NewSecurePass456!"

# List all versions
az keyvault secret list-versions --vault-name kv-handson-001 --name "db-password"

# Disable old version
az keyvault secret set-attributes \
  --vault-name kv-handson-001 \
  --name "db-password" \
  --version <old-version-id> \
  --enabled false
```

---

## Screenshots to Take
- [ ] Key Vault created with RBAC enabled
- [ ] Secrets stored (names visible, values hidden)
- [ ] Python script reading secret successfully
- [ ] Secret rotation with multiple versions

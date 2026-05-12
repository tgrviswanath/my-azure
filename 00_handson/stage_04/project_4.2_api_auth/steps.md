# Steps — Project 4.2 API Authentication & Authorization

## Phase 1 — Get Token and Test
```bash
# Get access token
TOKEN=$(az account get-access-token --resource <CLIENT_ID> --query accessToken -o tsv)

# Call protected endpoint
curl -H "Authorization: Bearer $TOKEN" \
  https://func-api-auth-001.azurewebsites.net/api/protected

# Call admin endpoint (requires Admin role)
curl -H "Authorization: Bearer $TOKEN" \
  https://func-api-auth-001.azurewebsites.net/api/admin
```

## Phase 2 — Assign App Role
```bash
# Assign Admin role to user
az ad app role assignment create \
  --assignee <USER_OBJECT_ID> \
  --id 00000000-0000-0000-0000-000000000001 \
  --resource-id <SERVICE_PRINCIPAL_OBJECT_ID>
```

## Screenshots to Take
- [ ] 401 without token
- [ ] 200 with valid token
- [ ] 403 without Admin role
- [ ] 200 with Admin role assigned

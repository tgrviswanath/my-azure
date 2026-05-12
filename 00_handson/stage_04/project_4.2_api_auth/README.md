# Project 4.2 — API Authentication & Authorization

## What This Does
Secures Azure Functions API with Azure AD JWT tokens and RBAC.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure AD | Identity provider, issues JWT tokens |
| Azure Functions | Protected API endpoints |
| API Management | Validate JWT policy |

## How to Run
```bash
# Get token
TOKEN=$(az account get-access-token --resource <APP_ID> --query accessToken -o tsv)

# Call protected endpoint
curl -H "Authorization: Bearer $TOKEN" https://<func>.azurewebsites.net/api/protected
```

## Lessons Learned
- Validate JWT in API Management — offloads auth from Function code
- Use `roles` claim for RBAC (app roles defined in App Registration)
- Never trust client-side claims — always validate server-side

# Architecture — Project 4.2 API Authentication

## JWT Flow

```
Client
  │  1. Request token
  ▼
Azure AD → issues JWT (contains: iss, aud, roles, exp)
  │  2. Call API with Bearer token
  ▼
Azure Function
  │  3. Validate JWT signature (JWKS endpoint)
  │  4. Check audience = CLIENT_ID
  │  5. Check roles claim for RBAC
  ▼
Response (200 / 401 / 403)
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| JWT | JSON Web Token — signed claims about the user |
| JWKS | Public keys endpoint for signature verification |
| `aud` claim | Must match your app's CLIENT_ID |
| `roles` claim | App roles assigned to the user |
| 401 | No/invalid token |
| 403 | Valid token but missing required role |

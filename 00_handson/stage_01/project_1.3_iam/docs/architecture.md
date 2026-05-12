# Architecture — Project 1.3 Azure AD RBAC & Identity Management

## Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                  Azure Active Directory                      │
│                                                              │
│   Users                Groups                               │
│   ┌──────────┐         ┌──────────────────────────────┐    │
│   │ labdev   │────────►│ azure-lab-developers          │    │
│   │ labread  │────────►│ azure-lab-readers             │    │
│   └──────────┘         └──────────────────────────────┘    │
│                                                              │
│   Managed Identities                                         │
│   ┌──────────────────────────────────────────────────────┐  │
│   │  lab-managed-identity (user-assigned)                │  │
│   │  Principal ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  │  │
│   └──────────────────────────────────────────────────────┘  │
└──────────────────────────────┬──────────────────────────────┘
                               │ Role Assignments
                               ▼
┌─────────────────────────────────────────────────────────────┐
│              Azure Subscription                              │
│                                                              │
│   ┌──────────────────────────────────────────────────────┐  │
│   │  Resource Group: iam-lab-rg                          │  │
│   │                                                      │  │
│   │  Role Assignments:                                   │  │
│   │  azure-lab-developers → Contributor                  │  │
│   │  azure-lab-readers    → Reader                       │  │
│   │  lab-managed-identity → Storage Blob Data Reader     │  │
│   │                                                      │  │
│   │  ┌──────────────┐  ┌──────────────────────────────┐ │  │
│   │  │ Storage Acct │  │  Azure VM (with managed ID)  │ │  │
│   │  │              │  │  ← uses managed identity     │ │  │
│   │  └──────────────┘  └──────────────────────────────┘ │  │
│   └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## RBAC Scope Hierarchy

```
Subscription (broadest)
    │
    ├── Resource Group
    │       │
    │       └── Resource (narrowest)
    │
    └── Assign roles at the NARROWEST scope possible
```

## Managed Identity vs Service Principal

```
┌─────────────────────────────────────────────────────────┐
│  Service Principal (old way)                            │
│  - Manual secret rotation required                      │
│  - Secret can be leaked                                 │
│  - You manage the credential lifecycle                  │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  Managed Identity (recommended)                         │
│  - No secrets — Azure manages credentials               │
│  - Automatic rotation                                   │
│  - Works with DefaultAzureCredential in SDK             │
│  - System-assigned: tied to resource lifecycle          │
│  - User-assigned: shared across multiple resources      │
└─────────────────────────────────────────────────────────┘
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Principal | Who is being assigned a role (user, group, managed identity, service principal) |
| Role | What permissions are granted (Owner, Contributor, Reader, custom) |
| Scope | Where the role applies (subscription, resource group, resource) |
| Role Assignment | The binding of principal + role + scope |
| Managed Identity | Azure-managed service account — no password management needed |
| Least Privilege | Grant only the minimum permissions required for the task |

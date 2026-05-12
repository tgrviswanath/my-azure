# Project 1.3 — Azure AD RBAC & Identity Management

## What This Does
Implements Azure Role-Based Access Control (RBAC) with Azure Active Directory. Creates users, groups, managed identities, and role assignments following the principle of least privilege.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure Active Directory | Identity provider — users, groups, apps |
| Azure RBAC | Role assignments on resources |
| Managed Identity | Service identity for Azure resources (no passwords) |
| Azure Key Vault | Secrets management (accessed via managed identity) |
| Azure Monitor | Audit logs for identity events |

## How to Deploy
```bash
cd terraform
terraform init
terraform apply -auto-approve

# Run RBAC setup script
pip install azure-mgmt-authorization azure-identity azure-mgmt-msi
python code/rbac_setup.py
```

## Folder Structure
```
project_1.3_iam/
├── README.md
├── steps.md
├── cost_estimate.md
├── docs/
│   └── architecture.md
├── terraform/
│   └── main.tf
└── code/
    └── rbac_setup.py
```

## Built-in Roles Reference
| Role | Permissions |
|------|------------|
| Owner | Full access including role assignments |
| Contributor | Create/manage resources, no role assignments |
| Reader | View resources only |
| Storage Blob Data Contributor | Read/write/delete blobs |
| Storage Blob Data Reader | Read blobs only |
| Key Vault Secrets User | Read secrets from Key Vault |
| Virtual Machine Contributor | Manage VMs, no network/storage access |

## Lessons Learned
- Managed Identity is the preferred way for Azure services to authenticate — no secrets
- Always assign roles at the narrowest scope (resource > resource group > subscription)
- `az role assignment list --assignee <object-id>` shows all roles for a principal
- System-assigned identity is tied to the resource lifecycle — deleted with the resource
- User-assigned identity can be shared across multiple resources
- Azure AD Free tier supports RBAC; P1/P2 adds Conditional Access and PIM

# Architecture — Full Azure Infrastructure

## ASCII Diagram

```
  Terraform
  ─────────
  main.tf ──► azurerm provider ──► Azure Resource Manager
                                          │
                    ┌─────────────────────▼──────────────────────────┐
                    │  Resource Group: rg-full-infra                  │
                    │                                                   │
                    │  ┌─────────────────────────────────────────┐   │
                    │  │  VNet: vnet-full-infra (10.0.0.0/16)     │   │
                    │  │                                           │   │
                    │  │  ┌──────────────────────────────────┐   │   │
                    │  │  │  subnet-appgw (10.0.0.0/24)       │   │   │
                    │  │  │  Application Gateway Standard_v2  │   │   │
                    │  │  │  pip-appgw (Static Public IP)     │   │   │
                    │  │  └──────────────┬───────────────────┘   │   │
                    │  │                 │ HTTP :80               │   │
                    │  │  ┌──────────────▼───────────────────┐   │   │
                    │  │  │  subnet-web (10.0.1.0/24)         │   │   │
                    │  │  │  NSG-web (Allow 80, 443, 22)      │   │   │
                    │  │  │  vm-web (Standard_B2s)            │   │   │
                    │  │  │  pip-vm (Static Public IP)        │   │   │
                    │  │  └──────────────┬───────────────────┘   │   │
                    │  │                 │ TCP :1433              │   │
                    │  │  ┌──────────────▼───────────────────┐   │   │
                    │  │  │  subnet-db (10.0.3.0/24)          │   │   │
                    │  │  │  NSG-db (Allow 1433 from web)     │   │   │
                    │  │  │  Azure SQL (sql-full-infra-xxxxx) │   │   │
                    │  │  │  db-app (S1 tier)                 │   │   │
                    │  │  └──────────────────────────────────┘   │   │
                    │  └─────────────────────────────────────────┘   │
                    └─────────────────────────────────────────────────┘
```

## Terraform Resource Dependency Graph

```
azurerm_resource_group.main
  └── azurerm_virtual_network.main
        ├── azurerm_subnet.appgw
        │     └── azurerm_application_gateway.main
        │           └── azurerm_public_ip.appgw
        ├── azurerm_subnet.web
        │     ├── azurerm_subnet_nsg_association.web
        │     │     └── azurerm_network_security_group.web
        │     └── azurerm_network_interface.vm
        │           └── azurerm_linux_virtual_machine.web
        │                 └── azurerm_public_ip.vm
        └── azurerm_subnet.db
              └── azurerm_subnet_nsg_association.db
                    └── azurerm_network_security_group.db

azurerm_mssql_server.main
  └── azurerm_mssql_database.app
  └── azurerm_mssql_virtual_network_rule.web
```

## Key Concepts

| Concept | Explanation |
|---|---|
| Implicit dependency | `azurerm_subnet.web.id` in a resource automatically creates a dependency |
| Explicit dependency | `depends_on = [azurerm_role_assignment.x]` for non-obvious dependencies |
| Resource lifecycle | `prevent_destroy = true` protects critical resources from accidental deletion |
| `random_string` | Generates unique suffixes for globally-unique names (storage, SQL) |
| `sensitive = true` | Hides variable/output values in plan and apply output |

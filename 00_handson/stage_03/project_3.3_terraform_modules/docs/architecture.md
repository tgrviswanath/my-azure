# Architecture — Terraform Modules

## Module Structure

```
terraform/
├── main.tf                    ← Root module (calls child modules)
├── envs/
│   ├── dev.tfvars             ← Dev variable values
│   ├── qa.tfvars              ← QA variable values
│   └── prod.tfvars            ← Prod variable values
└── modules/
    ├── vnet/                  ← VNet module
    │   ├── main.tf            ← azurerm_virtual_network, azurerm_subnet, azurerm_nsg
    │   ├── variables.tf       ← address_space, subnet_configs, location, etc.
    │   └── outputs.tf         ← subnet_ids, vnet_id, nsg_ids
    ├── vm/                    ← VM module
    │   ├── main.tf            ← azurerm_linux_virtual_machine, azurerm_nic, azurerm_public_ip
    │   ├── variables.tf       ← vm_size, admin_username, subnet_id, etc.
    │   └── outputs.tf         ← vm_id, public_ip, private_ip
    └── sql/                   ← SQL module
        ├── main.tf            ← azurerm_mssql_server, azurerm_mssql_database
        ├── variables.tf       ← sku_name, admin_username, admin_password, etc.
        └── outputs.tf         ← server_fqdn, database_id
```

## How Root Module Calls Child Modules

```hcl
# main.tf (root)
module "vnet" {
  source         = "./modules/vnet"
  resource_group = azurerm_resource_group.main.name
  location       = var.location
  environment    = var.environment
  address_space  = var.vnet_address_space
}

module "vm" {
  source         = "./modules/vm"
  resource_group = azurerm_resource_group.main.name
  location       = var.location
  subnet_id      = module.vnet.web_subnet_id   # ← uses vnet module output
  vm_size        = var.vm_size
  vm_count       = var.vm_count
}

module "sql" {
  source              = "./modules/sql"
  resource_group      = azurerm_resource_group.main.name
  location            = var.location
  sku_name            = var.sql_sku
  admin_password      = var.sql_admin_password
  allowed_subnet_id   = module.vnet.web_subnet_id
}
```

## Workspace → Environment Mapping

```
terraform workspace select dev  →  uses dev.tfvars  →  rg-modules-dev
terraform workspace select qa   →  uses qa.tfvars   →  rg-modules-qa
terraform workspace select prod →  uses prod.tfvars →  rg-modules-prod
```

## Key Concepts

| Concept | Explanation |
|---|---|
| Module | A directory of .tf files that can be called with `module {}` block |
| Module inputs | Variables declared in `variables.tf` of the module |
| Module outputs | Values declared in `outputs.tf`, accessed as `module.name.output_name` |
| Workspace | Separate state file for the same configuration. `terraform.workspace` returns current name. |
| `.tfvars` file | Key=value file passed with `-var-file=`. Overrides variable defaults. |
| Module source | Can be local path (`./modules/vnet`), Git URL, or Terraform Registry |

# Project 3.3 — Terraform Modules for Multi-Environment

## What It Does

Organizes Terraform code into reusable modules and deploys to dev/qa/prod environments:
- **modules/vnet** — reusable VNet + subnets module
- **modules/vm** — reusable VM module
- **modules/sql** — reusable Azure SQL module
- **environments/** — dev, qa, prod with different sizes and configs

The same module code deploys to all environments; only the variable values differ.

## Module Structure

```
terraform/
├── modules/
│   ├── vnet/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── vm/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── sql/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── envs/
│   ├── dev.tfvars
│   ├── qa.tfvars
│   └── prod.tfvars
└── main.tf   (calls modules)
```

## How to Deploy

```bash
cd terraform/

# Dev environment
terraform init
terraform workspace new dev
terraform plan -var-file="envs/dev.tfvars" -out=tfplan-dev
terraform apply tfplan-dev

# QA environment
terraform workspace new qa
terraform plan -var-file="envs/qa.tfvars" -out=tfplan-qa
terraform apply tfplan-qa

# Prod environment (requires confirmation)
terraform workspace new prod
terraform plan -var-file="envs/prod.tfvars" -out=tfplan-prod
terraform apply tfplan-prod
```

### Use the environment switcher
```bash
python code/env_switcher.py --env dev
python code/env_switcher.py --env qa
python code/env_switcher.py --env prod  # Requires confirmation
```

## Environment Differences

| Setting | dev | qa | prod |
|---|---|---|---|
| VM size | Standard_B1s | Standard_B2s | Standard_D4s_v3 |
| VM count | 1 | 2 | 4 |
| SQL tier | Basic | S1 | P1 |
| App GW capacity | 1 | 1 | 3 |
| Monthly cost | ~$50 | ~$100 | ~$300 |

## Lessons Learned

- **Modules are just directories** — any directory with .tf files can be a module
- **Module versioning** — use `source = "git::https://..."` with `?ref=v1.0.0` for versioned modules
- **Workspaces vs directories** — workspaces share the same code; directories allow different code per env
- **`terraform.workspace`** — use in code to conditionally set values based on workspace
- **Module outputs** — modules must explicitly output values for the caller to use
- **Don't over-modularize** — start simple; extract modules when you repeat the same pattern 3+ times

## Code

See `code/env_switcher.py` — switches Terraform workspaces, shows cost estimates, requires confirmation for prod.

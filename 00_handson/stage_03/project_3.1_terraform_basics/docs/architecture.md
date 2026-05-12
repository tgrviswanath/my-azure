# Architecture — Terraform Basics

## ASCII Diagram

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                    Terraform Workflow                             │
  │                                                                    │
  │   .tf files          Terraform CLI         Azure                  │
  │   ─────────          ─────────────         ─────                  │
  │                                                                    │
  │   main.tf    ──►  terraform init   ──►  Download azurerm plugin   │
  │   variables.tf     terraform fmt         (no Azure calls)         │
  │   outputs.tf       terraform validate    (no Azure calls)         │
  │                    terraform plan   ──►  Read current state       │
  │                                          Compare to .tf files     │
  │                                          Show diff (no changes)   │
  │                    terraform apply  ──►  Create Resource Group    │
  │                                          Create Storage Account   │
  │                                          Write terraform.tfstate  │
  │                    terraform output ──►  Read terraform.tfstate   │
  │                                          Print output values      │
  │                    terraform destroy──►  Delete all resources     │
  │                                          Clear terraform.tfstate  │
  └──────────────────────────────────────────────────────────────────┘

  ┌──────────────────────────────────────────────────────────────────┐
  │                    State File Concept                             │
  │                                                                    │
  │   terraform.tfstate (JSON)                                        │
  │   ┌─────────────────────────────────────────────────────────┐   │
  │   │  {                                                        │   │
  │   │    "resources": [                                         │   │
  │   │      {                                                    │   │
  │   │        "type": "azurerm_resource_group",                  │   │
  │   │        "name": "main",                                    │   │
  │   │        "instances": [{                                    │   │
  │   │          "attributes": {                                  │   │
  │   │            "id": "/subscriptions/.../rg-terraform-basics",│   │
  │   │            "name": "rg-terraform-basics",                 │   │
  │   │            "location": "eastus"                           │   │
  │   │          }                                                │   │
  │   │        }]                                                 │   │
  │   │      }                                                    │   │
  │   │    ]                                                      │   │
  │   │  }                                                        │   │
  │   └─────────────────────────────────────────────────────────┘   │
  └──────────────────────────────────────────────────────────────────┘
```

## Key Concepts

| Concept | Explanation |
|---|---|
| `terraform init` | Downloads provider plugins. Must run first. Creates `.terraform/` directory. |
| `terraform plan` | Compares `.tf` files to state file. Shows what will be created/changed/destroyed. |
| `terraform apply` | Executes the plan. Calls Azure APIs. Updates state file. |
| `terraform destroy` | Destroys all resources tracked in state file. |
| State file | `terraform.tfstate` — Terraform's source of truth for what exists. Never edit manually. |
| Provider | Plugin that translates Terraform resources into API calls (azurerm → Azure Resource Manager). |
| Variable | Input to your configuration. Set via CLI, `.tfvars` file, or environment variable. |
| Output | Value exposed after apply. Useful for passing values to other systems. |

## Terraform File Structure

```
terraform/
├── main.tf          # Resources, provider, terraform block
├── variables.tf     # Variable declarations (optional, can be in main.tf)
├── outputs.tf       # Output declarations (optional, can be in main.tf)
├── terraform.tfvars # Variable values (gitignore this if it has secrets)
├── .terraform/      # Provider plugins (gitignore this)
├── .terraform.lock.hcl  # Provider version lock (commit this)
└── terraform.tfstate    # State file (gitignore for local; use remote state in teams)
```

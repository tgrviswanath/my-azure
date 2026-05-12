# Project 3.1 — Terraform Basics with Azure

## What It Does

Introduces Terraform fundamentals using Azure as the target:
- **Provider configuration** — azurerm provider with authentication
- **Resources** — create a Resource Group and Storage Account
- **Variables** — parameterize your configuration
- **Outputs** — expose values after apply
- **State** — understand how Terraform tracks what it created

This is the "Hello World" of Terraform on Azure.

## Azure Services Used

| Service | Purpose |
|---|---|
| Resource Group | Container for all Azure resources |
| Storage Account | Simple Azure resource to practice with |

## How to Deploy

### Prerequisites
```bash
# Install Terraform
winget install HashiCorp.Terraform
# or
brew install terraform

# Verify
terraform version

# Login to Azure
az login
az account set --subscription "<your-subscription-id>"
```

### Deploy
```bash
cd terraform/
terraform init          # Download azurerm provider
terraform fmt           # Format code
terraform validate      # Check syntax
terraform plan          # Preview changes
terraform apply         # Create resources
terraform output        # Show outputs
terraform show          # Show current state
terraform destroy       # Delete everything
```

### Use the Python wrapper
```bash
pip install subprocess
python code/terraform_runner.py init
python code/terraform_runner.py plan
python code/terraform_runner.py apply
python code/terraform_runner.py output
python code/terraform_runner.py destroy
```

## Terraform Concepts

| Concept | What It Is |
|---|---|
| Provider | Plugin that talks to a cloud API (azurerm, aws, google) |
| Resource | A piece of infrastructure to create/manage |
| Variable | Input parameter for your configuration |
| Output | Value to expose after apply (like a return value) |
| State | JSON file tracking what Terraform created |
| Plan | Diff between desired state and current state |
| Apply | Execute the plan to reach desired state |

## Lessons Learned

- **`terraform init` must run first** — downloads the provider plugin
- **State file is critical** — never delete `terraform.tfstate` manually
- **`terraform plan` before every apply** — always review what will change
- **Variables with `sensitive = true`** — values are hidden in plan output
- **`terraform fmt`** — run this before committing; CI will fail without it
- **Provider version pinning** — always pin `~> 3.90` not `>= 3.0` to avoid breaking changes

## Code

See `code/terraform_runner.py` — Python wrapper for all Terraform commands with colored output and error handling.

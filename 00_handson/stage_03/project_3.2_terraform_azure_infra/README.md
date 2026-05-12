# Project 3.2 — Full Azure Infrastructure with Terraform

## What It Does

Provisions a complete Azure infrastructure stack using Terraform:
- **Resource Group** — container for all resources
- **Virtual Network** — 3-subnet network (web, app, db)
- **NSG** — security rules for each subnet
- **Linux VM** — web server in the web subnet
- **Application Gateway** — L7 load balancer
- **Azure SQL** — managed database

This is a realistic "production-like" infrastructure you'd use as a starting point for real projects.

## Azure Services Used

| Service | Purpose |
|---|---|
| Resource Group | Logical container |
| Virtual Network + 3 Subnets | Network isolation |
| NSG | Traffic filtering |
| Linux VM (B2s) | Web server |
| Application Gateway Standard_v2 | Load balancer |
| Azure SQL Server + Database | Managed database |

## How to Deploy

```bash
cd terraform/
terraform init
terraform plan \
  -var="sql_admin_password=YourP@ssw0rd123" \
  -out=tfplan
terraform apply tfplan
```

### Verify
```bash
pip install azure-mgmt-network azure-mgmt-compute azure-mgmt-sql azure-identity
python code/infra_validator.py --resource-group rg-full-infra
```

### Destroy
```bash
terraform destroy -var="sql_admin_password=YourP@ssw0rd123"
```

## File Structure

```
terraform/
├── main.tf        # All resources
├── variables.tf   # Input variables
└── outputs.tf     # Output values
```

## Lessons Learned

- **Terraform dependency graph** — resources are created in the right order automatically based on references
- **`depends_on`** — use when Terraform can't infer the dependency (e.g., role assignments)
- **`lifecycle { prevent_destroy = true }`** — protect production databases from accidental destroy
- **`terraform plan -out=tfplan`** — save the plan and apply exactly that plan (no surprises)
- **Sensitive outputs** — mark passwords and keys as `sensitive = true` to hide from logs
- **`random_string` resource** — use for globally unique names (storage accounts, SQL servers)

## Code

See `code/infra_validator.py` — validates each resource exists and is in the expected state.

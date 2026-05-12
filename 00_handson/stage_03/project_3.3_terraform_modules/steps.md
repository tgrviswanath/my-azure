# Deployment Steps — Terraform Modules

## Phase 1: Create Module Structure

```bash
# 1.1 Review the module structure
ls terraform/modules/
# vnet/  vm/  sql/

# 1.2 Review a module
cat terraform/modules/vnet/main.tf
cat terraform/modules/vnet/variables.tf
cat terraform/modules/vnet/outputs.tf

# 1.3 Review how main.tf calls modules
cat terraform/main.tf
# module "vnet" {
#   source = "./modules/vnet"
#   ...
# }

# 1.4 Initialize (downloads providers for all modules)
cd terraform/
terraform init
```

---

## Phase 2: Deploy Dev Environment

```bash
# 2.1 Create dev workspace
terraform workspace new dev
terraform workspace show  # Should show: dev

# 2.2 Review dev variables
cat envs/dev.tfvars
# environment = "dev"
# vm_size = "Standard_B1s"
# vm_count = 1
# sql_sku = "Basic"

# 2.3 Plan dev
terraform plan \
  -var-file="envs/dev.tfvars" \
  -var="sql_admin_password=DevP@ssw0rd123" \
  -out=tfplan-dev

# 2.4 Apply dev
terraform apply tfplan-dev

# 2.5 Verify
terraform output
az resource list --resource-group rg-modules-dev --output table
```

---

## Phase 3: Deploy QA Environment

```bash
# 3.1 Switch to qa workspace
terraform workspace new qa
terraform workspace show  # Should show: qa

# 3.2 Plan qa (different sizes)
terraform plan \
  -var-file="envs/qa.tfvars" \
  -var="sql_admin_password=QaP@ssw0rd123" \
  -out=tfplan-qa

# 3.3 Apply qa
terraform apply tfplan-qa

# 3.4 List all workspaces
terraform workspace list
#   default
#   dev
# * qa
```

---

## Phase 4: Deploy Prod Environment

```bash
# 4.1 Switch to prod workspace
terraform workspace new prod
terraform workspace show  # Should show: prod

# 4.2 Plan prod (larger sizes)
terraform plan \
  -var-file="envs/prod.tfvars" \
  -var="sql_admin_password=ProdP@ssw0rd123!" \
  -out=tfplan-prod

# 4.3 Review plan carefully before applying to prod
terraform show tfplan-prod | head -100

# 4.4 Apply prod (use env_switcher.py for safety)
python code/env_switcher.py --env prod --action apply
# Will prompt: "You are about to apply to PROD. Type 'yes' to confirm:"
```

---

## Phase 5: Compare Costs

```bash
# 5.1 Show cost estimate per environment
python code/env_switcher.py --show-costs

# 5.2 List resources per environment
for env in dev qa prod; do
  echo "=== $env ==="
  az resource list --resource-group rg-modules-$env --output table 2>/dev/null || echo "Not deployed"
done

# 5.3 Destroy dev (cheapest to keep, but clean up when done)
terraform workspace select dev
terraform destroy \
  -var-file="envs/dev.tfvars" \
  -var="sql_admin_password=DevP@ssw0rd123"

# 5.4 Destroy all environments
for env in dev qa prod; do
  terraform workspace select $env
  terraform destroy -var-file="envs/$env.tfvars" -var="sql_admin_password=P@ssw0rd123" -auto-approve
done
```

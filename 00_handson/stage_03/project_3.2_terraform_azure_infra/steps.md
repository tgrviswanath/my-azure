# Deployment Steps — Full Azure Infrastructure

## Phase 1: Initialize

```bash
# 1.1 Navigate to terraform directory
cd terraform/

# 1.2 Initialize
terraform init

# 1.3 Format and validate
terraform fmt -recursive
terraform validate

# 1.4 Review the plan
terraform plan \
  -var="sql_admin_password=YourP@ssw0rd123" \
  -out=tfplan

# Expected: ~15 resources to add
```

---

## Phase 2: Plan

```bash
# 2.1 Review the plan output carefully
# Look for:
#   + azurerm_resource_group.main
#   + azurerm_virtual_network.main
#   + azurerm_subnet.web / app / db
#   + azurerm_network_security_group.web / app / db
#   + azurerm_public_ip.appgw / vm
#   + azurerm_application_gateway.main
#   + azurerm_network_interface.vm
#   + azurerm_linux_virtual_machine.web
#   + azurerm_mssql_server.main
#   + azurerm_mssql_database.app

# 2.2 Save plan to file for safe apply
terraform plan \
  -var="sql_admin_password=YourP@ssw0rd123" \
  -out=tfplan

# 2.3 Show the saved plan
terraform show tfplan
```

---

## Phase 3: Apply

```bash
# 3.1 Apply the saved plan
terraform apply tfplan

# This will take 5-10 minutes (App Gateway takes longest)

# 3.2 Watch progress
# Terraform shows each resource as it's created:
# azurerm_resource_group.main: Creating...
# azurerm_resource_group.main: Creation complete after 2s
# azurerm_virtual_network.main: Creating...
# ...

# 3.3 Show outputs after apply
terraform output
```

---

## Phase 4: Verify Resources

```bash
# 4.1 List all resources in the group
az resource list \
  --resource-group rg-full-infra \
  --output table

# 4.2 Check VNet
az network vnet show \
  --resource-group rg-full-infra \
  --name vnet-full-infra \
  --query "{name:name, addressSpace:addressSpace.addressPrefixes}" \
  --output table

# 4.3 Check VM
az vm show \
  --resource-group rg-full-infra \
  --name vm-web \
  --show-details \
  --query "{name:name, powerState:powerState, publicIp:publicIps}" \
  --output table

# 4.4 Check App Gateway
az network application-gateway show \
  --resource-group rg-full-infra \
  --name appgw-full-infra \
  --query "{name:name, state:operationalState}" \
  --output table

# 4.5 Check SQL
SQL_SERVER=$(terraform output -raw sql_server_name)
az sql db show \
  --resource-group rg-full-infra \
  --server $SQL_SERVER \
  --name db-app \
  --query "{name:name, status:status}" \
  --output table

# 4.6 Run Python validator
pip install azure-mgmt-network azure-mgmt-compute azure-mgmt-sql azure-identity
python code/infra_validator.py --resource-group rg-full-infra
```

---

## Phase 5: Destroy

```bash
# 5.1 Plan the destroy first
terraform plan -destroy \
  -var="sql_admin_password=YourP@ssw0rd123"

# 5.2 Destroy all resources
terraform destroy \
  -var="sql_admin_password=YourP@ssw0rd123"
# Type 'yes' when prompted

# 5.3 Verify everything is gone
az group show --name rg-full-infra
# Expected: ResourceGroupNotFound error

# 5.4 Clean up local state
rm -f tfplan terraform.tfstate terraform.tfstate.backup
```

# Deployment Steps — Failure Simulation

## Phase 1: Deploy Test Environment

```bash
# 1.1 Create resource group
az group create --name rg-chaos-lab --location eastus

# 1.2 Create VNet
az network vnet create \
  --resource-group rg-chaos-lab \
  --name vnet-chaos \
  --address-prefix 10.3.0.0/16

az network vnet subnet create \
  --resource-group rg-chaos-lab \
  --vnet-name vnet-chaos \
  --name subnet-vms \
  --address-prefix 10.3.1.0/24

# 1.3 Create NSG with allow rules
az network nsg create \
  --resource-group rg-chaos-lab \
  --name nsg-chaos

az network nsg rule create \
  --resource-group rg-chaos-lab \
  --nsg-name nsg-chaos \
  --name Allow-SSH \
  --priority 100 \
  --protocol Tcp \
  --destination-port-range 22 \
  --access Allow \
  --direction Inbound

az network nsg rule create \
  --resource-group rg-chaos-lab \
  --nsg-name nsg-chaos \
  --name Allow-HTTP \
  --priority 110 \
  --protocol Tcp \
  --destination-port-range 80 \
  --access Allow \
  --direction Inbound

az network vnet subnet update \
  --resource-group rg-chaos-lab \
  --vnet-name vnet-chaos \
  --name subnet-vms \
  --network-security-group nsg-chaos

# 1.4 Create test VM
az vm create \
  --resource-group rg-chaos-lab \
  --name vm-chaos-target \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --vnet-name vnet-chaos \
  --subnet subnet-vms \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-sku Standard

# 1.5 Create Azure SQL
az sql server create \
  --resource-group rg-chaos-lab \
  --name sql-chaos-$(date +%s) \
  --location eastus \
  --admin-user sqladmin \
  --admin-password "ChaosP@ssw0rd123"

SQL_SERVER=$(az sql server list --resource-group rg-chaos-lab --query "[0].name" -o tsv)

az sql db create \
  --resource-group rg-chaos-lab \
  --server $SQL_SERVER \
  --name db-chaos \
  --service-objective Basic

# 1.6 Verify everything is running
az vm list --resource-group rg-chaos-lab --show-details --output table
az sql server list --resource-group rg-chaos-lab --output table
```

---

## Phase 2: Simulate VM Failure

```bash
# 2.1 Check VM status before
az vm show \
  --resource-group rg-chaos-lab \
  --name vm-chaos-target \
  --show-details \
  --query "{name:name, powerState:powerState}" \
  --output table

# 2.2 Run chaos: stop VM
python code/chaos_simulator.py stop-vm \
  --resource-group rg-chaos-lab \
  --vm-name vm-chaos-target

# 2.3 Verify VM is deallocated
az vm show \
  --resource-group rg-chaos-lab \
  --name vm-chaos-target \
  --show-details \
  --query "{name:name, powerState:powerState}" \
  --output table

# 2.4 Try to SSH (should fail)
VM_IP=$(az vm show --resource-group rg-chaos-lab --name vm-chaos-target \
  --show-details --query publicIps -o tsv)
ssh azureuser@$VM_IP  # This should time out or fail
```

---

## Phase 3: Simulate NSG Lockout

```bash
# 3.1 Verify connectivity before
VM_IP=$(az vm show --resource-group rg-chaos-lab --name vm-chaos-target \
  --show-details --query publicIps -o tsv)
curl -m 5 http://$VM_IP/  # Should respond (or timeout if no web server)

# 3.2 Run chaos: block NSG
python code/chaos_simulator.py block-nsg \
  --resource-group rg-chaos-lab \
  --nsg-name nsg-chaos

# 3.3 Verify NSG rules are gone
az network nsg rule list \
  --resource-group rg-chaos-lab \
  --nsg-name nsg-chaos \
  --output table

# 3.4 Try to connect (should fail)
curl -m 5 http://$VM_IP/  # Should time out
```

---

## Phase 4: Simulate DB Failure

```bash
# 4.1 Check SQL server status
SQL_SERVER=$(az sql server list --resource-group rg-chaos-lab --query "[0].name" -o tsv)
az sql db show \
  --resource-group rg-chaos-lab \
  --server $SQL_SERVER \
  --name db-chaos \
  --query "{name:name, status:status}" \
  --output table

# 4.2 Run chaos: simulate DB failure
python code/chaos_simulator.py simulate-db-fail \
  --resource-group rg-chaos-lab

# 4.3 Observe: connection strings will fail for 20-30 seconds during failover
# In a real app, you'd see connection errors here

# 4.4 Check DB status after failover
az sql db show \
  --resource-group rg-chaos-lab \
  --server $SQL_SERVER \
  --name db-chaos \
  --query "{name:name, status:status}" \
  --output table
```

---

## Phase 5: Restore Everything

```bash
# 5.1 Run restore (reads rollback.json)
python code/chaos_simulator.py restore \
  --resource-group rg-chaos-lab

# 5.2 Verify VM is running again
az vm show \
  --resource-group rg-chaos-lab \
  --name vm-chaos-target \
  --show-details \
  --query "{name:name, powerState:powerState}" \
  --output table

# 5.3 Verify NSG rules are restored
az network nsg rule list \
  --resource-group rg-chaos-lab \
  --nsg-name nsg-chaos \
  --output table

# 5.4 Cleanup
az group delete --name rg-chaos-lab --yes --no-wait
```

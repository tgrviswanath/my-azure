# Steps — Project 1.5 Python Azure Automation

## Phase 1 — Install Azure SDK

### 1.1 Install required packages
```bash
pip install azure-identity \
            azure-storage-blob \
            azure-mgmt-compute \
            azure-mgmt-resource \
            azure-mgmt-storage
```

### 1.2 Verify installation
```bash
python -c "from azure.identity import DefaultAzureCredential; print('OK')"
python -c "from azure.storage.blob import BlobServiceClient; print('OK')"
```

---

## Phase 2 — Authenticate with DefaultAzureCredential

### 2.1 Login via Azure CLI (for local development)
```bash
az login
az account show
```

### 2.2 Set subscription (if you have multiple)
```bash
az account set --subscription "Your Subscription Name"
```

### 2.3 Test authentication in Python
```python
from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import ResourceManagementClient
import os

credential = DefaultAzureCredential()
subscription_id = os.environ["AZURE_SUBSCRIPTION_ID"]

client = ResourceManagementClient(credential, subscription_id)
groups = list(client.resource_groups.list())
print(f"Found {len(groups)} resource groups")
```

---

## Phase 3 — Upload Blobs

### 3.1 Deploy storage account with Terraform
```bash
cd terraform
terraform init
terraform apply -auto-approve
terraform output storage_account_name
```

### 3.2 Create sample data to upload
```bash
mkdir -p sample_data
echo '{"id":1,"name":"product-a"}' > sample_data/product_a.json
echo '{"id":2,"name":"product-b"}' > sample_data/product_b.json
echo "Report data" > sample_data/report.txt
```

### 3.3 Run blob uploader
```bash
export AZURE_STORAGE_ACCOUNT="your-storage-account-name"
python scripts/blob_uploader.py
```

### 3.4 Verify uploads
```bash
az storage blob list \
  --account-name $AZURE_STORAGE_ACCOUNT \
  --container-name uploads \
  --auth-mode login \
  --output table
```

---

## Phase 4 — Start/Stop VMs

### 4.1 List VMs in a resource group
```bash
az vm list --resource-group my-rg --output table
```

### 4.2 Stop a VM (deallocate to stop billing)
```bash
az vm deallocate \
  --resource-group my-rg \
  --name my-vm \
  --no-wait
```

### 4.3 Start a VM
```bash
az vm start \
  --resource-group my-rg \
  --name my-vm
```

### 4.4 Automate with Python
```python
from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient

credential = DefaultAzureCredential()
compute_client = ComputeManagementClient(credential, subscription_id)

# Deallocate (stop billing)
poller = compute_client.virtual_machines.begin_deallocate(resource_group, vm_name)
poller.result()  # Wait for completion
```

---

## Phase 5 — Automate Backups

### 5.1 Sync a local folder to blob storage
```bash
python scripts/blob_uploader.py --mode sync --folder ./backups --container backups
```

### 5.2 Schedule with cron (Linux/macOS)
```bash
# Run backup every day at 2 AM
crontab -e
# Add:
0 2 * * * /usr/bin/python3 /path/to/scripts/blob_uploader.py --mode sync
```

### 5.3 Schedule with Task Scheduler (Windows)
```powershell
$action = New-ScheduledTaskAction -Execute "python" -Argument "C:\scripts\blob_uploader.py"
$trigger = New-ScheduledTaskTrigger -Daily -At 2am
Register-ScheduledTask -TaskName "AzureBackup" -Action $action -Trigger $trigger
```

---

## Screenshots to Take
- [ ] `az login` successful
- [ ] Blob uploader output showing files uploaded with progress
- [ ] Blobs listed in Azure Portal
- [ ] VM start/stop automation output
- [ ] Sync operation showing new/changed/unchanged files

# Steps — Project 0.1 Local Cloud Development Setup

## Phase 1 — Install Tools

### 1.1 Install Docker Desktop
```bash
docker --version
docker compose version
```
Expected: Docker version 24.x.x or higher

### 1.2 Install Azure CLI
```bash
# macOS
brew install azure-cli

# Windows
winget install Microsoft.AzureCLI

# Verify
az --version
```

### 1.3 Install Azure Functions Core Tools
```bash
npm install -g azure-functions-core-tools@4
func --version
```

### 1.4 Install Terraform
```bash
# Windows (via Chocolatey)
choco install terraform

# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

terraform --version
```

### 1.5 Install Python Azure SDKs
```bash
pip install azure-storage-blob azure-storage-queue azure-storage-file-datalake
pip install azure-identity azure-mgmt-storage
```

---

## Phase 2 — Start Azurite

### 2.1 Start all services
```bash
docker compose up -d
```

### 2.2 Verify Azurite is running
```bash
docker compose ps
curl http://localhost:10000/devstoreaccount1
# Expected: XML response with StorageServiceProperties
```

### 2.3 Check logs
```bash
docker compose logs azurite
```

---

## Phase 3 — Test Blob Storage Locally

### 3.1 Set connection string
```bash
# Linux/macOS
export AZURE_STORAGE_CONNECTION_STRING="UseDevelopmentStorage=true"

# Windows PowerShell
$env:AZURE_STORAGE_CONNECTION_STRING = "UseDevelopmentStorage=true"
```

### 3.2 Create container and upload blob
```bash
az storage container create --name test-container
echo "Hello Azurite" > test.txt
az storage blob upload --container-name test-container --file test.txt --name test.txt
az storage blob list --container-name test-container --output table
```

### 3.3 Download and verify
```bash
az storage blob download --container-name test-container --name test.txt --file downloaded.txt
cat downloaded.txt
```

---

## Phase 4 — Run Azure Function Locally

### 4.1 Create a new Function project
```bash
func init MyFunctionApp --python
cd MyFunctionApp
func new --name HttpTrigger --template "HTTP trigger"
```

### 4.2 Start the function host
```bash
func start
```

### 4.3 Test the function
```bash
curl "http://localhost:7071/api/HttpTrigger?name=Azure"
# Expected: Hello, Azure. This HTTP triggered function executed successfully.
```

---

## Phase 5 — Terraform with Azurite

```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
terraform output
```

---

## Phase 6 — Run Python Demo

```bash
python code/azurite_demo.py
```

Expected output:
- Blob container created
- 3 files uploaded
- Queue created
- 3 messages sent and received

---

## Screenshots to Take
- [ ] `docker compose up` showing Azurite healthy
- [ ] Blob container created and file uploaded via CLI
- [ ] Azure Function running locally on port 7071
- [ ] Queue message sent and received
- [ ] Python demo output showing all operations

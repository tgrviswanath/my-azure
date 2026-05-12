# Steps — Project 1.1 Static Website on Azure Storage + CDN

## Phase 1 — Create Storage Account

### 1.1 Deploy with Terraform
```bash
cd terraform
terraform init
terraform apply -auto-approve
terraform output
```

### 1.2 Or create manually via CLI
```bash
RESOURCE_GROUP="static-website-rg"
STORAGE_ACCOUNT="mystaticsite$(date +%s)"  # must be globally unique
LOCATION="eastus"

az group create --name $RESOURCE_GROUP --location $LOCATION

az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2
```

---

## Phase 2 — Enable Static Website

### 2.1 Enable static website hosting
```bash
az storage blob service-properties update \
  --account-name $STORAGE_ACCOUNT \
  --static-website \
  --index-document index.html \
  --404-document 404.html
```

### 2.2 Verify the $web container was created
```bash
az storage container list \
  --account-name $STORAGE_ACCOUNT \
  --output table
# Should see: $web container
```

### 2.3 Get the static website URL
```bash
az storage account show \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --query "primaryEndpoints.web" \
  --output tsv
```

---

## Phase 3 — Upload Website Files

### 3.1 Upload index.html
```bash
az storage blob upload \
  --account-name $STORAGE_ACCOUNT \
  --container-name '$web' \
  --file code/index.html \
  --name index.html \
  --content-type "text/html"
```

### 3.2 Upload all files at once
```bash
az storage blob upload-batch \
  --account-name $STORAGE_ACCOUNT \
  --source ./code/website/ \
  --destination '$web' \
  --content-type "text/html"
```

### 3.3 Test the static website
```bash
WEBSITE_URL=$(az storage account show \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --query "primaryEndpoints.web" -o tsv)

curl $WEBSITE_URL
```

---

## Phase 4 — Create CDN Endpoint

### 4.1 Create CDN profile
```bash
az cdn profile create \
  --name static-site-cdn \
  --resource-group $RESOURCE_GROUP \
  --sku Standard_Microsoft
```

### 4.2 Create CDN endpoint
```bash
ORIGIN=$(az storage account show \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --query "primaryEndpoints.web" -o tsv | sed 's|https://||' | sed 's|/||')

az cdn endpoint create \
  --name mystaticsite-endpoint \
  --profile-name static-site-cdn \
  --resource-group $RESOURCE_GROUP \
  --origin $ORIGIN \
  --origin-host-header $ORIGIN
```

### 4.3 Test CDN endpoint
```bash
curl https://mystaticsite-endpoint.azureedge.net
```

---

## Phase 5 — Custom Domain + HTTPS

### 5.1 Add CNAME record in your DNS provider
```
CNAME: www → mystaticsite-endpoint.azureedge.net
```

### 5.2 Add custom domain to CDN endpoint
```bash
az cdn custom-domain create \
  --endpoint-name mystaticsite-endpoint \
  --profile-name static-site-cdn \
  --resource-group $RESOURCE_GROUP \
  --name www-domain \
  --hostname www.yourdomain.com
```

### 5.3 Enable HTTPS (free managed certificate)
```bash
az cdn custom-domain enable-https \
  --endpoint-name mystaticsite-endpoint \
  --profile-name static-site-cdn \
  --resource-group $RESOURCE_GROUP \
  --name www-domain
```

### 5.4 Purge CDN cache after updates
```bash
az cdn endpoint purge \
  --name mystaticsite-endpoint \
  --profile-name static-site-cdn \
  --resource-group $RESOURCE_GROUP \
  --content-paths "/*"
```

---

## Screenshots to Take
- [ ] Storage account with static website enabled
- [ ] Website loading from Storage URL
- [ ] CDN endpoint created and responding
- [ ] HTTPS working on CDN endpoint

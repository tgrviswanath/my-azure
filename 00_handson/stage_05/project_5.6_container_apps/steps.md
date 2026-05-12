# Steps — Project 5.6 Azure Container Apps

## Phase 1 — Deploy
```bash
cd terraform && terraform init && terraform apply -auto-approve
terraform output app_url
```

## Phase 2 — Test
```bash
APP_URL=$(terraform output -raw app_url)
curl $APP_URL/health
curl $APP_URL/
```

## Phase 3 — Update Revision
```bash
az containerapp update \
  --name ca-myapp \
  --resource-group rg-container-apps \
  --image acrhandson001.azurecr.io/myapp:v2.0
```

## Screenshots to Take
- [ ] Container App running with public URL
- [ ] App responding to requests
- [ ] Scale-to-zero working (0 replicas when idle)

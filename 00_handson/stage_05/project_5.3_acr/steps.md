# Steps — Project 5.3 Push Containers to ACR

## Phase 1 — Create ACR
```bash
cd terraform && terraform init && terraform apply -auto-approve
```

## Phase 2 — Build and Push
```bash
az acr login --name acrhandson001

# Build locally and push
docker build -t myapp:latest ../project_5.1_single_docker_app/
docker tag myapp:latest acrhandson001.azurecr.io/myapp:v1.0
docker push acrhandson001.azurecr.io/myapp:v1.0

# OR build directly in ACR (no local Docker needed)
az acr build --registry acrhandson001 \
  --image myapp:v1.0 \
  ../project_5.1_single_docker_app/
```

## Phase 3 — List Images
```bash
az acr repository list --name acrhandson001 --output table
az acr repository show-tags --name acrhandson001 --repository myapp --output table
```

## Screenshots to Take
- [ ] ACR created in portal
- [ ] Image pushed successfully
- [ ] Image listed in ACR repository

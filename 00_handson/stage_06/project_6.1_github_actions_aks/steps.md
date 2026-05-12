# Steps — Project 6.1 GitHub Actions CI/CD to AKS

## Phase 1 — Create ACR and AKS

```bash
cd stage_06/project_6.1_github_actions_aks/terraform

# Initialize and deploy
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Capture outputs
export ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server)
export ACR_ID=$(terraform output -raw acr_id)
export AKS_CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
export AKS_RESOURCE_GROUP=$(terraform output -raw resource_group_name)
export AKS_ID=$(terraform output -raw aks_id)

echo "ACR: $ACR_LOGIN_SERVER"
echo "AKS: $AKS_CLUSTER_NAME in $AKS_RESOURCE_GROUP"

# Verify ACR is accessible
az acr login --name $(terraform output -raw acr_name)
az acr show --name $(terraform output -raw acr_name) --query "loginServer" -o tsv

# Verify AKS cluster is running
az aks get-credentials \
  --resource-group $AKS_RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --overwrite-existing

kubectl get nodes
# Expected: 2 nodes in Ready state
```

## Phase 2 — Create Service Principal

```bash
# Create SP with AcrPush permission on the registry
az ad sp create-for-rbac \
  --name "sp-github-actions-proj61" \
  --role "AcrPush" \
  --scopes $ACR_ID \
  --sdk-auth > sp_credentials.json

cat sp_credentials.json
# Save this JSON — it goes into GitHub secret AZURE_CREDENTIALS

# Extract the SP client ID
SP_CLIENT_ID=$(cat sp_credentials.json | python3 -c "import sys,json; print(json.load(sys.stdin)['clientId'])")
echo "SP Client ID: $SP_CLIENT_ID"

# Grant AKS Cluster User Role so the SP can get kubeconfig
az role assignment create \
  --assignee $SP_CLIENT_ID \
  --role "Azure Kubernetes Service Cluster User Role" \
  --scope $AKS_ID

# Grant the AKS kubelet identity AcrPull so nodes can pull images
KUBELET_IDENTITY=$(az aks show \
  --resource-group $AKS_RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --query "identityProfile.kubeletidentity.objectId" -o tsv)

az role assignment create \
  --assignee $KUBELET_IDENTITY \
  --role "AcrPull" \
  --scope $ACR_ID

echo "Kubelet identity $KUBELET_IDENTITY granted AcrPull on ACR"
```

## Phase 3 — Configure GitHub Secrets

```bash
# Using GitHub CLI (gh) to set secrets
# Install: https://cli.github.com/

gh auth login

# Set all required secrets
gh secret set AZURE_CREDENTIALS < sp_credentials.json

gh secret set ACR_LOGIN_SERVER --body "$ACR_LOGIN_SERVER"
gh secret set ACR_NAME --body "$(terraform output -raw acr_name)"
gh secret set AKS_CLUSTER_NAME --body "$AKS_CLUSTER_NAME"
gh secret set AKS_RESOURCE_GROUP --body "$AKS_RESOURCE_GROUP"

# Verify secrets are set (values are masked)
gh secret list
# Expected output:
# AZURE_CREDENTIALS    Updated 2024-01-15
# ACR_LOGIN_SERVER     Updated 2024-01-15
# ACR_NAME             Updated 2024-01-15
# AKS_CLUSTER_NAME     Updated 2024-01-15
# AKS_RESOURCE_GROUP   Updated 2024-01-15
```

## Phase 4 — Create Workflow File

```bash
# Create the GitHub Actions workflow directory
mkdir -p .github/workflows

# Copy the workflow file
cp code/deploy.yml .github/workflows/deploy.yml

# Also create a sample Dockerfile and app if not present
cat > Dockerfile <<'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8080
CMD ["python", "app.py"]
EOF

cat > app.py <<'EOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
import os

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        version = os.environ.get("APP_VERSION", "1.0.0")
        self.wfile.write(f"Hello from AKS! Version: {version}\n".encode())

if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
EOF

echo "flask" > requirements.txt

# Commit and push to trigger the pipeline
git add .github/workflows/deploy.yml Dockerfile app.py requirements.txt
git commit -m "feat: add CI/CD pipeline and sample app"
git push origin main
```

## Phase 5 — Test Pipeline

```bash
# Watch the pipeline run in real time
gh run list --limit 5
gh run watch

# Once complete, verify the deployment
kubectl get deployments -n default
kubectl get pods -n default
kubectl get service myapp-service -n default

# Get the external IP of the LoadBalancer service
EXTERNAL_IP=$(kubectl get service myapp-service \
  -n default \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "App URL: http://$EXTERNAL_IP:8080"
curl http://$EXTERNAL_IP:8080
# Expected: Hello from AKS! Version: 1.0.0

# Run the Python verification script
cd code
export AKS_CLUSTER_NAME=$AKS_CLUSTER_NAME
export AKS_RESOURCE_GROUP=$AKS_RESOURCE_GROUP
python deploy_check.py

# Test rollback
kubectl rollout undo deployment/myapp
kubectl rollout status deployment/myapp

# Clean up
cd ../terraform
terraform destroy -auto-approve
```

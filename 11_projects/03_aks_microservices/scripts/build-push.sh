#!/bin/bash
# Build and push all microservice images to ACR
set -euo pipefail

ACR_NAME="acrmicrservicesprod"
ACR_LOGIN="${ACR_NAME}.azurecr.io"
IMAGE_TAG="${1:-$(git rev-parse --short HEAD 2>/dev/null || echo 'latest')}"

SERVICES=("order-service" "product-service" "user-service" "notification-service")

echo "=== Building and Pushing Images ==="
echo "ACR: $ACR_LOGIN | Tag: $IMAGE_TAG"

# Login to ACR
az acr login --name $ACR_NAME

for SERVICE in "${SERVICES[@]}"; do
  SERVICE_DIR="../../services/$SERVICE"

  if [ ! -d "$SERVICE_DIR" ]; then
    echo "WARNING: $SERVICE_DIR not found, skipping"
    continue
  fi

  echo "Building $SERVICE:$IMAGE_TAG..."

  # Build using ACR Tasks (builds in cloud, no local Docker needed)
  az acr build \
    --registry $ACR_NAME \
    --image "$SERVICE:$IMAGE_TAG" \
    --image "$SERVICE:latest" \
    --file "$SERVICE_DIR/Dockerfile" \
    "$SERVICE_DIR"

  echo "✅ $SERVICE pushed to $ACR_LOGIN/$SERVICE:$IMAGE_TAG"
done

echo ""
echo "=== All images pushed ==="
echo "Update k8s manifests with tag: $IMAGE_TAG"
echo "  sed -i 's|:latest|:$IMAGE_TAG|g' ../k8s/*.yaml"

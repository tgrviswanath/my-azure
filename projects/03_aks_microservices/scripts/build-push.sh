#!/bin/bash
# Project 03 — Build and Push Microservice Images to ACR
set -euo pipefail

ACR_NAME="${ACR_NAME:?Set ACR_NAME environment variable}"
TAG="${TAG:-$(git rev-parse --short HEAD 2>/dev/null || echo 'latest')}"
SERVICES=("order-service" "product-service" "user-service" "notification-service")

echo "🐳 Building and pushing microservice images"
echo "   ACR: $ACR_NAME"
echo "   Tag: $TAG"

# Login to ACR
az acr login --name $ACR_NAME

# Build each service
for SERVICE in "${SERVICES[@]}"; do
  SERVICE_DIR="services/${SERVICE}"

  if [ ! -d "$SERVICE_DIR" ]; then
    echo "⚠️  Service directory not found: $SERVICE_DIR — creating sample"
    mkdir -p "$SERVICE_DIR"

    # Create minimal Dockerfile for demo
    cat > "$SERVICE_DIR/Dockerfile" << EOF
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production 2>/dev/null || true
COPY . .
RUN addgroup -S app && adduser -S app -G app
USER app
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:3000/health || exit 1
CMD ["node", "server.js"]
EOF

    # Create minimal server
    cat > "$SERVICE_DIR/server.js" << EOF
const http = require('http');
const SERVICE = '${SERVICE}';
const PORT = process.env.PORT || 3000;
const server = http.createServer((req, res) => {
  if (req.url === '/health') return res.end(JSON.stringify({status:'ok',service:SERVICE}));
  if (req.url === '/ready')  return res.end(JSON.stringify({ready:true}));
  res.end(JSON.stringify({service:SERVICE,version:process.env.APP_VERSION||'v1',hostname:require('os').hostname()}));
});
server.listen(PORT, () => console.log(\`\${SERVICE} on port \${PORT}\`));
EOF

    echo '{"name":"'$SERVICE'","version":"1.0.0","scripts":{"start":"node server.js"}}' > "$SERVICE_DIR/package.json"
  fi

  echo ""
  echo "📦 Building: $SERVICE:$TAG"

  # Build
  az acr build \
    --registry $ACR_NAME \
    --image "${SERVICE}:${TAG}" \
    --image "${SERVICE}:latest" \
    --file "${SERVICE_DIR}/Dockerfile" \
    "$SERVICE_DIR/" \
    --no-logs

  echo "✅ Pushed: ${ACR_NAME}.azurecr.io/${SERVICE}:${TAG}"
done

echo ""
echo "✅ All images built and pushed!"
echo ""
echo "Images:"
for SERVICE in "${SERVICES[@]}"; do
  echo "  ${ACR_NAME}.azurecr.io/${SERVICE}:${TAG}"
done
echo ""
echo "Next: kubectl apply -f k8s/ to deploy"

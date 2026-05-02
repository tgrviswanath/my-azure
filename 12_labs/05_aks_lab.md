# Lab 05 — Deploy Application on AKS

## Objective
Create an AKS cluster, deploy a containerized application with auto-scaling, configure monitoring, and implement rolling updates.

## Prerequisites
- Azure subscription
- Azure CLI + kubectl + Docker installed
- Estimated time: 90 minutes
- Estimated cost: ~$2 (3 B2s nodes for 1 hour)

## Step 1: Create Infrastructure

```bash
RG="rg-lab05-dev-eastus"
LOCATION="eastus"
CLUSTER_NAME="aks-lab05"
ACR_NAME="acrlab05$(openssl rand -hex 4)"

az group create --name $RG --location $LOCATION

# Create ACR
az acr create \
  --name $ACR_NAME \
  --resource-group $RG \
  --sku Basic \
  --admin-enabled false

# Create Log Analytics workspace
LAW_ID=$(az monitor log-analytics workspace create \
  --workspace-name "law-lab05" \
  --resource-group $RG \
  --location $LOCATION \
  --query id --output tsv)

# Create AKS cluster
az aks create \
  --resource-group $RG \
  --name $CLUSTER_NAME \
  --node-count 2 \
  --node-vm-size Standard_B2s \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 5 \
  --network-plugin azure \
  --enable-managed-identity \
  --enable-addons monitoring \
  --workspace-resource-id $LAW_ID \
  --generate-ssh-keys \
  --attach-acr $ACR_NAME

# Get credentials
az aks get-credentials \
  --resource-group $RG \
  --name $CLUSTER_NAME \
  --overwrite-existing

# Verify
kubectl get nodes
kubectl get pods --all-namespaces
```

## Step 2: Build and Push Container Image

```bash
# Create sample Node.js app
mkdir lab05-app && cd lab05-app

cat > app.js << 'EOF'
const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;
const VERSION = process.env.APP_VERSION || 'v1';

app.get('/health', (req, res) => res.json({ status: 'ok', version: VERSION }));
app.get('/ready', (req, res) => res.json({ ready: true }));
app.get('/', (req, res) => res.json({
  message: `Hello from AKS Lab! Version: ${VERSION}`,
  hostname: require('os').hostname(),
  timestamp: new Date().toISOString(),
}));

app.listen(PORT, () => console.log(`Server v${VERSION} on port ${PORT}`));
EOF

cat > package.json << 'EOF'
{"name":"lab05-app","version":"1.0.0","scripts":{"start":"node app.js"},"dependencies":{"express":"^4.18.2"}}
EOF

cat > Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN addgroup -S app && adduser -S app -G app
USER app
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:3000/health || exit 1
CMD ["node", "app.js"]
EOF

cd ..

# Build and push to ACR
az acr build \
  --registry $ACR_NAME \
  --image lab05-app:v1 \
  --file lab05-app/Dockerfile \
  lab05-app/

# Verify image
az acr repository list --name $ACR_NAME --output table
az acr repository show-tags --name $ACR_NAME --repository lab05-app --output table
```

## Step 3: Deploy to Kubernetes

```bash
ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer --output tsv)

# Create namespace
kubectl create namespace lab05

# Create deployment
cat > deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lab05-app
  namespace: lab05
  labels:
    app: lab05-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: lab05-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: lab05-app
        version: v1
    spec:
      containers:
      - name: app
        image: ${ACR_LOGIN_SERVER}/lab05-app:v1
        ports:
        - containerPort: 3000
        env:
        - name: APP_VERSION
          value: "v1"
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: lab05-service
  namespace: lab05
spec:
  selector:
    app: lab05-app
  ports:
  - port: 80
    targetPort: 3000
  type: LoadBalancer
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: lab05-hpa
  namespace: lab05
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: lab05-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
EOF

kubectl apply -f deployment.yaml

# Wait for deployment
kubectl rollout status deployment/lab05-app -n lab05

# Get external IP
kubectl get service lab05-service -n lab05 --watch
```

## Step 4: Test the Application

```bash
# Get external IP
EXTERNAL_IP=$(kubectl get service lab05-service -n lab05 \
  --output jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "App URL: http://$EXTERNAL_IP"

# Test endpoints
curl http://$EXTERNAL_IP/
curl http://$EXTERNAL_IP/health

# Check pods
kubectl get pods -n lab05 -o wide
kubectl describe pod -n lab05 -l app=lab05-app
```

## Step 5: Rolling Update (Zero-Downtime)

```bash
# Build v2 image
cat > lab05-app/app.js << 'EOF'
const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;
const VERSION = process.env.APP_VERSION || 'v2';

app.get('/health', (req, res) => res.json({ status: 'ok', version: VERSION }));
app.get('/ready', (req, res) => res.json({ ready: true }));
app.get('/', (req, res) => res.json({
  message: `Hello from AKS Lab! Version: ${VERSION} - UPDATED!`,
  hostname: require('os').hostname(),
  timestamp: new Date().toISOString(),
  newFeature: true,
}));

app.listen(PORT, () => console.log(`Server v${VERSION} on port ${PORT}`));
EOF

az acr build \
  --registry $ACR_NAME \
  --image lab05-app:v2 \
  lab05-app/

# Update deployment (rolling update)
kubectl set image deployment/lab05-app \
  app=${ACR_LOGIN_SERVER}/lab05-app:v2 \
  -n lab05

# Watch rolling update
kubectl rollout status deployment/lab05-app -n lab05

# Verify new version
curl http://$EXTERNAL_IP/

# Rollback if needed
kubectl rollout undo deployment/lab05-app -n lab05
kubectl rollout history deployment/lab05-app -n lab05
```

## Step 6: Load Test and Auto-scaling

```bash
# Install hey (HTTP load generator)
# go install github.com/rakyll/hey@latest

# Generate load to trigger HPA
hey -z 2m -c 50 http://$EXTERNAL_IP/

# Watch HPA in action
kubectl get hpa -n lab05 --watch

# Watch pods scale
kubectl get pods -n lab05 --watch
```

## Step 7: View Monitoring

```bash
# View container logs
kubectl logs -l app=lab05-app -n lab05 --tail=50

# View resource usage
kubectl top pods -n lab05
kubectl top nodes

# View events
kubectl get events -n lab05 --sort-by='.lastTimestamp'

# AKS insights in portal
echo "View in Azure portal:"
echo "  AKS cluster → Insights → Containers"
echo "  AKS cluster → Insights → Nodes"
echo "  AKS cluster → Workbooks"
```

## Cleanup

```bash
kubectl delete namespace lab05
az group delete --name $RG --yes --no-wait
```

## Troubleshooting

| Issue | Command | Fix |
|-------|---------|-----|
| ImagePullBackOff | `kubectl describe pod` | Check ACR attached to AKS |
| Pending pods | `kubectl describe pod` | Check node resources |
| Service no external IP | `kubectl get svc --watch` | Wait 2-3 min for LB provisioning |
| HPA not scaling | `kubectl describe hpa` | Check metrics-server running |
| CrashLoopBackOff | `kubectl logs --previous` | Check app logs for errors |

## Expected Outcomes
- ✅ AKS cluster with 2 nodes
- ✅ App deployed with 2 replicas
- ✅ LoadBalancer service with external IP
- ✅ HPA configured (2-10 replicas)
- ✅ Rolling update with zero downtime
- ✅ Rollback capability
- ✅ Container Insights monitoring

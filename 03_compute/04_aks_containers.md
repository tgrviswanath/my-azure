# Azure Kubernetes Service (AKS) — Production Deep Dive

## AKS Architecture

```
AKS Cluster
├── Control Plane (managed by Azure, free)
│   ├── API Server
│   ├── etcd (cluster state)
│   ├── Scheduler
│   └── Controller Manager
└── Node Pools (you pay for VMs)
    ├── System Node Pool (kube-system pods)
    └── User Node Pools (application pods)
        ├── Node 1 (VM)
        ├── Node 2 (VM)
        └── Node 3 (VM)

Networking Options:
  kubenet:    Simple, NAT, limited features
  Azure CNI:  Each pod gets VNet IP, full VNet integration (recommended)
  Azure CNI Overlay: Pods get overlay IPs, scales better
```

## Cluster Creation

```bash
# Create AKS cluster
az aks create \
  --resource-group $RG \
  --name aks-prod-eastus \
  --node-count 3 \
  --node-vm-size Standard_D4s_v5 \
  --enable-cluster-autoscaler \
  --min-count 2 \
  --max-count 10 \
  --network-plugin azure \
  --network-policy azure \
  --enable-managed-identity \
  --enable-addons monitoring \
  --workspace-resource-id $LAW_ID \
  --zones 1 2 3 \
  --kubernetes-version 1.28 \
  --os-disk-size-gb 128 \
  --generate-ssh-keys \
  --tags Environment=Production

# Get credentials
az aks get-credentials \
  --resource-group $RG \
  --name aks-prod-eastus \
  --overwrite-existing

# Verify
kubectl get nodes
kubectl get pods --all-namespaces

# Add user node pool
az aks nodepool add \
  --resource-group $RG \
  --cluster-name aks-prod-eastus \
  --name gpupool \
  --node-count 2 \
  --node-vm-size Standard_NC6 \
  --node-taints sku=gpu:NoSchedule \
  --labels hardware=gpu
```

## Kubernetes Manifests

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-deployment
  namespace: production
  labels:
    app: api
    version: v1.2.0
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: api
        version: v1.2.0
    spec:
      serviceAccountName: api-sa
      containers:
      - name: api
        image: myregistry.azurecr.io/api:v1.2.0
        ports:
        - containerPort: 3000
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: api-secrets
              key: database-url
        - name: NODE_ENV
          value: "production"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: api
---
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: api-service
  namespace: production
spec:
  selector:
    app: api
  ports:
  - port: 80
    targetPort: 3000
  type: ClusterIP
---
# hpa.yaml — Horizontal Pod Autoscaler
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-deployment
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
---
# ingress.yaml — NGINX Ingress with TLS
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  namespace: production
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/rate-limit: "100"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - api.example.com
    secretName: api-tls
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 80
```

## Azure Container Registry (ACR)

```bash
# Create ACR
az acr create \
  --name myregistry \
  --resource-group $RG \
  --sku Premium \
  --admin-enabled false \
  --zone-redundancy enabled

# Attach ACR to AKS (grants pull permissions)
az aks update \
  --name aks-prod-eastus \
  --resource-group $RG \
  --attach-acr myregistry

# Build and push image
az acr build \
  --registry myregistry \
  --image api:v1.2.0 \
  --file Dockerfile \
  .

# Enable geo-replication
az acr replication create \
  --registry myregistry \
  --location westeurope
```

## AKS Security

```bash
# Enable Azure AD integration
az aks update \
  --resource-group $RG \
  --name aks-prod-eastus \
  --enable-aad \
  --aad-admin-group-object-ids $ADMIN_GROUP_ID

# Enable Azure Policy for AKS
az aks enable-addons \
  --resource-group $RG \
  --name aks-prod-eastus \
  --addons azure-policy

# Enable Workload Identity (replaces pod identity)
az aks update \
  --resource-group $RG \
  --name aks-prod-eastus \
  --enable-oidc-issuer \
  --enable-workload-identity

# Network policy — deny all, allow specific
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF
```

## Interview Questions

### Q1: What is the difference between AKS node pools and why use multiple?
**Answer:**
Node pools are groups of VMs with the same configuration. Use multiple pools for:
- **System pool**: reserved for Kubernetes system components
- **User pools**: application workloads
- **Specialized pools**: GPU nodes, high-memory nodes, spot instances
- **Isolation**: separate dev/prod workloads on different node types
- **Cost optimization**: use spot instances for fault-tolerant workloads

### Q2: How does AKS cluster autoscaler work?
**Answer:**
The cluster autoscaler monitors pods that can't be scheduled (insufficient resources) and adds nodes. It also removes underutilized nodes. Works with HPA (Horizontal Pod Autoscaler) — HPA scales pods, cluster autoscaler scales nodes. Configure min/max node counts per pool.

### Q3: What is the difference between liveness and readiness probes?
**Answer:**
- **Liveness probe**: Is the container alive? If fails, Kubernetes restarts the container.
- **Readiness probe**: Is the container ready to serve traffic? If fails, removes pod from Service endpoints (no traffic sent).
- **Startup probe**: Has the container started? Delays liveness/readiness checks for slow-starting apps.

### Q4: How do you manage secrets in AKS?
**Answer:**
1. **Kubernetes Secrets** (base64 encoded, not encrypted by default)
2. **Azure Key Vault + CSI driver**: mount secrets as volumes or env vars
3. **Workload Identity**: pods get Azure AD identity, access Key Vault directly
4. **Sealed Secrets**: encrypt secrets for GitOps
5. **External Secrets Operator**: sync from Key Vault to K8s secrets
Best practice: use Key Vault with Workload Identity.

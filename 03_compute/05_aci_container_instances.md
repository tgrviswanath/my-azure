# Azure Container Instances (ACI) — Deep Dive

## What is ACI?
ACI runs containers directly in Azure without managing VMs or orchestrators. It's the fastest way to run a container in Azure — no cluster setup, no node management.

```
ACI vs AKS vs App Service (Containers):

ACI:         Serverless containers, per-second billing, no orchestration
             → Best for: batch jobs, event-driven tasks, dev/test, CI/CD runners
AKS:         Full Kubernetes, complex orchestration, persistent workloads
             → Best for: microservices, long-running production apps
App Service: PaaS container hosting, built-in scaling, deployment slots
             → Best for: web apps, APIs with simple scaling needs
```

---

## Core Concepts

```
Container Group (top-level resource)
├── One or more containers (share lifecycle, network, storage)
├── Shared IP address and port namespace
├── Shared volumes (Azure Files, emptyDir, secret, gitRepo)
└── Restart policy: Always | OnFailure | Never

OS Types:
  Linux:   Most container workloads
  Windows: Windows-based containers

SKUs:
  Standard: General purpose
  Dedicated: Isolated hardware (compliance requirements)
```

---

## Quick Start

```bash
# Simplest possible container
az container create \
  --resource-group $RG \
  --name aci-hello \
  --image mcr.microsoft.com/azuredocs/aci-helloworld \
  --ports 80 \
  --dns-name-label aci-hello-$RANDOM \
  --location eastus

# Get FQDN and test
FQDN=$(az container show \
  --resource-group $RG \
  --name aci-hello \
  --query ipAddress.fqdn \
  --output tsv)
echo "URL: http://$FQDN"
curl http://$FQDN

# View logs
az container logs --resource-group $RG --name aci-hello

# Stream logs
az container attach --resource-group $RG --name aci-hello

# Delete
az container delete --resource-group $RG --name aci-hello --yes
```

---

## Production Container Group

```bash
# Full production container with all options
az container create \
  --resource-group $RG \
  --name aci-api-prod \
  --image myregistry.azurecr.io/api:v1.2.0 \
  --registry-login-server myregistry.azurecr.io \
  --registry-username $ACR_USERNAME \
  --registry-password $ACR_PASSWORD \
  --cpu 2 \
  --memory 4 \
  --ports 8080 \
  --protocol TCP \
  --os-type Linux \
  --restart-policy OnFailure \
  --environment-variables \
    NODE_ENV=production \
    PORT=8080 \
  --secure-environment-variables \
    DB_PASSWORD=$DB_PASSWORD \
    API_KEY=$API_KEY \
  --azure-file-volume-account-name $STORAGE_NAME \
  --azure-file-volume-account-key $STORAGE_KEY \
  --azure-file-volume-share-name myshare \
  --azure-file-volume-mount-path /data \
  --log-analytics-workspace $LAW_ID \
  --log-analytics-workspace-key $LAW_KEY \
  --location eastus \
  --tags Environment=production Application=api
```

---

## Multi-Container Groups (Sidecar Pattern)

```yaml
# container-group.yaml — YAML deployment
apiVersion: '2021-10-01'
location: eastus
name: aci-multi-container
properties:
  containers:
  - name: app
    properties:
      image: myregistry.azurecr.io/app:latest
      resources:
        requests:
          cpu: 1.0
          memoryInGB: 2.0
      ports:
      - port: 8080
        protocol: TCP
      environmentVariables:
      - name: NODE_ENV
        value: production
      - name: DB_PASSWORD
        secureValue: "$(DB_PASSWORD)"
      volumeMounts:
      - name: shared-data
        mountPath: /shared
      livenessProbe:
        httpGet:
          path: /health
          port: 8080
        initialDelaySeconds: 30
        periodSeconds: 10
        failureThreshold: 3
      readinessProbe:
        httpGet:
          path: /ready
          port: 8080
        initialDelaySeconds: 5
        periodSeconds: 5

  - name: log-forwarder
    properties:
      image: fluent/fluent-bit:latest
      resources:
        requests:
          cpu: 0.5
          memoryInGB: 0.5
      volumeMounts:
      - name: shared-data
        mountPath: /shared
      - name: fluentbit-config
        mountPath: /fluent-bit/etc

  - name: metrics-exporter
    properties:
      image: prom/node-exporter:latest
      resources:
        requests:
          cpu: 0.25
          memoryInGB: 0.25
      ports:
      - port: 9100
        protocol: TCP

  imageRegistryCredentials:
  - server: myregistry.azurecr.io
    username: $(ACR_USERNAME)
    password: $(ACR_PASSWORD)

  ipAddress:
    type: Public
    ports:
    - protocol: TCP
      port: 8080
    dnsNameLabel: myapp-prod

  osType: Linux
  restartPolicy: Always

  volumes:
  - name: shared-data
    emptyDir: {}
  - name: fluentbit-config
    secret:
      fluent-bit.conf: $(base64 fluent-bit.conf)

tags:
  Environment: production
  Application: myapp
type: Microsoft.ContainerInstance/containerGroups
```

```bash
# Deploy from YAML
az container create \
  --resource-group $RG \
  --file container-group.yaml
```

---

## ACI in a VNet (Private Networking)

```bash
# Create subnet for ACI (must be delegated)
az network vnet subnet create \
  --name snet-aci \
  --resource-group $RG \
  --vnet-name vnet-app-prod \
  --address-prefix 10.0.5.0/24 \
  --delegations Microsoft.ContainerInstance/containerGroups

# Deploy ACI in VNet (no public IP)
az container create \
  --resource-group $RG \
  --name aci-private \
  --image myregistry.azurecr.io/worker:latest \
  --vnet vnet-app-prod \
  --subnet snet-aci \
  --cpu 2 \
  --memory 4 \
  --restart-policy OnFailure \
  --environment-variables \
    DB_HOST=sql-prod.database.windows.net \
  --secure-environment-variables \
    DB_PASSWORD=$DB_PASSWORD
```

---

## ACI for Batch Jobs

```bash
# One-time batch job (restart policy: Never)
az container create \
  --resource-group $RG \
  --name batch-job-$(date +%Y%m%d%H%M%S) \
  --image myregistry.azurecr.io/batch-processor:latest \
  --restart-policy Never \
  --cpu 4 \
  --memory 8 \
  --environment-variables \
    JOB_DATE=$(date +%Y-%m-%d) \
    INPUT_CONTAINER=raw-data \
    OUTPUT_CONTAINER=processed-data \
  --secure-environment-variables \
    STORAGE_KEY=$STORAGE_KEY \
  --command-line "python process.py --date $(date +%Y-%m-%d)"

# Wait for completion
az container wait \
  --resource-group $RG \
  --name batch-job-$(date +%Y%m%d%H%M%S) \
  --condition terminated

# Get exit code
az container show \
  --resource-group $RG \
  --name batch-job-$(date +%Y%m%d%H%M%S) \
  --query "containers[0].instanceView.currentState.exitCode"

# Get logs
az container logs \
  --resource-group $RG \
  --name batch-job-$(date +%Y%m%d%H%M%S)
```

---

## ACI as AKS Virtual Node (Burst Scaling)

ACI integrates with AKS as a "virtual node" — burst AKS workloads to ACI when cluster is full.

```bash
# Enable virtual nodes on AKS cluster
az aks enable-addons \
  --resource-group $RG \
  --name aks-prod \
  --addons virtual-node \
  --subnet-name snet-aci

# Schedule pods on virtual node (ACI)
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: burst-workload
spec:
  replicas: 10
  selector:
    matchLabels:
      app: burst
  template:
    metadata:
      labels:
        app: burst
    spec:
      nodeSelector:
        kubernetes.io/role: agent
        beta.kubernetes.io/os: linux
        type: virtual-kubelet
      tolerations:
      - key: virtual-kubelet.io/provider
        operator: Exists
      containers:
      - name: worker
        image: myregistry.azurecr.io/worker:latest
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
EOF
```

---

## Managed Identity with ACI

```bash
# Create user-assigned managed identity
az identity create \
  --name mi-aci-prod \
  --resource-group $RG

IDENTITY_ID=$(az identity show \
  --name mi-aci-prod \
  --resource-group $RG \
  --query id --output tsv)

PRINCIPAL_ID=$(az identity show \
  --name mi-aci-prod \
  --resource-group $RG \
  --query principalId --output tsv)

# Grant access to storage
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Storage Blob Data Contributor" \
  --scope $STORAGE_ID

# Grant access to Key Vault
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Key Vault Secrets User" \
  --scope $KV_ID

# Deploy ACI with managed identity (no credentials in env vars!)
az container create \
  --resource-group $RG \
  --name aci-secure \
  --image myregistry.azurecr.io/app:latest \
  --assign-identity $IDENTITY_ID \
  --environment-variables \
    STORAGE_ACCOUNT=$STORAGE_NAME \
    KEY_VAULT_URL=https://$KV_NAME.vault.azure.net/
```

---

## Bicep Template

```bicep
param location string = resourceGroup().location
param environment string = 'prod'
param imageTag string = 'latest'
param acrLoginServer string

@secure()
param acrPassword string

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: 'aci-worker-${environment}'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    containers: [
      {
        name: 'worker'
        properties: {
          image: '${acrLoginServer}/worker:${imageTag}'
          resources: {
            requests: {
              cpu: 2
              memoryInGB: 4
            }
          }
          environmentVariables: [
            {
              name: 'NODE_ENV'
              value: environment
            }
          ]
          livenessProbe: {
            httpGet: {
              path: '/health'
              port: 8080
            }
            initialDelaySeconds: 30
            periodSeconds: 10
          }
        }
      }
    ]
    imageRegistryCredentials: [
      {
        server: acrLoginServer
        username: 'token-name'
        password: acrPassword
      }
    ]
    osType: 'Linux'
    restartPolicy: 'OnFailure'
    ipAddress: {
      type: 'Private'
      ports: [
        {
          protocol: 'TCP'
          port: 8080
        }
      ]
    }
    subnetIds: [
      {
        id: resourceId('Microsoft.Network/virtualNetworks/subnets', 'vnet-app-prod', 'snet-aci')
      }
    ]
  }
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'mi-aci-prod'
}
```

---

## Cost Considerations

```
ACI Pricing (Linux):
  CPU:    $0.0000125 per vCPU-second
  Memory: $0.0000013 per GB-second

Example: 2 vCPU, 4GB, running 1 hour:
  CPU:    2 × 3600 × $0.0000125 = $0.09
  Memory: 4 × 3600 × $0.0000013 = $0.019
  Total:  ~$0.11/hour

vs VM (Standard_D2s_v5): ~$0.096/hour (always on)

ACI is cost-effective for:
  - Workloads running < 8 hours/day
  - Burst/batch workloads
  - Dev/test environments
  - Event-driven processing

ACI is NOT cost-effective for:
  - 24/7 workloads (use VMs or AKS)
  - High-throughput sustained workloads
```

---

## Common Pitfalls

| Pitfall | Solution |
|---------|---------|
| Container exits immediately | Check restart policy, view logs with `az container logs` |
| Can't pull private image | Verify registry credentials or use managed identity |
| VNet deployment fails | Ensure subnet is delegated to `Microsoft.ContainerInstance/containerGroups` |
| Secrets in env vars | Use managed identity + Key Vault instead |
| No persistent storage | Mount Azure Files volume for persistent data |
| Slow cold start | Pre-pull images to ACR in same region |

---

## Interview Q&A

### Q1: What is the difference between ACI and AKS?
**ACI**: Serverless containers, no cluster management, per-second billing, fast startup. Best for batch jobs, event-driven tasks, dev/test, CI/CD runners, burst workloads.
**AKS**: Full Kubernetes orchestration, persistent workloads, complex networking, auto-scaling, service mesh. Best for microservices, long-running production applications needing full K8s features.
Rule of thumb: ACI for short-lived/burst, AKS for persistent/complex.

### Q2: What is a Container Group in ACI?
A Container Group is the top-level resource in ACI — equivalent to a Kubernetes Pod. Multiple containers in a group share: the same host machine, network namespace (same IP/ports), storage volumes, and lifecycle. Use for sidecar patterns (log forwarder, metrics exporter alongside main app).

### Q3: How do you handle secrets in ACI?
1. **Secure environment variables**: encrypted at rest, not shown in portal/logs — for simple secrets
2. **Managed Identity + Key Vault**: ACI gets Azure AD identity, fetches secrets from Key Vault at runtime — most secure, no credentials in config
3. **Secret volumes**: mount Key Vault secrets as files — for certificate/config files
Never use plain environment variables for secrets.

### Q4: When would you use ACI as a virtual node for AKS?
When AKS cluster is at capacity and you need to burst quickly without waiting for new nodes to provision (node provisioning takes 2-5 minutes). ACI virtual nodes start in seconds. Use for: unpredictable traffic spikes, batch processing bursts, CI/CD job runners. Limitation: not all K8s features work on virtual nodes (no DaemonSets, limited volume types).

### Q5: How do you monitor ACI containers?
1. **Azure Monitor**: CPU, memory metrics automatically collected
2. **Log Analytics**: Send container logs with `--log-analytics-workspace`
3. **`az container logs`**: Real-time log streaming
4. **`az container attach`**: Attach to container stdout/stderr
5. **Application Insights**: Instrument app code for distributed tracing
6. **Container Insights**: If using ACI with AKS virtual nodes

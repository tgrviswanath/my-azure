# Project 03 — Microservices on AKS

## Architecture
```
Internet → Azure Front Door → Application Gateway (WAF)
                                      ↓
                              AKS Cluster (3 zones)
                              ├── Ingress Controller (NGINX)
                              ├── Order Service (3 replicas)
                              ├── Product Service (3 replicas)
                              ├── User Service (3 replicas)
                              └── Notification Service (2 replicas)
                                      ↓
                              Azure Service Bus (async)
                              Azure SQL (per service)
                              Azure Cache for Redis
                              Azure Container Registry
                              Key Vault (secrets via CSI)
                              Application Insights (distributed tracing)
```

## Services
| Service | Port | Database | Description |
|---------|------|----------|-------------|
| order-service | 3001 | SQL DB | Order management |
| product-service | 3002 | SQL DB | Product catalog |
| user-service | 3003 | SQL DB | User management |
| notification-service | 3004 | — | Email/SMS notifications |

## Deploy
```bash
# 1. Create AKS cluster
./scripts/create-cluster.sh

# 2. Build and push images
./scripts/build-push.sh

# 3. Deploy services
kubectl apply -f k8s/

# 4. Verify
kubectl get pods -n production
kubectl get ingress -n production
```

## Kubernetes Resources
- Deployments with rolling update strategy
- HPA (Horizontal Pod Autoscaler) per service
- PodDisruptionBudget for availability
- NetworkPolicy for service isolation
- ServiceAccount with Workload Identity
- ConfigMap for non-sensitive config
- External Secrets Operator for Key Vault secrets

## Cost Estimate
| Resource | SKU | Monthly Cost |
|----------|-----|-------------|
| AKS (3 nodes D4s_v5) | Standard_D4s_v5 × 3 | ~$420 |
| Azure SQL (3 DBs) | GP_Gen5_2 × 3 | ~$450 |
| Redis Cache | Standard C1 | ~$55 |
| ACR | Premium | ~$50 |
| Service Bus | Standard | ~$10 |
| **Total** | | **~$985/mo** |

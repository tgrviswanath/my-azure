# Architecture — Project 5.4 AKS Deployment

## Diagram

```
Internet → Load Balancer → AKS Cluster
                              ├── Node 1 (Standard_B2s)
                              │     ├── Pod: myapp (replica 1)
                              │     └── Pod: myapp (replica 2)
                              └── Node 2 (Standard_B2s)
                                    └── Pod: myapp (replica 3+)

ACR → AcrPull (Managed Identity) → AKS pulls images
HPA → scales pods 2-10 based on CPU > 70%
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Deployment | Manages pod replicas, rolling updates |
| Service (ClusterIP) | Internal load balancing between pods |
| HPA | Auto-scales pods based on CPU/memory |
| AcrPull | Managed Identity role to pull from ACR |
| Liveness probe | Restarts unhealthy pods |
| Readiness probe | Removes pod from LB until ready |

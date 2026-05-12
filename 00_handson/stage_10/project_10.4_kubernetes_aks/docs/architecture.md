# Architecture — Project 10.4 Kubernetes on AKS

## Diagram

```
Internet
    │ HTTP/HTTPS
    ▼
Application Gateway (AGIC)
    │ path-based routing
    │ /api/* → handson-api service
    │ /web/* → handson-web service
    ▼
AKS Cluster
    │
    ├── System Node Pool (Standard_D2s_v3 x1)
    │     └── kube-system pods (CoreDNS, kube-proxy, etc.)
    │
    └── User Node Pool (Standard_D2s_v3 x2, autoscale 1-5)
          └── handson namespace
                ├── Deployment: handson-api (3 replicas)
                │     └── Pod → Container (port 8080)
                │           └── Workload Identity → Key Vault
                ├── Service: handson-api (ClusterIP)
                ├── Ingress: handson-api (AGIC)
                └── HPA: handson-api (CPU 50%, 2-10 replicas)
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| System node pool | Reserved for Kubernetes system pods |
| User node pool | For application workloads — can scale to 0 |
| AGIC | Application Gateway Ingress Controller — native Azure |
| HPA | Horizontal Pod Autoscaler — scale pods on CPU/memory |
| Workload Identity | Pod gets Azure AD identity — no stored credentials |
| Cluster Autoscaler | Add/remove nodes based on pending pods |

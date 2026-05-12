# Architecture — Project 6.5 Kubernetes GitOps with ArgoCD

## Diagram

```
GitHub Repository
  └── k8s/
      ├── base/
      │   ├── deployment.yaml
      │   ├── service.yaml
      │   └── kustomization.yaml
      └── overlays/
          ├── dev/
          └── prod/
          
    │ ArgoCD polls every 3 min
    ▼
ArgoCD (running in AKS, argocd namespace)
    │
    ├── Compares Git state vs cluster state
    ├── Detects drift
    └── Syncs cluster to match Git
          │
          ▼
    AKS Cluster
      └── handson namespace
          ├── Deployment (3 replicas)
          ├── Service (ClusterIP)
          └── Ingress (Application Gateway)
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| GitOps | Git is the single source of truth for cluster state |
| ArgoCD Application | CRD that defines what Git repo/path to sync |
| Sync policy | Auto-sync: ArgoCD applies changes automatically |
| Kustomize | Overlay system for environment-specific config |
| Self-heal | ArgoCD reverts manual kubectl changes to match Git |

# Architecture — Project 6.1

## Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           GitHub                                        │
│                                                                         │
│   Developer ──git push──► main branch                                  │
│                                │                                        │
│                                ▼                                        │
│              ┌─────────────────────────────────────┐                   │
│              │       GitHub Actions Workflow        │                   │
│              │                                      │                   │
│              │  ┌──────────────────────────────┐   │                   │
│              │  │  Job: build-and-push          │   │                   │
│              │  │  Runner: ubuntu-latest        │   │                   │
│              │  │                               │   │                   │
│              │  │  1. actions/checkout          │   │                   │
│              │  │  2. Run unit tests            │   │                   │
│              │  │  3. az acr login              │   │                   │
│              │  │  4. docker build              │   │                   │
│              │  │  5. docker push → ACR         │   │                   │
│              │  └──────────────┬───────────────┘   │                   │
│              │                 │ on success         │                   │
│              │  ┌──────────────▼───────────────┐   │                   │
│              │  │  Job: deploy                  │   │                   │
│              │  │  Runner: ubuntu-latest        │   │                   │
│              │  │                               │   │                   │
│              │  │  6. az aks get-credentials    │   │                   │
│              │  │  7. kubectl set image         │   │                   │
│              │  │  8. kubectl rollout status    │   │                   │
│              │  └──────────────────────────────┘   │                   │
│              └─────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────────────┘
                          │                    │
                          ▼                    ▼
              ┌───────────────────┐  ┌──────────────────────────────────┐
              │  Azure Container  │  │  Azure Kubernetes Service (AKS)  │
              │  Registry (ACR)   │  │                                  │
              │                   │  │  ┌────────────────────────────┐  │
              │  myacr.azurecr.io │  │  │  Deployment: myapp         │  │
              │  /myapp:abc1234   │◄─┼──│  replicas: 2               │  │
              │                   │  │  │  image: myacr.../myapp:SHA │  │
              └───────────────────┘  │  └────────────────────────────┘  │
                                     │                                  │
                                     │  ┌────────────────────────────┐  │
                                     │  │  Service: LoadBalancer      │  │
                                     │  │  port: 80 → 8080           │  │
                                     │  │  External IP: x.x.x.x      │  │
                                     │  └────────────────────────────┘  │
                                     └──────────────────────────────────┘

Authentication Flow:
  GitHub Actions ──AZURE_CREDENTIALS (SP JSON)──► Azure AD
  Azure AD ──access token──► ACR (AcrPush role)
  Azure AD ──access token──► AKS (Cluster User role)
  AKS kubelet identity ──AcrPull role──► ACR (pull images at runtime)
```

## Key Concepts

| Concept | Description |
|---|---|
| GitHub Actions Workflow | YAML file in `.github/workflows/` that defines jobs triggered by git events (push, PR, schedule). |
| Service Principal (SP) | Azure AD identity used by GitHub Actions to authenticate to Azure. Stored as `AZURE_CREDENTIALS` secret. |
| `github.sha` image tag | Each Docker image is tagged with the git commit SHA, making every build uniquely identifiable and rollbacks trivial. |
| AcrPull on kubelet identity | AKS nodes use a managed identity to pull images from ACR. This avoids storing registry credentials as Kubernetes secrets. |
| `kubectl rollout status` | Blocks the workflow until the deployment converges. If pods fail to start, the pipeline fails and alerts the team. |
| Rolling update strategy | Kubernetes replaces pods one at a time (default). Zero-downtime deployments with `maxUnavailable: 0`. |
| `kubectl rollout undo` | Instantly reverts to the previous ReplicaSet (previous image tag). No re-build required. |
| Separate build/deploy jobs | Allows re-running only the deploy job if the issue was infrastructure, not code. Also enables deploy to multiple environments. |

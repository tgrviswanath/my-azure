# Architecture — Project 5.3 ACR

## Flow

```
Local Docker build
  → docker tag → acrhandson001.azurecr.io/myapp:v1.0
  → docker push → ACR (Basic tier)
                    └── Used by AKS (project 5.4)
                    └── Used by Container Apps (project 5.6)
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| ACR Basic | Dev/test — no geo-replication, 10GB storage |
| ACR Standard | Production — geo-replication, 100GB |
| ACR Tasks | Cloud-based image build — no local Docker |
| AcrPull role | Grant AKS Managed Identity pull access |
| Admin disabled | Use Managed Identity instead of admin credentials |

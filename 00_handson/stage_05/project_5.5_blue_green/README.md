# Project 5.5 — Blue-Green Deployment

## What This Does
Implements zero-downtime blue-green deployments on AKS. Two identical environments (blue=v1, green=v2) run simultaneously — traffic switches instantly via Kubernetes Service selector.

## Services Used
| Service | Purpose |
|---------|---------|
| AKS | Kubernetes cluster |
| Kubernetes Service | Traffic routing via label selector |
| Azure Container Registry | Container images for blue and green |

## Architecture
```
Service: myapp-svc
    │ selector: version=blue (or green)
    │
    ├── Deployment: myapp-blue (v1, 2 replicas) ← active
    └── Deployment: myapp-green (v2, 2 replicas) ← standby

Traffic switch: patch service selector → instant, zero-downtime
Rollback: patch selector back to blue → instant
```

## How to Run
```bash
# 1. Deploy green (v2) alongside blue (v1)
python code/blue_green_deploy.py deploy-green \
  --image acrhandson001.azurecr.io/myapp:v2.0

# 2. Verify green is healthy
python code/blue_green_deploy.py status

# 3. Switch traffic to green
python code/blue_green_deploy.py switch-to-green

# 4. Rollback if needed
python code/blue_green_deploy.py rollback
```

## Lessons Learned
- Blue-green: instant switch, full rollback capability — no gradual traffic shift
- Canary: gradual traffic shift (10% → 50% → 100%) — use for risk reduction
- Keep blue running until green is verified stable (at least 30 minutes)
- Resource cost: 2x during transition — both environments running simultaneously
- Use readiness probes — green pods must pass before switching traffic

## Code

### `code/blue_green_deploy.py` — Blue-green deployment controller

```bash
# Deploy green version
python code/blue_green_deploy.py deploy-green --image acrhandson001.azurecr.io/myapp:v2.0

# Switch traffic
python code/blue_green_deploy.py switch-to-green

# Rollback
python code/blue_green_deploy.py rollback

# Check status
python code/blue_green_deploy.py status
```

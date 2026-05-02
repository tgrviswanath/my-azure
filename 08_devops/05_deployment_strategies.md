# Azure Deployment Strategies — Blue/Green, Canary & Rolling

## Overview

```
Strategy        | Downtime | Risk   | Rollback  | Cost
----------------|----------|--------|-----------|------
Recreate        | Yes      | High   | Redeploy  | Low
Rolling Update  | No       | Medium | Slow      | Low
Blue/Green      | No       | Low    | Instant   | High (2x infra)
Canary          | No       | Low    | Fast      | Medium
A/B Testing     | No       | Low    | Fast      | Medium
Shadow          | No       | None   | N/A       | High
```

---

## Blue/Green Deployment — App Service Slots

App Service deployment slots are the native Azure mechanism for blue/green deployments.

```
Production Slot (Blue):  app-myapp-prod.azurewebsites.net  → v1.0
Staging Slot (Green):    app-myapp-prod-staging.azurewebsites.net → v2.0

Swap: atomic traffic switch, zero downtime
Rollback: swap back (takes seconds)
```

### Setup and Deploy

```bash
# Create staging slot
az webapp deployment slot create \
  --name app-myapp-prod \
  --resource-group $RG \
  --slot staging \
  --configuration-source app-myapp-prod

# Deploy new version to staging slot
az webapp deployment source config-zip \
  --name app-myapp-prod \
  --resource-group $RG \
  --slot staging \
  --src ./dist/app-v2.zip

# Warm up staging slot
curl -s https://app-myapp-prod-staging.azurewebsites.net/health

# Run smoke tests against staging
./scripts/smoke-tests.sh https://app-myapp-prod-staging.azurewebsites.net

# Swap slots (zero-downtime production deployment)
az webapp deployment slot swap \
  --name app-myapp-prod \
  --resource-group $RG \
  --slot staging \
  --target-slot production

echo "Deployment complete. Production now running v2.0"

# Rollback (swap back)
az webapp deployment slot swap \
  --name app-myapp-prod \
  --resource-group $RG \
  --slot staging \
  --target-slot production

echo "Rolled back to v1.0"
```

### Slot Settings (Sticky Settings)

```bash
# Mark settings as slot-specific (not swapped)
# Use for: connection strings, environment-specific config
az webapp config appsettings set \
  --name app-myapp-prod \
  --resource-group $RG \
  --slot staging \
  --slot-settings \
    ENVIRONMENT=staging \
    DB_CONNECTION_STRING="Server=sql-staging..." \
    FEATURE_FLAGS='{"newUI":true}'

# These settings stay with the slot, not swapped with the app
```

### Auto-Swap (CI/CD Integration)

```bash
# Enable auto-swap: staging → production on successful deployment
az webapp deployment slot auto-swap \
  --name app-myapp-prod \
  --resource-group $RG \
  --slot staging \
  --auto-swap-slot production
```

---

## Canary Release — Traffic Splitting

Route a percentage of traffic to the new version before full rollout.

### App Service Traffic Routing

```bash
# Route 10% of traffic to staging slot (canary)
az webapp traffic-routing set \
  --name app-myapp-prod \
  --resource-group $RG \
  --distribution staging=10

# Monitor error rate and latency for 30 minutes
# If healthy, increase to 50%
az webapp traffic-routing set \
  --name app-myapp-prod \
  --resource-group $RG \
  --distribution staging=50

# If healthy, complete rollout (swap)
az webapp deployment slot swap \
  --name app-myapp-prod \
  --resource-group $RG \
  --slot staging

# If issues, route all traffic back to production
az webapp traffic-routing clear \
  --name app-myapp-prod \
  --resource-group $RG
```

### Azure Front Door — Canary with Origin Groups

```bash
# Create two origin groups: stable and canary
az afd origin-group create \
  --profile-name afd-myapp-prod \
  --resource-group $RG \
  --origin-group-name stable \
  --probe-request-type GET \
  --probe-protocol Https \
  --probe-interval-in-seconds 30 \
  --probe-path /health \
  --sample-size 4 \
  --successful-samples-required 3

az afd origin-group create \
  --profile-name afd-myapp-prod \
  --resource-group $RG \
  --origin-group-name canary \
  --probe-request-type GET \
  --probe-protocol Https \
  --probe-interval-in-seconds 30 \
  --probe-path /health

# Add origins to groups
az afd origin create \
  --profile-name afd-myapp-prod \
  --resource-group $RG \
  --origin-group-name stable \
  --origin-name app-v1 \
  --host-name app-myapp-prod.azurewebsites.net \
  --origin-host-header app-myapp-prod.azurewebsites.net \
  --http-port 80 --https-port 443 \
  --weight 90

az afd origin create \
  --profile-name afd-myapp-prod \
  --resource-group $RG \
  --origin-group-name canary \
  --origin-name app-v2 \
  --host-name app-myapp-prod-staging.azurewebsites.net \
  --origin-host-header app-myapp-prod-staging.azurewebsites.net \
  --http-port 80 --https-port 443 \
  --weight 10
```

---

## Canary with Azure Container Apps

```bash
# Deploy new revision with 10% traffic
az containerapp revision copy \
  --name myapp \
  --resource-group $RG \
  --image myregistry.azurecr.io/myapp:v2.0 \
  --revision-suffix v2

# Set traffic split
az containerapp ingress traffic set \
  --name myapp \
  --resource-group $RG \
  --revision-weight \
    myapp--v1=90 \
    myapp--v2=10

# After validation, shift all traffic
az containerapp ingress traffic set \
  --name myapp \
  --resource-group $RG \
  --revision-weight \
    myapp--v2=100

# Deactivate old revision
az containerapp revision deactivate \
  --name myapp \
  --resource-group $RG \
  --revision myapp--v1
```

---

## Rolling Update — AKS

```yaml
# deployment.yaml — rolling update strategy
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 6
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 2        # Allow 2 extra pods during update
      maxUnavailable: 0  # Never reduce below desired count
  template:
    spec:
      containers:
        - name: myapp
          image: myregistry.azurecr.io/myapp:v2.0
          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 3
```

```bash
# Trigger rolling update
kubectl set image deployment/myapp \
  myapp=myregistry.azurecr.io/myapp:v2.0 \
  --namespace production

# Watch rollout progress
kubectl rollout status deployment/myapp --namespace production

# Rollback if issues
kubectl rollout undo deployment/myapp --namespace production

# Rollback to specific revision
kubectl rollout history deployment/myapp --namespace production
kubectl rollout undo deployment/myapp --to-revision=3 --namespace production
```

---

## Feature Flags with Azure App Configuration

```bash
# Create App Configuration store
az appconfig create \
  --name appconfig-myapp-prod \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard

# Create feature flag
az appconfig feature set \
  --name appconfig-myapp-prod \
  --feature new-checkout-ui \
  --label production \
  --yes

# Enable for 10% of users (percentage filter)
az appconfig feature filter add \
  --name appconfig-myapp-prod \
  --feature new-checkout-ui \
  --filter-name Microsoft.Percentage \
  --filter-parameters Percentage=10

# Enable for specific users (targeting filter)
az appconfig feature filter add \
  --name appconfig-myapp-prod \
  --feature new-checkout-ui \
  --filter-name Microsoft.Targeting \
  --filter-parameters '{"Audience":{"Users":["alice@company.com"],"Groups":[{"Name":"beta-testers","RolloutPercentage":100}],"DefaultRolloutPercentage":0}}'
```

```javascript
// Node.js — check feature flag
const { AppConfigurationClient } = require('@azure/app-configuration');
const { FeatureManager } = require('@microsoft/feature-management');

const client = new AppConfigurationClient(process.env.APP_CONFIG_CONNECTION);
const featureManager = new FeatureManager(client);

app.get('/checkout', async (req, res) => {
    const useNewUI = await featureManager.isEnabled('new-checkout-ui', {
        userId: req.user.id,
        groups: req.user.groups
    });

    if (useNewUI) {
        return res.render('checkout-v2');
    }
    return res.render('checkout-v1');
});
```

---

## CI/CD Pipeline with Blue/Green

```yaml
# azure-pipelines.yml — Blue/Green deployment
stages:
- stage: Deploy_Staging
  displayName: 'Deploy to Staging Slot'
  jobs:
  - deployment: DeployStaging
    environment: staging
    strategy:
      runOnce:
        deploy:
          steps:
          - task: AzureWebApp@1
            inputs:
              azureSubscription: 'Azure-Production'
              appName: 'app-myapp-prod'
              deployToSlotOrASE: true
              resourceGroupName: $(resourceGroup)
              slotName: staging
              package: '$(Pipeline.Workspace)/drop/*.zip'

          - script: |
              echo "Running smoke tests against staging..."
              curl -f https://app-myapp-prod-staging.azurewebsites.net/health
              npm run test:smoke -- --url https://app-myapp-prod-staging.azurewebsites.net
            displayName: 'Smoke Tests'

- stage: Approve_Production
  displayName: 'Approval Gate'
  dependsOn: Deploy_Staging
  jobs:
  - job: WaitForApproval
    pool: server
    steps:
    - task: ManualValidation@0
      inputs:
        notifyUsers: 'team@company.com'
        instructions: |
          Staging deployment complete.
          URL: https://app-myapp-prod-staging.azurewebsites.net
          Please verify and approve to swap to production.
        onTimeout: reject
        timeout: 60

- stage: Swap_Production
  displayName: 'Swap to Production'
  dependsOn: Approve_Production
  jobs:
  - deployment: SwapSlots
    environment: production
    strategy:
      runOnce:
        deploy:
          steps:
          - task: AzureAppServiceManage@0
            inputs:
              azureSubscription: 'Azure-Production'
              Action: 'Swap Slots'
              WebAppName: 'app-myapp-prod'
              ResourceGroupName: $(resourceGroup)
              SourceSlot: staging
              SwapWithProduction: true

          - script: |
              echo "Verifying production deployment..."
              sleep 30
              curl -f https://app-myapp-prod.azurewebsites.net/health
            displayName: 'Post-swap verification'
```

---

## Interview Q&A

### Q1: What is the difference between blue/green and canary deployments?
**Blue/Green**: Two identical environments. Switch all traffic at once (or via slot swap). Easy instant rollback — just swap back. Higher cost (double infrastructure temporarily). Best for: major releases, database schema changes, when you need instant rollback.
**Canary**: Route small percentage (5-10%) to new version. Monitor metrics. Gradually increase. Rollback by routing 100% back. Lower risk than full deployment, lower cost than full blue/green. Best for: gradual rollouts, A/B testing, risk-averse releases.

### Q2: How do App Service deployment slots work?
Slots are live environments with their own hostnames. You deploy to staging slot, test it, then swap. During swap: Azure warms up the staging slot (sends requests to it), then atomically switches the routing — production traffic goes to what was staging, and vice versa. Zero downtime. Slot-specific settings (marked as sticky) stay with the slot. If issues arise, swap back in seconds.

### Q3: How do you implement a canary release for a microservice on AKS?
1. Deploy new version as a separate deployment with different labels
2. Create a Service that selects both old and new pods (weighted)
3. Use Ingress with traffic splitting (NGINX, Istio, or Flagger)
4. Monitor error rate and latency for new pods
5. Gradually increase traffic to new version
6. Delete old deployment when confident
Or use Flagger for automated canary analysis with automatic rollback on metric degradation.

### Q4: What are feature flags and when would you use them over deployment strategies?
Feature flags decouple deployment from release. You deploy code with the feature disabled, then enable it for specific users/percentages without redeployment. Use when: (1) You want to test with real users before full rollout, (2) Feature spans multiple services (coordinate release), (3) Need kill switch for risky features, (4) A/B testing different implementations, (5) Gradual rollout to specific user segments. Deployment strategies control infrastructure; feature flags control functionality.

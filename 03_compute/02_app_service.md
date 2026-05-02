# Azure App Service — Web Apps, API Apps & Deployment

## App Service Overview

```
App Service = PaaS for hosting web apps, REST APIs, mobile backends
├── Supports: .NET, Node.js, Python, Java, PHP, Ruby, containers
├── Built-in: auto-scaling, SSL, custom domains, deployment slots
├── Managed: OS patching, load balancing, capacity provisioning
└── Pricing: based on App Service Plan (not per app)

App Service Plan = defines compute resources
├── Free (F1):    Shared, 60 min/day CPU, no custom domain
├── Shared (D1):  Shared, custom domain
├── Basic (B1-3): Dedicated, manual scale, no staging slots
├── Standard (S1-3): Auto-scale, 5 slots, custom domains/SSL
├── Premium (P1-3v3): Enhanced performance, 20 slots, VNet integration
└── Isolated (I1-3v2): Dedicated environment (ASE), VNet injection
```

## Deployment Methods

```bash
# Method 1: ZIP deploy
az webapp deployment source config-zip \
  --resource-group $RG \
  --name $APP_NAME \
  --src ./app.zip

# Method 2: Git deploy
az webapp deployment source config \
  --name $APP_NAME \
  --resource-group $RG \
  --repo-url "https://github.com/user/repo" \
  --branch main

# Method 3: Container
az webapp create \
  --name $APP_NAME \
  --resource-group $RG \
  --plan $APP_PLAN \
  --deployment-container-image-name myregistry.azurecr.io/myapp:latest

# Method 4: Azure DevOps / GitHub Actions (CI/CD)
# See devops/ section
```

## Deployment Slots

```bash
# Create staging slot
az webapp deployment slot create \
  --name $APP_NAME \
  --resource-group $RG \
  --slot staging

# Deploy to staging
az webapp deployment source config-zip \
  --resource-group $RG \
  --name $APP_NAME \
  --slot staging \
  --src ./app.zip

# Swap staging → production (zero-downtime)
az webapp deployment slot swap \
  --resource-group $RG \
  --name $APP_NAME \
  --slot staging \
  --target-slot production

# Slot settings (not swapped)
az webapp config appsettings set \
  --name $APP_NAME \
  --resource-group $RG \
  --slot staging \
  --slot-settings DATABASE_URL="staging-db-connection"
```

## Auto-scaling

```bash
# Create autoscale profile
az monitor autoscale create \
  --resource-group $RG \
  --resource $APP_PLAN \
  --resource-type Microsoft.Web/serverfarms \
  --name autoscale-webapp \
  --min-count 1 \
  --max-count 10 \
  --count 2

# Scale out: HTTP queue > 10 for 5 min
az monitor autoscale rule create \
  --resource-group $RG \
  --autoscale-name autoscale-webapp \
  --condition "HttpQueueLength > 10 avg 5m" \
  --scale out 2

# Schedule: scale up during business hours
az monitor autoscale profile create \
  --resource-group $RG \
  --autoscale-name autoscale-webapp \
  --name "BusinessHours" \
  --min-count 3 \
  --max-count 10 \
  --count 3 \
  --recurrence week mon tue wed thu fri \
  --timezone "Eastern Standard Time" \
  --start 08:00 \
  --end 18:00
```

## VNet Integration

```bash
# Integrate App Service with VNet (outbound)
az webapp vnet-integration add \
  --name $APP_NAME \
  --resource-group $RG \
  --vnet $VNET_NAME \
  --subnet $SUBNET_NAME

# Private endpoint (inbound — no public access)
az network private-endpoint create \
  --name pe-webapp \
  --resource-group $RG \
  --vnet-name $VNET_NAME \
  --subnet $SUBNET_NAME \
  --private-connection-resource-id $(az webapp show --name $APP_NAME --resource-group $RG --query id -o tsv) \
  --group-id sites \
  --connection-name conn-webapp
```

## App Service Environment (ASE)

```
ASE = fully isolated, dedicated environment for App Service
├── Deployed into your VNet
├── No shared infrastructure
├── Supports internal load balancer (ILB ASE)
├── Higher cost but maximum isolation
└── Use for: compliance requirements, high security, large scale
```

## Interview Questions

### Q1: What is the difference between App Service Plan tiers?
**Answer:**
- **Free/Shared**: Shared infrastructure, limited resources, no SLA
- **Basic**: Dedicated VMs, manual scaling, no deployment slots
- **Standard**: Auto-scaling, 5 deployment slots, custom SSL, SLA 99.95%
- **Premium**: Better performance, 20 slots, VNet integration, zone redundancy
- **Isolated**: Dedicated environment (ASE), VNet injection, highest isolation

### Q2: How do deployment slots work and what is a slot swap?
**Answer:**
Deployment slots are live environments (staging, QA, etc.) with their own URLs. A **slot swap** exchanges the content between two slots (e.g., staging → production) with zero downtime. Azure warms up the new slot before swapping, so users experience no interruption. Slot-specific settings (marked as "slot settings") are NOT swapped.

### Q3: How do you achieve zero-downtime deployments with App Service?
**Answer:**
1. Deploy to staging slot
2. Run smoke tests on staging
3. Swap staging → production (atomic, zero-downtime)
4. If issues: swap back (rollback in seconds)
5. Use "Auto Swap" for fully automated deployments

### Q4: What is VNet Integration and when do you need it?
**Answer:**
VNet Integration allows App Service to make **outbound** calls to resources in a VNet (databases, internal APIs). It does NOT make the app private (inbound). For private inbound access, use **Private Endpoints**. Use VNet Integration when your app needs to access resources not exposed to the internet (Azure SQL with private endpoint, Redis Cache, etc.).

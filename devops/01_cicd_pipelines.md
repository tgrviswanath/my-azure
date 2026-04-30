# Azure DevOps — CI/CD Pipelines, IaC & Deployment Strategies

## Azure DevOps Overview

```
Azure DevOps Services
├── Azure Repos:     Git repositories
├── Azure Pipelines: CI/CD automation
├── Azure Boards:    Work tracking (Scrum/Kanban)
├── Azure Artifacts: Package management (npm, NuGet, Maven)
└── Azure Test Plans: Manual/automated testing

GitHub Actions (alternative)
├── Integrated with GitHub repos
├── Azure-specific actions available
└── Free for public repos, minutes-based for private
```

## Azure Pipelines — YAML

```yaml
# azure-pipelines.yml — Complete CI/CD pipeline
trigger:
  branches:
    include:
    - main
    - release/*
  paths:
    exclude:
    - docs/**
    - '*.md'

pr:
  branches:
    include:
    - main

variables:
  azureSubscription: 'Azure-Production'
  resourceGroup: 'rg-myapp-prod-eastus'
  appName: 'app-myapp-prod'
  containerRegistry: 'myregistry.azurecr.io'
  imageRepository: 'myapp'
  dockerfilePath: '$(Build.SourcesDirectory)/Dockerfile'
  tag: '$(Build.BuildId)'

stages:
# ── Stage 1: Build & Test ──────────────────────────────────────────────────
- stage: Build
  displayName: 'Build and Test'
  jobs:
  - job: BuildJob
    displayName: 'Build, Test, Scan'
    pool:
      vmImage: 'ubuntu-latest'
    steps:
    - task: NodeTool@0
      inputs:
        versionSpec: '18.x'

    - script: |
        npm ci
        npm run lint
        npm test -- --coverage --ci
      displayName: 'Install, Lint, Test'

    - task: PublishTestResults@2
      inputs:
        testResultsFormat: 'JUnit'
        testResultsFiles: '**/test-results.xml'

    - task: PublishCodeCoverageResults@1
      inputs:
        codeCoverageTool: 'Cobertura'
        summaryFileLocation: '**/coverage/cobertura-coverage.xml'

    # Security scan
    - task: SnykSecurityScan@1
      inputs:
        serviceConnectionEndpoint: 'Snyk'
        testType: 'app'
        failOnIssues: true
        monitorWhen: 'always'

    # Build Docker image
    - task: Docker@2
      displayName: 'Build Docker image'
      inputs:
        command: build
        repository: $(imageRepository)
        dockerfile: $(dockerfilePath)
        containerRegistry: $(containerRegistry)
        tags: |
          $(tag)
          latest

    # Push to ACR
    - task: Docker@2
      displayName: 'Push to ACR'
      inputs:
        command: push
        repository: $(imageRepository)
        containerRegistry: $(containerRegistry)
        tags: |
          $(tag)
          latest

    # Scan container image
    - task: AzureContainerScan@0
      inputs:
        dockerImageName: '$(containerRegistry)/$(imageRepository):$(tag)'

    - task: PublishPipelineArtifact@1
      inputs:
        targetPath: '$(Pipeline.Workspace)'
        artifact: 'drop'

# ── Stage 2: Deploy to Staging ────────────────────────────────────────────
- stage: DeployStaging
  displayName: 'Deploy to Staging'
  dependsOn: Build
  condition: succeeded()
  variables:
    environment: staging
    slot: staging
  jobs:
  - deployment: DeployToStaging
    displayName: 'Deploy to Staging Slot'
    environment: 'staging'
    pool:
      vmImage: 'ubuntu-latest'
    strategy:
      runOnce:
        deploy:
          steps:
          - task: AzureWebAppContainer@1
            inputs:
              azureSubscription: $(azureSubscription)
              appName: $(appName)
              deployToSlotOrASE: true
              resourceGroupName: $(resourceGroup)
              slotName: staging
              containers: '$(containerRegistry)/$(imageRepository):$(tag)'

          # Smoke tests
          - script: |
              STAGING_URL="https://$(appName)-staging.azurewebsites.net"
              STATUS=$(curl -s -o /dev/null -w "%{http_code}" $STAGING_URL/health)
              if [ "$STATUS" != "200" ]; then
                echo "Health check failed: $STATUS"
                exit 1
              fi
              echo "Staging health check passed"
            displayName: 'Smoke Test'

# ── Stage 3: Deploy to Production ─────────────────────────────────────────
- stage: DeployProduction
  displayName: 'Deploy to Production'
  dependsOn: DeployStaging
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
  - deployment: DeployToProduction
    displayName: 'Swap Staging to Production'
    environment: 'production'  # requires manual approval
    pool:
      vmImage: 'ubuntu-latest'
    strategy:
      runOnce:
        deploy:
          steps:
          # Swap slots (zero-downtime)
          - task: AzureAppServiceManage@0
            inputs:
              azureSubscription: $(azureSubscription)
              Action: 'Swap Slots'
              WebAppName: $(appName)
              ResourceGroupName: $(resourceGroup)
              SourceSlot: staging
              SwapWithProduction: true

          # Post-deployment verification
          - script: |
              PROD_URL="https://$(appName).azurewebsites.net"
              for i in {1..5}; do
                STATUS=$(curl -s -o /dev/null -w "%{http_code}" $PROD_URL/health)
                if [ "$STATUS" == "200" ]; then
                  echo "Production health check passed"
                  exit 0
                fi
                sleep 10
              done
              echo "Production health check failed — initiating rollback"
              exit 1
            displayName: 'Production Health Check'

          # Rollback on failure
          - task: AzureAppServiceManage@0
            condition: failed()
            inputs:
              azureSubscription: $(azureSubscription)
              Action: 'Swap Slots'
              WebAppName: $(appName)
              ResourceGroupName: $(resourceGroup)
              SourceSlot: staging
              SwapWithProduction: true
            displayName: 'Rollback on Failure'
```

## GitHub Actions for Azure

```yaml
# .github/workflows/deploy.yml
name: Deploy to Azure

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  AZURE_WEBAPP_NAME: app-myapp-prod
  REGISTRY: myregistry.azurecr.io
  IMAGE_NAME: myapp

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '18'
        cache: 'npm'

    - run: npm ci
    - run: npm test -- --coverage

    - name: Login to ACR
      uses: azure/docker-login@v1
      with:
        login-server: ${{ env.REGISTRY }}
        username: ${{ secrets.ACR_USERNAME }}
        password: ${{ secrets.ACR_PASSWORD }}

    - name: Build and push
      run: |
        docker build -t ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} .
        docker push ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}

  deploy:
    needs: build-and-test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment: production

    steps:
    - name: Azure Login
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}

    - name: Deploy to App Service
      uses: azure/webapps-deploy@v3
      with:
        app-name: ${{ env.AZURE_WEBAPP_NAME }}
        images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
```

## Deployment Strategies

```
Blue/Green:
  ├── Two identical environments (blue=current, green=new)
  ├── Deploy to green, test, switch traffic
  ├── Instant rollback: switch back to blue
  └── Azure: deployment slots (staging=green, production=blue)

Canary:
  ├── Route small % of traffic to new version
  ├── Monitor metrics, gradually increase %
  ├── Rollback if issues detected
  └── Azure: Traffic Manager weighted routing, App Gateway

Rolling:
  ├── Update instances one by one
  ├── No downtime, but mixed versions during rollout
  └── Azure: VMSS rolling upgrade, AKS rolling update

Feature Flags:
  ├── Deploy code but control feature activation
  ├── Test in production with subset of users
  └── Azure: Azure App Configuration feature flags
```

## Interview Questions

### Q1: What is the difference between Blue/Green and Canary deployments?
**Answer:**
- **Blue/Green**: Two complete environments. Switch all traffic at once. Instant rollback. Higher cost (double infrastructure). Best for: major releases, database migrations.
- **Canary**: Gradually shift traffic (5% → 25% → 100%). Monitor metrics at each stage. Slower rollout but lower risk. Best for: continuous delivery, A/B testing.

### Q2: How do you implement zero-downtime deployments in Azure?
**Answer:**
1. **App Service**: Deployment slots + slot swap (atomic, pre-warmed)
2. **AKS**: Rolling update strategy with maxSurge/maxUnavailable
3. **VMSS**: Rolling upgrade policy
4. **Azure Front Door**: Weighted routing for canary
5. **Traffic Manager**: Priority/weighted routing for blue/green

### Q3: What is Infrastructure as Code and why use it?
**Answer:**
IaC defines infrastructure in code files (ARM, Bicep, Terraform). Benefits:
- **Repeatability**: same infrastructure every time
- **Version control**: track changes, rollback
- **Consistency**: dev/staging/prod identical
- **Automation**: no manual portal clicks
- **Documentation**: code IS the documentation
Azure options: ARM templates (JSON), Bicep (DSL, compiles to ARM), Terraform (multi-cloud)

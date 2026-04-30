# Lab 04 — Setup CI/CD Pipeline with Azure DevOps

## Objective
Create a complete CI/CD pipeline using Azure DevOps that builds, tests, and deploys a Node.js app to App Service with staging slot and approval gates.

## Prerequisites
- Azure DevOps organization (free at dev.azure.com)
- Azure subscription
- GitHub repository with Node.js app

## Step 1: Create Azure DevOps Project

```bash
# Install Azure DevOps CLI extension
az extension add --name azure-devops

# Configure defaults
az devops configure --defaults organization=https://dev.azure.com/YOUR_ORG project=MyProject

# Create project
az devops project create \
  --name "AzureLab04" \
  --description "CI/CD Lab" \
  --visibility private \
  --process Agile
```

## Step 2: Create Service Connection

```bash
# Create service principal
SP_JSON=$(az ad sp create-for-rbac \
  --name "sp-azuredevops-lab04" \
  --role Contributor \
  --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG" \
  --sdk-auth)

# Extract values
APP_ID=$(echo $SP_JSON | jq -r '.clientId')
PASSWORD=$(echo $SP_JSON | jq -r '.clientSecret')
TENANT_ID=$(echo $SP_JSON | jq -r '.tenantId')

echo "Service Principal created:"
echo "  App ID: $APP_ID"
echo "  Tenant: $TENANT_ID"
echo ""
echo "In Azure DevOps:"
echo "  Project Settings → Service Connections → New → Azure Resource Manager"
echo "  Use Service Principal (manual) with above values"
```

## Step 3: Create Variable Groups

```bash
# Create variable group for non-sensitive values
az pipelines variable-group create \
  --name "lab04-variables" \
  --variables \
    APP_NAME="app-lab04-prod" \
    RESOURCE_GROUP="rg-lab04-prod" \
    AZURE_SUBSCRIPTION="Azure-Production" \
    NODE_VERSION="18"

# Create variable group linked to Key Vault (for secrets)
az pipelines variable-group create \
  --name "lab04-secrets" \
  --authorize true \
  --variables placeholder=placeholder

echo "Link lab04-secrets to Key Vault in Azure DevOps UI:"
echo "  Library → lab04-secrets → Link secrets from Azure Key Vault"
```

## Step 4: Create Pipeline YAML

```yaml
# azure-pipelines.yml — save in repo root
trigger:
  branches:
    include: [main, develop]
  paths:
    exclude: ['*.md', 'docs/**']

pr:
  branches:
    include: [main]

variables:
- group: lab04-variables
- group: lab04-secrets
- name: imageTag
  value: '$(Build.BuildId)'

pool:
  vmImage: 'ubuntu-latest'

stages:
# ── Build & Test ──────────────────────────────────────────────────────────────
- stage: Build
  displayName: '🔨 Build & Test'
  jobs:
  - job: BuildTest
    steps:
    - task: NodeTool@0
      inputs:
        versionSpec: '$(NODE_VERSION).x'
      displayName: 'Install Node.js'

    - script: npm ci
      displayName: 'Install dependencies'

    - script: npm run lint
      displayName: 'Lint'
      continueOnError: false

    - script: npm test -- --coverage --ci --reporters=default --reporters=jest-junit
      displayName: 'Run tests'
      env:
        CI: true

    - task: PublishTestResults@2
      condition: always()
      inputs:
        testResultsFormat: 'JUnit'
        testResultsFiles: '**/junit.xml'
        mergeTestResults: true
        testRunTitle: 'Unit Tests'

    - task: PublishCodeCoverageResults@1
      inputs:
        codeCoverageTool: 'Cobertura'
        summaryFileLocation: '**/coverage/cobertura-coverage.xml'

    - script: |
        npm run build 2>/dev/null || echo "No build step"
        zip -r $(Build.ArtifactStagingDirectory)/app.zip . \
          --exclude "*.git*" --exclude "node_modules/*" --exclude "*.test.*"
      displayName: 'Package application'

    - task: PublishPipelineArtifact@1
      inputs:
        targetPath: '$(Build.ArtifactStagingDirectory)/app.zip'
        artifact: 'app'
      displayName: 'Publish artifact'

# ── Deploy to Staging ─────────────────────────────────────────────────────────
- stage: DeployStaging
  displayName: '🚀 Deploy Staging'
  dependsOn: Build
  condition: succeeded()
  jobs:
  - deployment: DeployStaging
    displayName: 'Deploy to Staging Slot'
    environment: 'staging'
    strategy:
      runOnce:
        deploy:
          steps:
          - task: DownloadPipelineArtifact@2
            inputs:
              artifact: 'app'
              path: '$(Pipeline.Workspace)/app'

          - task: AzureWebApp@1
            displayName: 'Deploy to staging slot'
            inputs:
              azureSubscription: '$(AZURE_SUBSCRIPTION)'
              appType: 'webAppLinux'
              appName: '$(APP_NAME)'
              deployToSlotOrASE: true
              resourceGroupName: '$(RESOURCE_GROUP)'
              slotName: 'staging'
              package: '$(Pipeline.Workspace)/app/app.zip'
              runtimeStack: 'NODE|18-lts'

          - script: |
              STAGING_URL="https://$(APP_NAME)-staging.azurewebsites.net"
              echo "Testing staging: $STAGING_URL"
              for i in {1..5}; do
                STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$STAGING_URL/health")
                if [ "$STATUS" == "200" ]; then
                  echo "✅ Staging health check passed (attempt $i)"
                  exit 0
                fi
                echo "Attempt $i: status=$STATUS, retrying..."
                sleep 10
              done
              echo "❌ Staging health check failed"
              exit 1
            displayName: 'Smoke test staging'

# ── Deploy to Production ──────────────────────────────────────────────────────
- stage: DeployProduction
  displayName: '🏭 Deploy Production'
  dependsOn: DeployStaging
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
  - deployment: DeployProduction
    displayName: 'Swap to Production'
    environment: 'production'  # Requires approval in Azure DevOps
    strategy:
      runOnce:
        deploy:
          steps:
          - task: AzureAppServiceManage@0
            displayName: 'Swap staging → production'
            inputs:
              azureSubscription: '$(AZURE_SUBSCRIPTION)'
              Action: 'Swap Slots'
              WebAppName: '$(APP_NAME)'
              ResourceGroupName: '$(RESOURCE_GROUP)'
              SourceSlot: 'staging'
              SwapWithProduction: true

          - script: |
              PROD_URL="https://$(APP_NAME).azurewebsites.net"
              echo "Verifying production: $PROD_URL"
              for i in {1..10}; do
                STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$PROD_URL/health")
                if [ "$STATUS" == "200" ]; then
                  echo "✅ Production health check passed"
                  exit 0
                fi
                sleep 15
              done
              echo "❌ Production health check failed — initiating rollback"
              exit 1
            displayName: 'Production health check'

          - task: AzureAppServiceManage@0
            condition: failed()
            displayName: '🔄 Rollback on failure'
            inputs:
              azureSubscription: '$(AZURE_SUBSCRIPTION)'
              Action: 'Swap Slots'
              WebAppName: '$(APP_NAME)'
              ResourceGroupName: '$(RESOURCE_GROUP)'
              SourceSlot: 'staging'
              SwapWithProduction: true
```

## Step 5: Configure Environments with Approvals

```bash
# In Azure DevOps UI:
# Pipelines → Environments → production → Approvals and checks
# Add: Approvals → Add approver (your email)
# Add: Branch control → Only allow main branch

echo "Configure in Azure DevOps UI:"
echo "1. Pipelines → Environments → Create 'staging' and 'production'"
echo "2. production → Approvals and checks → Add approval"
echo "3. Add yourself as required approver"
echo "4. Set timeout: 1 hour"
```

## Step 6: Add Branch Policies

```bash
# Require PR reviews before merging to main
az repos policy approver-count create \
  --branch main \
  --is-blocking true \
  --repository-id $REPO_ID \
  --minimum-approver-count 1 \
  --creator-vote-counts false \
  --allow-downvotes false \
  --reset-on-source-push true

# Require CI to pass before merge
az repos policy build create \
  --branch main \
  --is-blocking true \
  --repository-id $REPO_ID \
  --build-definition-id $PIPELINE_ID \
  --valid-duration 720 \
  --queue-on-source-update-only false \
  --manual-queue-only false \
  --display-name "CI must pass"
```

## Expected Outcomes
- ✅ Pipeline triggers on push to main/develop
- ✅ Tests run with coverage reporting
- ✅ Artifact published and deployed to staging
- ✅ Smoke tests validate staging deployment
- ✅ Manual approval required for production
- ✅ Slot swap for zero-downtime production deployment
- ✅ Automatic rollback on health check failure
- ✅ Branch policies enforce code review

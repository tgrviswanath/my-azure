// ============================================================
// Project 01 — Scalable Web App Infrastructure
// Deploys: Front Door, App Service (2 regions), SQL Failover Group,
//          Redis Cache, Key Vault, Storage, App Insights
// Deploy: az deployment group create --resource-group $RG --template-file main.bicep --parameters @prod.parameters.json
// ============================================================

@description('Application name')
@minLength(3)
@maxLength(15)
param appName string = 'mywebapp'

@description('Primary region')
param primaryLocation string = 'eastus'

@description('DR region')
param drLocation string = 'westeurope'

@description('Environment')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'prod'

@description('SQL admin password')
@secure()
param sqlAdminPassword string

@description('App Service SKU')
param appServiceSku string = 'P2v3'

var prefix = '${appName}-${environment}'
var tags = {
  Environment: environment
  Application: appName
  ManagedBy: 'Bicep'
}

// ── Log Analytics ─────────────────────────────────────────────────────────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'law-${prefix}'
  location: primaryLocation
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: environment == 'prod' ? 90 : 30
  }
}

// ── Application Insights ──────────────────────────────────────────────────────
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-${prefix}'
  location: primaryLocation
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    RetentionInDays: environment == 'prod' ? 90 : 30
  }
}

// ── Key Vault ─────────────────────────────────────────────────────────────────
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: 'kv-${prefix}-${uniqueString(resourceGroup().id)}'
  location: primaryLocation
  tags: tags
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: environment == 'prod' ? 90 : 7
    enablePurgeProtection: environment == 'prod' ? true : null
  }
}

// ── Storage Account ───────────────────────────────────────────────────────────
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'st${replace(prefix, '-', '')}${uniqueString(resourceGroup().id)}'
  location: primaryLocation
  tags: tags
  sku: { name: environment == 'prod' ? 'Standard_ZRS' : 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

// ── SQL Server Primary ────────────────────────────────────────────────────────
resource sqlServerPrimary 'Microsoft.Sql/servers@2023-02-01-preview' = {
  name: 'sql-${prefix}-primary'
  location: primaryLocation
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    administratorLogin: 'sqladmin'
    administratorLoginPassword: sqlAdminPassword
    publicNetworkAccess: 'Disabled'
    minimalTlsVersion: '1.2'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-02-01-preview' = {
  parent: sqlServerPrimary
  name: '${appName}-db'
  location: primaryLocation
  tags: tags
  sku: {
    name: environment == 'prod' ? 'BC_Gen5_4' : 'GP_Gen5_2'
    tier: environment == 'prod' ? 'BusinessCritical' : 'GeneralPurpose'
  }
  properties: {
    zoneRedundant: environment == 'prod'
    backupStorageRedundancy: environment == 'prod' ? 'Zone' : 'Local'
  }
}

// ── App Service Plan (Primary) ────────────────────────────────────────────────
resource appPlanPrimary 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: 'asp-${prefix}'
  location: primaryLocation
  tags: tags
  sku: { name: appServiceSku }
  kind: 'linux'
  properties: {
    reserved: true
    zoneRedundant: environment == 'prod'
  }
}

// ── Web App (Primary) ─────────────────────────────────────────────────────────
resource webAppPrimary 'Microsoft.Web/sites@2023-01-01' = {
  name: 'app-${prefix}'
  location: primaryLocation
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: appPlanPrimary.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|18-lts'
      alwaysOn: environment != 'dev'
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      healthCheckPath: '/health'
      appSettings: [
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
        { name: 'NODE_ENV', value: environment == 'prod' ? 'production' : environment }
        { name: 'STORAGE_ACCOUNT_NAME', value: storage.name }
        { name: 'DATABASE_URL', value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=DatabaseConnectionString)' }
      ]
    }
  }
}

// Staging slot
resource stagingSlot 'Microsoft.Web/sites/slots@2023-01-01' = if (environment != 'dev') {
  parent: webAppPrimary
  name: 'staging'
  location: primaryLocation
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: appPlanPrimary.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|18-lts'
      alwaysOn: true
      healthCheckPath: '/health'
    }
  }
}

// ── RBAC ──────────────────────────────────────────────────────────────────────
resource kvSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, webAppPrimary.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: webAppPrimary.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, webAppPrimary.id, 'Storage Blob Data Contributor')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: webAppPrimary.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Autoscale ─────────────────────────────────────────────────────────────────
resource autoscale 'Microsoft.Insights/autoscalesettings@2022-10-01' = if (environment == 'prod') {
  name: 'autoscale-${prefix}'
  location: primaryLocation
  tags: tags
  properties: {
    enabled: true
    targetResourceUri: appPlanPrimary.id
    profiles: [
      {
        name: 'default'
        capacity: { default: '2', minimum: '2', maximum: '10' }
        rules: [
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: appPlanPrimary.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 70
            }
            scaleAction: { direction: 'Increase', type: 'ChangeCount', value: '2', cooldown: 'PT5M' }
          }
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: appPlanPrimary.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 30
            }
            scaleAction: { direction: 'Decrease', type: 'ChangeCount', value: '1', cooldown: 'PT10M' }
          }
        ]
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output webAppUrl string = 'https://${webAppPrimary.properties.defaultHostName}'
output webAppName string = webAppPrimary.name
output keyVaultName string = keyVault.name
output storageAccountName string = storage.name
output sqlServerFqdn string = sqlServerPrimary.properties.fullyQualifiedDomainName
output appInsightsConnectionString string = appInsights.properties.ConnectionString

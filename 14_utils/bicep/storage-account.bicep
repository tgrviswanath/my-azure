// ============================================================
// Bicep Module: Storage Account
// Reusable module for creating a production-grade storage account
// Usage: module storage 'storage-account.bicep' = { ... }
// ============================================================

@description('Storage account name (3-24 chars, lowercase, no hyphens)')
@minLength(3)
@maxLength(24)
param name string

@description('Azure region')
param location string = resourceGroup().location

@description('Storage SKU')
@allowed(['Standard_LRS', 'Standard_ZRS', 'Standard_GRS', 'Standard_GZRS', 'Premium_LRS', 'Premium_ZRS'])
param sku string = 'Standard_ZRS'

@description('Access tier for blob storage')
@allowed(['Hot', 'Cool'])
param accessTier string = 'Hot'

@description('Enable hierarchical namespace (Data Lake Gen2)')
param enableHns bool = false

@description('Enable blob versioning')
param enableVersioning bool = false

@description('Soft delete retention days (0 = disabled)')
@minValue(0)
@maxValue(365)
param softDeleteDays int = 7

@description('Allowed VNet subnet IDs')
param allowedSubnetIds array = []

@description('Allowed IP addresses/ranges')
param allowedIpRanges array = []

@description('Containers to create')
param containers array = []

@description('Lifecycle rules')
param lifecycleRules array = []

@description('Tags')
param tags object = {}

// ── Storage Account ───────────────────────────────────────────────────────────
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: name
  location: location
  tags: tags
  sku: { name: sku }
  kind: 'StorageV2'
  properties: {
    accessTier: accessTier
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    isHnsEnabled: enableHns
    networkAcls: {
      defaultAction: empty(allowedSubnetIds) && empty(allowedIpRanges) ? 'Allow' : 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: [for subnetId in allowedSubnetIds: {
        id: subnetId
        action: 'Allow'
      }]
      ipRules: [for ip in allowedIpRanges: {
        value: ip
        action: 'Allow'
      }]
    }
  }
}

// ── Blob Service ──────────────────────────────────────────────────────────────
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: softDeleteDays > 0 ? {
      enabled: true
      days: softDeleteDays
    } : { enabled: false }
    containerDeleteRetentionPolicy: softDeleteDays > 0 ? {
      enabled: true
      days: softDeleteDays
    } : { enabled: false }
    isVersioningEnabled: enableVersioning
    changeFeed: enableVersioning ? { enabled: true } : { enabled: false }
  }
}

// ── Containers ────────────────────────────────────────────────────────────────
resource blobContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for container in containers: {
  parent: blobService
  name: container.name
  properties: {
    publicAccess: contains(container, 'publicAccess') ? container.publicAccess : 'None'
    metadata: contains(container, 'metadata') ? container.metadata : {}
  }
}]

// ── Lifecycle Policy ──────────────────────────────────────────────────────────
resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-01-01' = if (!empty(lifecycleRules)) {
  parent: storageAccount
  name: 'default'
  properties: {
    policy: {
      rules: lifecycleRules
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output id string = storageAccount.id
output name string = storageAccount.name
output primaryEndpoints object = storageAccount.properties.primaryEndpoints
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob

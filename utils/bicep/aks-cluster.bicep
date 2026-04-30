// ============================================================
// Bicep Module: AKS Cluster
// Production-grade AKS with zone redundancy, RBAC, monitoring
// ============================================================

@description('AKS cluster name')
param clusterName string

@description('Azure region')
param location string = resourceGroup().location

@description('Kubernetes version')
param kubernetesVersion string = '1.28'

@description('System node pool VM size')
param systemNodeSize string = 'Standard_D4s_v5'

@description('User node pool VM size')
param userNodeSize string = 'Standard_D4s_v5'

@description('Min user node count')
@minValue(1)
param minUserNodes int = 2

@description('Max user node count')
@maxValue(100)
param maxUserNodes int = 10

@description('Log Analytics workspace resource ID')
param logAnalyticsWorkspaceId string

@description('VNet subnet resource ID for nodes')
param nodeSubnetId string

@description('ACR resource ID to attach')
param acrId string = ''

@description('Tags')
param tags object = {}

// ── AKS Cluster ───────────────────────────────────────────────────────────────
resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-07-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: clusterName
    enableRBAC: true

    // AAD integration
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }

    // Network
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }

    // System node pool
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: 3
        vmSize: systemNodeSize
        osDiskSizeGB: 128
        osDiskType: 'Managed'
        osType: 'Linux'
        osSKU: 'Ubuntu'
        vnetSubnetID: nodeSubnetId
        availabilityZones: ['1', '2', '3']
        enableAutoScaling: false
        nodeTaints: ['CriticalAddonsOnly=true:NoSchedule']
        upgradeSettings: {
          maxSurge: '1'
        }
      }
      {
        name: 'user'
        mode: 'User'
        count: minUserNodes
        vmSize: userNodeSize
        osDiskSizeGB: 128
        osDiskType: 'Managed'
        osType: 'Linux'
        osSKU: 'Ubuntu'
        vnetSubnetID: nodeSubnetId
        availabilityZones: ['1', '2', '3']
        enableAutoScaling: true
        minCount: minUserNodes
        maxCount: maxUserNodes
        upgradeSettings: {
          maxSurge: '1'
        }
        nodeLabels: {
          'nodepool-type': 'user'
          'environment': 'production'
        }
      }
    ]

    // Add-ons
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
      azurepolicy: {
        enabled: true
      }
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
    }

    // Security
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
      imageCleaner: {
        enabled: true
        intervalHours: 48
      }
    }

    // Auto-upgrade
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
    }

    // Storage
    storageProfile: {
      diskCSIDriver: { enabled: true }
      fileCSIDriver: { enabled: true }
      snapshotController: { enabled: true }
    }
  }
}

// ── ACR Pull Role Assignment ──────────────────────────────────────────────────
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(acrId)) {
  name: guid(acrId, aksCluster.id, 'AcrPull')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: aksCluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output clusterName string = aksCluster.name
output clusterId string = aksCluster.id
output clusterFqdn string = aksCluster.properties.fqdn
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
output principalId string = aksCluster.identity.principalId

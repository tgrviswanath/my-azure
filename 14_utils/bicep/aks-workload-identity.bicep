// ============================================================
// Bicep — AKS Workload Identity Setup
// Creates managed identity + federated credential for a K8s service account
// Deploy: az deployment group create -g $RG -f aks-workload-identity.bicep
// ============================================================

@description('AKS cluster name')
param aksClusterName string

@description('Resource group of AKS cluster')
param aksResourceGroup string = resourceGroup().name

@description('Kubernetes namespace')
param k8sNamespace string = 'production'

@description('Kubernetes service account name')
param k8sServiceAccountName string

@description('Name for the managed identity')
param identityName string

@description('Azure region')
param location string = resourceGroup().location

// ── Get AKS OIDC Issuer URL ───────────────────────────────────────────────────
resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-07-01' existing = {
  name: aksClusterName
  scope: resourceGroup(aksResourceGroup)
}

// ── Create User-Assigned Managed Identity ─────────────────────────────────────
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: {
    AKSCluster: aksClusterName
    K8sNamespace: k8sNamespace
    K8sServiceAccount: k8sServiceAccountName
  }
}

// ── Create Federated Identity Credential ─────────────────────────────────────
// This links the K8s service account to the managed identity
resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: managedIdentity
  name: '${aksClusterName}-${k8sNamespace}-${k8sServiceAccountName}'
  properties: {
    issuer: aksCluster.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${k8sNamespace}:${k8sServiceAccountName}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output identityClientId string = managedIdentity.properties.clientId
output identityPrincipalId string = managedIdentity.properties.principalId
output identityResourceId string = managedIdentity.id
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL

// ── Usage Instructions ────────────────────────────────────────────────────────
// After deploying, create the K8s service account:
//
// kubectl create serviceaccount ${k8sServiceAccountName} -n ${k8sNamespace}
// kubectl annotate serviceaccount ${k8sServiceAccountName} \
//   -n ${k8sNamespace} \
//   azure.workload.identity/client-id=<identityClientId>
//
// Then grant the identity access to Azure resources:
// az role assignment create \
//   --assignee <identityPrincipalId> \
//   --role "Key Vault Secrets User" \
//   --scope <keyVaultId>

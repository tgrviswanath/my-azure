// Bicep parameters file for production deployment
// Usage: az deployment group create --resource-group $RG --template-file main.bicep --parameters prod.parameters.bicepparam

using 'main.bicep'

param appName         = 'mywebapp'
param primaryLocation = 'eastus'
param drLocation      = 'westeurope'
param environment     = 'prod'
param appServiceSku   = 'P2v3'
// sqlAdminPassword: set via environment variable
// export AZURE_SQL_PASSWORD=$(openssl rand -base64 32)
// az deployment group create ... --parameters sqlAdminPassword=$AZURE_SQL_PASSWORD

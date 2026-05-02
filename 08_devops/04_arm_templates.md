# ARM Templates — Azure Resource Manager Deep Dive

## ARM Template Structure

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": { },
  "variables": { },
  "functions": [ ],
  "resources": [ ],
  "outputs": { }
}
```

## Key Concepts

### Parameters
```json
"parameters": {
  "appName": {
    "type": "string",
    "minLength": 3,
    "maxLength": 24,
    "metadata": { "description": "Application name" }
  },
  "environment": {
    "type": "string",
    "defaultValue": "dev",
    "allowedValues": ["dev", "staging", "prod"]
  },
  "adminPassword": {
    "type": "securestring"
  },
  "instanceCount": {
    "type": "int",
    "defaultValue": 2,
    "minValue": 1,
    "maxValue": 10
  }
}
```

### Variables & Functions
```json
"variables": {
  "prefix": "[concat(parameters('appName'), '-', parameters('environment'))]",
  "uniqueSuffix": "[uniqueString(resourceGroup().id)]",
  "storageAccountName": "[toLower(concat('st', replace(variables('prefix'), '-', ''), variables('uniqueSuffix')))]",
  "tags": {
    "Environment": "[parameters('environment')]",
    "ManagedBy": "ARM"
  },
  "skuMap": {
    "dev": "B1",
    "staging": "S2",
    "prod": "P2v3"
  },
  "appServiceSku": "[variables('skuMap')[parameters('environment')]]"
}
```

### Resource Dependencies
```json
"resources": [
  {
    "type": "Microsoft.Storage/storageAccounts",
    "apiVersion": "2023-01-01",
    "name": "[variables('storageAccountName')]",
    "location": "[parameters('location')]",
    "sku": { "name": "Standard_ZRS" },
    "kind": "StorageV2"
  },
  {
    "type": "Microsoft.Web/sites",
    "apiVersion": "2023-01-01",
    "name": "[variables('webAppName')]",
    "location": "[parameters('location')]",
    "dependsOn": [
      "[resourceId('Microsoft.Web/serverfarms', variables('planName'))]",
      "[resourceId('Microsoft.Storage/storageAccounts', variables('storageAccountName'))]"
    ],
    "identity": { "type": "SystemAssigned" },
    "properties": {
      "serverFarmId": "[resourceId('Microsoft.Web/serverfarms', variables('planName'))]",
      "siteConfig": {
        "appSettings": [
          {
            "name": "STORAGE_ACCOUNT",
            "value": "[variables('storageAccountName')]"
          },
          {
            "name": "STORAGE_KEY",
            "value": "[listKeys(resourceId('Microsoft.Storage/storageAccounts', variables('storageAccountName')), '2023-01-01').keys[0].value]"
          }
        ]
      }
    }
  }
]
```

### Copy (Loops)
```json
{
  "type": "Microsoft.Storage/storageAccounts",
  "apiVersion": "2023-01-01",
  "name": "[concat('storage', copyIndex())]",
  "location": "[parameters('location')]",
  "sku": { "name": "Standard_LRS" },
  "kind": "StorageV2",
  "copy": {
    "name": "storageCopy",
    "count": "[parameters('storageCount')]",
    "mode": "Parallel"
  }
}
```

### Conditions
```json
{
  "type": "Microsoft.Sql/servers/databases",
  "condition": "[equals(parameters('environment'), 'prod')]",
  "name": "[concat(variables('sqlServerName'), '/replica-db')]",
  "properties": {
    "createMode": "Secondary",
    "sourceDatabaseId": "[resourceId('Microsoft.Sql/servers/databases', variables('sqlServerName'), variables('dbName'))]"
  }
}
```

## Deployment Commands

```bash
# Validate template
az deployment group validate \
  --resource-group $RG \
  --template-file main.json \
  --parameters @params.json

# What-if (preview changes)
az deployment group what-if \
  --resource-group $RG \
  --template-file main.json \
  --parameters @params.json

# Deploy
az deployment group create \
  --resource-group $RG \
  --template-file main.json \
  --parameters @params.json \
  --name "deploy-$(date +%Y%m%d-%H%M%S)" \
  --mode Incremental

# Complete mode (deletes resources not in template — use carefully!)
az deployment group create \
  --resource-group $RG \
  --template-file main.json \
  --mode Complete

# Deploy at subscription scope
az deployment sub create \
  --location $LOCATION \
  --template-file subscription-template.json \
  --parameters @params.json

# Export existing resource as ARM template
az group export \
  --resource-group $RG \
  --output json > exported-template.json

# Check deployment status
az deployment group show \
  --resource-group $RG \
  --name "deploy-20240115-120000" \
  --query "properties.provisioningState"

# List deployments
az deployment group list \
  --resource-group $RG \
  --output table
```

## Linked Templates

```json
{
  "type": "Microsoft.Resources/deployments",
  "apiVersion": "2022-09-01",
  "name": "storageDeployment",
  "properties": {
    "mode": "Incremental",
    "templateLink": {
      "uri": "https://raw.githubusercontent.com/user/repo/main/storage.json",
      "contentVersion": "1.0.0.0"
    },
    "parameters": {
      "storageAccountName": { "value": "[variables('storageAccountName')]" },
      "location": { "value": "[parameters('location')]" }
    }
  }
}
```

## ARM vs Bicep vs Terraform

| Feature | ARM JSON | Bicep | Terraform |
|---------|----------|-------|-----------|
| Language | JSON | DSL (compiles to ARM) | HCL |
| Learning curve | High | Medium | Medium |
| Azure-native | Yes | Yes | No (multi-cloud) |
| State management | None (idempotent) | None | State file |
| Modules | Linked templates | Modules | Modules |
| IDE support | Good | Excellent | Good |
| Multi-cloud | No | No | Yes |
| Community | Large | Growing | Very large |
| Recommended | Legacy | New Azure projects | Multi-cloud |

## Interview Questions

### Q1: What is the difference between Incremental and Complete deployment modes?
**Answer:**
- **Incremental** (default): Adds/updates resources in template. Resources NOT in template are left unchanged. Safe for most deployments.
- **Complete**: Deletes resources in resource group NOT in template. Dangerous — can delete production resources. Use only for full environment management.

### Q2: What is `dependsOn` and when do you need it?
**Answer:**
`dependsOn` explicitly declares deployment order. ARM automatically detects dependencies via `resourceId()` references. Only use `dependsOn` when there's an implicit dependency not expressed through resource references (e.g., a script that must run after a VM is created but doesn't reference it directly).

### Q3: What is the difference between ARM templates and Bicep?
**Answer:**
Bicep is a DSL that compiles to ARM JSON. Benefits of Bicep: cleaner syntax, type safety, better IDE support, modules, no need for `dependsOn` (auto-detected), string interpolation. ARM JSON is verbose but is the underlying format. Use Bicep for new projects; ARM for legacy or when you need exact JSON control.

### Q4: How do you handle secrets in ARM templates?
**Answer:**
1. Use `securestring` parameter type (not logged, not stored in deployment history)
2. Reference Key Vault secrets in parameters file: `{"reference": {"keyVault": {"id": "..."}, "secretName": "..."}}`
3. Never hardcode secrets in templates
4. Use Managed Identity + Key Vault references in app settings
5. Store parameters files securely (not in source control)

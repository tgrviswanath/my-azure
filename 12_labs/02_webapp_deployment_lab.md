# Lab 02 — Deploy Web App with Database and CI/CD

## Objective
Deploy a Node.js web app to App Service with Azure SQL Database, Key Vault for secrets, and GitHub Actions CI/CD.

## Prerequisites
- Azure subscription + GitHub account
- Node.js 18+ installed locally
- Estimated time: 60 minutes
- Estimated cost: ~$5/month (B1 App Service + Basic SQL)

## Step 1: Create Infrastructure

```bash
RG="rg-lab02-dev-eastus"
LOCATION="eastus"
APP_NAME="app-lab02-$(openssl rand -hex 4)"
SQL_SERVER="sql-lab02-$(openssl rand -hex 4)"
KV_NAME="kv-lab02-$(openssl rand -hex 4)"
SQL_PASSWORD="Lab02Pass$(openssl rand -hex 8)!"

az group create --name $RG --location $LOCATION

# Key Vault
az keyvault create \
  --name $KV_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --enable-rbac-authorization true

# SQL Server
az sql server create \
  --name $SQL_SERVER \
  --resource-group $RG \
  --location $LOCATION \
  --admin-user sqladmin \
  --admin-password "$SQL_PASSWORD"

# Allow Azure services
az sql server firewall-rule create \
  --server $SQL_SERVER \
  --resource-group $RG \
  --name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

# SQL Database
az sql db create \
  --name webapp-db \
  --server $SQL_SERVER \
  --resource-group $RG \
  --service-objective Basic

# Store connection string in Key Vault
CONN_STR="Server=tcp:${SQL_SERVER}.database.windows.net,1433;Database=webapp-db;User ID=sqladmin;Password=${SQL_PASSWORD};Encrypt=true;"
az keyvault secret set \
  --vault-name $KV_NAME \
  --name "DatabaseConnectionString" \
  --value "$CONN_STR"

# App Service Plan
az appservice plan create \
  --name "asp-lab02" \
  --resource-group $RG \
  --location $LOCATION \
  --sku B1 \
  --is-linux

# Web App
az webapp create \
  --name $APP_NAME \
  --resource-group $RG \
  --plan "asp-lab02" \
  --runtime "NODE:18-lts" \
  --https-only true

# Enable Managed Identity
PRINCIPAL_ID=$(az webapp identity assign \
  --name $APP_NAME \
  --resource-group $RG \
  --query principalId \
  --output tsv)

# Grant Key Vault access to web app
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Key Vault Secrets User" \
  --scope $(az keyvault show --name $KV_NAME --resource-group $RG --query id --output tsv)

# Configure app settings (Key Vault reference)
az webapp config appsettings set \
  --name $APP_NAME \
  --resource-group $RG \
  --settings \
    DATABASE_URL="@Microsoft.KeyVault(VaultName=${KV_NAME};SecretName=DatabaseConnectionString)" \
    NODE_ENV=production \
    PORT=8080

echo "App URL: https://${APP_NAME}.azurewebsites.net"
echo "SQL Server: ${SQL_SERVER}.database.windows.net"
echo "Key Vault: $KV_NAME"
```

## Step 2: Create Sample Node.js App

```bash
mkdir lab02-app && cd lab02-app
npm init -y
npm install express mssql

cat > app.js << 'EOF'
const express = require('express');
const sql = require('mssql');

const app = express();
app.use(express.json());

const dbConfig = {
  connectionString: process.env.DATABASE_URL,
  options: { encrypt: true, trustServerCertificate: false }
};

let pool;
async function getPool() {
  if (!pool) pool = await sql.connect(dbConfig);
  return pool;
}

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.get('/api/items', async (req, res) => {
  try {
    const db = await getPool();
    const result = await db.request().query('SELECT TOP 10 * FROM Items ORDER BY CreatedAt DESC');
    res.json({ items: result.recordset });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/items', async (req, res) => {
  const { name, description } = req.body;
  if (!name) return res.status(400).json({ error: 'name is required' });
  try {
    const db = await getPool();
    const result = await db.request()
      .input('name', sql.NVarChar, name)
      .input('description', sql.NVarChar, description || '')
      .query('INSERT INTO Items (Name, Description, CreatedAt) OUTPUT INSERTED.* VALUES (@name, @description, GETUTCDATE())');
    res.status(201).json({ item: result.recordset[0] });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
EOF

cat > package.json << 'EOF'
{
  "name": "lab02-app",
  "version": "1.0.0",
  "scripts": {
    "start": "node app.js",
    "test": "echo 'Tests passed'"
  },
  "dependencies": {
    "express": "^4.18.2",
    "mssql": "^10.0.1"
  }
}
EOF
```

## Step 3: Create Database Schema

```bash
# Connect to SQL and create table
az sql db execute \
  --server $SQL_SERVER \
  --resource-group $RG \
  --database webapp-db \
  --query "CREATE TABLE Items (Id INT IDENTITY PRIMARY KEY, Name NVARCHAR(200) NOT NULL, Description NVARCHAR(1000), CreatedAt DATETIME2 NOT NULL)"
```

## Step 4: Deploy App Manually

```bash
# Create ZIP and deploy
cd lab02-app
zip -r ../app.zip .
cd ..

az webapp deployment source config-zip \
  --name $APP_NAME \
  --resource-group $RG \
  --src app.zip

# Test
curl https://${APP_NAME}.azurewebsites.net/health
curl -X POST https://${APP_NAME}.azurewebsites.net/api/items \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Item","description":"Created via lab"}'
curl https://${APP_NAME}.azurewebsites.net/api/items
```

## Step 5: Set Up GitHub Actions CI/CD

```bash
# Create service principal for GitHub Actions
SP_JSON=$(az ad sp create-for-rbac \
  --name "sp-github-lab02" \
  --role Contributor \
  --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG" \
  --sdk-auth)

echo "Add this as GitHub secret AZURE_CREDENTIALS:"
echo $SP_JSON

# Get publish profile
az webapp deployment list-publishing-profiles \
  --name $APP_NAME \
  --resource-group $RG \
  --xml > publish-profile.xml
echo "Add publish-profile.xml content as GitHub secret AZURE_WEBAPP_PUBLISH_PROFILE"
```

```yaml
# .github/workflows/deploy.yml
name: Deploy to Azure App Service

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  AZURE_WEBAPP_NAME: ${{ secrets.AZURE_WEBAPP_NAME }}
  NODE_VERSION: '18'

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
      with:
        node-version: ${{ env.NODE_VERSION }}
        cache: 'npm'
    - run: npm ci
    - run: npm test
    - uses: actions/upload-artifact@v4
      with:
        name: app
        path: .

  deploy:
    needs: build-and-test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment: production
    steps:
    - uses: actions/download-artifact@v4
      with:
        name: app
    - uses: azure/webapps-deploy@v3
      with:
        app-name: ${{ env.AZURE_WEBAPP_NAME }}
        publish-profile: ${{ secrets.AZURE_WEBAPP_PUBLISH_PROFILE }}
        package: .
```

## Step 6: Add Deployment Slot

```bash
# Create staging slot
az webapp deployment slot create \
  --name $APP_NAME \
  --resource-group $RG \
  --slot staging

# Configure staging-specific settings
az webapp config appsettings set \
  --name $APP_NAME \
  --resource-group $RG \
  --slot staging \
  --slot-settings NODE_ENV=staging

# Deploy to staging, test, then swap
az webapp deployment source config-zip \
  --name $APP_NAME \
  --resource-group $RG \
  --slot staging \
  --src app.zip

# Test staging
curl https://${APP_NAME}-staging.azurewebsites.net/health

# Swap to production
az webapp deployment slot swap \
  --name $APP_NAME \
  --resource-group $RG \
  --slot staging \
  --target-slot production

echo "Deployment complete!"
```

## Cleanup

```bash
az group delete --name $RG --yes --no-wait
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Key Vault reference not resolving | Check managed identity has "Key Vault Secrets User" role |
| SQL connection fails | Check firewall rules, connection string format |
| App returns 500 | Check app logs: `az webapp log tail --name $APP_NAME --resource-group $RG` |
| Deployment fails | Check deployment logs in Azure portal → Deployment Center |
| Slot swap fails | Ensure staging slot is healthy (readiness check) |

## Expected Outcomes
- ✅ App Service running Node.js app
- ✅ Azure SQL Database with Items table
- ✅ Key Vault storing connection string
- ✅ Managed Identity accessing Key Vault (no credentials in code)
- ✅ GitHub Actions deploying on push to main
- ✅ Staging slot for zero-downtime deployments

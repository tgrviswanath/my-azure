# Lab 06 — Azure Functions: Serverless Order Processing

## Objective
Build a serverless order processing system using Azure Functions with HTTP triggers, Service Bus, Cosmos DB, and Durable Functions.

## Prerequisites
- Azure subscription
- Node.js 18+, Azure Functions Core Tools v4
- Estimated time: 60 minutes
- Estimated cost: ~$0 (within free tier)

## Step 1: Setup Infrastructure

```bash
RG="rg-lab06-dev-eastus"
LOCATION="eastus"
FUNC_APP="func-lab06-$(openssl rand -hex 4)"
STORAGE_NAME="stlab06$(openssl rand -hex 4)"
COSMOS_NAME="cosmos-lab06-$(openssl rand -hex 4)"
SB_NAMESPACE="sbns-lab06-$(openssl rand -hex 4)"

az group create --name $RG --location $LOCATION

# Storage for Function App
az storage account create --name $STORAGE_NAME --resource-group $RG \
  --location $LOCATION --sku Standard_LRS --kind StorageV2

# Cosmos DB (Serverless — pay per RU, no minimum cost)
az cosmosdb create --name $COSMOS_NAME --resource-group $RG \
  --locations regionName=$LOCATION failoverPriority=0 \
  --default-consistency-level Session

az cosmosdb sql database create --account-name $COSMOS_NAME \
  --resource-group $RG --name "lab06-db"

az cosmosdb sql container create --account-name $COSMOS_NAME \
  --resource-group $RG --database-name "lab06-db" \
  --name "orders" --partition-key-path "/customerId" --throughput 400

az cosmosdb sql container create --account-name $COSMOS_NAME \
  --resource-group $RG --database-name "lab06-db" \
  --name "leases" --partition-key-path "/id" --throughput 400

# Service Bus
az servicebus namespace create --name $SB_NAMESPACE --resource-group $RG \
  --location $LOCATION --sku Standard

az servicebus queue create --name "orders" \
  --namespace-name $SB_NAMESPACE --resource-group $RG \
  --max-delivery-count 5 --dead-lettering-on-message-expiration true

# Function App
az functionapp create --name $FUNC_APP --resource-group $RG \
  --storage-account $STORAGE_NAME --consumption-plan-location $LOCATION \
  --runtime node --runtime-version 18 --functions-version 4 --os-type Linux

# Get connection strings
COSMOS_CONN=$(az cosmosdb keys list --name $COSMOS_NAME --resource-group $RG \
  --type connection-strings --query "connectionStrings[0].connectionString" --output tsv)
SB_CONN=$(az servicebus namespace authorization-rule keys list \
  --namespace-name $SB_NAMESPACE --resource-group $RG \
  --name RootManageSharedAccessKey --query primaryConnectionString --output tsv)

# Configure app settings
az functionapp config appsettings set --name $FUNC_APP --resource-group $RG \
  --settings \
    CosmosDBConnection="$COSMOS_CONN" \
    ServiceBusConnection="$SB_CONN" \
    COSMOS_DATABASE="lab06-db" \
    COSMOS_CONTAINER="orders"

echo "Function App: https://${FUNC_APP}.azurewebsites.net"
```

## Step 2: Create Function App Locally

```bash
mkdir lab06-functions && cd lab06-functions
func init --worker-runtime node --language javascript
npm install @azure/functions @azure/cosmos @azure/service-bus

# Create HTTP trigger function
func new --name CreateOrder --template "HTTP trigger" --authlevel function

# Create Service Bus trigger
func new --name ProcessOrder --template "Azure Service Bus Queue trigger"

# Create Timer trigger
func new --name DailyReport --template "Timer trigger"
```

## Step 3: Implement Functions

```javascript
// src/functions/createOrder.js
const { app, output } = require('@azure/functions');

const serviceBusOutput = output.serviceBusQueue({
  queueName: 'orders',
  connection: 'ServiceBusConnection',
});

app.http('createOrder', {
  methods: ['POST'],
  authLevel: 'function',
  route: 'orders',
  return: serviceBusOutput,
  handler: async (request, context) => {
    let body;
    try { body = await request.json(); }
    catch { return { status: 400, jsonBody: { error: 'Invalid JSON' } }; }

    const { productId, quantity, customerId } = body;
    if (!productId || !quantity || !customerId) {
      return { status: 422, jsonBody: { error: 'productId, quantity, customerId required' } };
    }

    const order = {
      id:         `order-${Date.now()}`,
      productId,
      quantity:   parseInt(quantity),
      customerId,
      status:     'pending',
      createdAt:  new Date().toISOString(),
    };

    context.log('Order queued:', order.id);
    return {
      status: 202,
      jsonBody: { orderId: order.id, status: 'queued' },
      value: JSON.stringify(order),
    };
  },
});
```

```javascript
// src/functions/processOrder.js
const { app } = require('@azure/functions');
const { CosmosClient } = require('@azure/cosmos');

const client = new CosmosClient(process.env.CosmosDBConnection);
const container = client
  .database(process.env.COSMOS_DATABASE)
  .container(process.env.COSMOS_CONTAINER);

app.serviceBusQueue('processOrder', {
  queueName: 'orders',
  connection: 'ServiceBusConnection',
  handler: async (message, context) => {
    const order = typeof message === 'string' ? JSON.parse(message) : message;
    context.log('Processing order:', order.id);

    try {
      // Simulate processing
      await new Promise(r => setTimeout(r, 100));

      const processed = {
        ...order,
        status:      'completed',
        processedAt: new Date().toISOString(),
        total:       order.quantity * 9.99,
      };

      await container.items.upsert(processed);
      context.log('Order completed:', order.id);
    } catch (err) {
      context.log.error('Order failed:', order.id, err.message);
      // Throw to trigger retry / dead-letter
      throw err;
    }
  },
});
```

```javascript
// src/functions/getOrder.js
const { app } = require('@azure/functions');
const { CosmosClient } = require('@azure/cosmos');

const client = new CosmosClient(process.env.CosmosDBConnection);
const container = client
  .database(process.env.COSMOS_DATABASE)
  .container(process.env.COSMOS_CONTAINER);

app.http('getOrder', {
  methods: ['GET'],
  authLevel: 'function',
  route: 'orders/{orderId}',
  handler: async (request, context) => {
    const { orderId } = request.params;
    try {
      const { resource } = await container.item(orderId, orderId).read();
      if (!resource) return { status: 404, jsonBody: { error: 'Order not found' } };
      return { status: 200, jsonBody: resource };
    } catch (err) {
      if (err.code === 404) return { status: 404, jsonBody: { error: 'Order not found' } };
      return { status: 500, jsonBody: { error: err.message } };
    }
  },
});
```

```javascript
// src/functions/dailyReport.js
const { app } = require('@azure/functions');
const { CosmosClient } = require('@azure/cosmos');

const client = new CosmosClient(process.env.CosmosDBConnection);
const container = client
  .database(process.env.COSMOS_DATABASE)
  .container(process.env.COSMOS_CONTAINER);

app.timer('dailyReport', {
  schedule: '0 0 8 * * *',  // 8 AM daily
  handler: async (myTimer, context) => {
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    yesterday.setHours(0, 0, 0, 0);

    const { resources: orders } = await container.items.query({
      query: 'SELECT * FROM c WHERE c.createdAt >= @since AND c.status = "completed"',
      parameters: [{ name: '@since', value: yesterday.toISOString() }],
    }).fetchAll();

    const report = {
      date:       yesterday.toISOString().split('T')[0],
      totalOrders: orders.length,
      totalRevenue: orders.reduce((s, o) => s + (o.total || 0), 0).toFixed(2),
      avgOrderValue: orders.length > 0
        ? (orders.reduce((s, o) => s + (o.total || 0), 0) / orders.length).toFixed(2)
        : '0.00',
    };

    context.log('Daily report:', report);
  },
});
```

## Step 4: Deploy and Test

```bash
# Deploy
func azure functionapp publish $FUNC_APP --javascript

# Get function key
FUNC_KEY=$(az functionapp keys list --name $FUNC_APP --resource-group $RG \
  --query "functionKeys.default" --output tsv)

BASE_URL="https://${FUNC_APP}.azurewebsites.net/api"

# Create order
ORDER_ID=$(curl -s -X POST "${BASE_URL}/orders?code=${FUNC_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"productId":"prod-123","quantity":2,"customerId":"cust-456"}' \
  | jq -r '.orderId')

echo "Created order: $ORDER_ID"

# Wait for processing
sleep 5

# Get order
curl -s "${BASE_URL}/orders/${ORDER_ID}?code=${FUNC_KEY}" | jq .

# Check Service Bus dead-letter queue
az servicebus queue show \
  --name "orders" \
  --namespace-name $SB_NAMESPACE \
  --resource-group $RG \
  --query "countDetails.deadLetterMessageCount"
```

## Step 5: Monitor

```bash
# Stream live logs
func azure functionapp logstream $FUNC_APP

# View in Application Insights
echo "View in Azure portal:"
echo "  Function App → Monitor → Invocations"
echo "  Application Insights → Live Metrics"
echo "  Application Insights → Failures"
```

## Cleanup

```bash
az group delete --name $RG --yes --no-wait
```

## Expected Outcomes
- ✅ HTTP trigger creates orders and queues to Service Bus
- ✅ Service Bus trigger processes orders and saves to Cosmos DB
- ✅ GET endpoint retrieves orders from Cosmos DB
- ✅ Timer trigger runs daily report
- ✅ Dead-letter queue captures failed messages
- ✅ Application Insights shows invocations and errors

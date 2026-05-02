# Azure Functions — Serverless Computing Deep Dive

## Functions Architecture

```
Azure Functions = event-driven, serverless compute
├── Trigger: what starts the function (HTTP, timer, queue, blob, etc.)
├── Input binding: read data from external source
├── Output binding: write data to external destination
└── Runtime: Node.js, Python, .NET, Java, PowerShell, custom

Hosting Plans:
  Consumption:  Auto-scale, pay-per-execution, cold starts, 5-min timeout
  Premium:      Pre-warmed instances, no cold starts, VNet, 60-min timeout
  Dedicated:    App Service Plan, always-on, predictable cost
  Container:    Run in containers (ACA or AKS)
```

## Triggers & Bindings

```javascript
// HTTP Trigger (Node.js)
const { app } = require('@azure/functions');

app.http('httpTrigger', {
  methods: ['GET', 'POST'],
  authLevel: 'function',
  handler: async (request, context) => {
    const name = request.query.get('name') || 'World';
    return { body: `Hello, ${name}!` };
  }
});

// Timer Trigger — runs every 5 minutes
app.timer('timerTrigger', {
  schedule: '0 */5 * * * *',  // CRON: sec min hour day month weekday
  handler: async (myTimer, context) => {
    context.log('Timer fired at:', new Date().toISOString());
  }
});

// Blob Trigger — fires when blob created/modified
app.storageBlob('blobTrigger', {
  path: 'uploads/{name}',
  connection: 'AzureWebJobsStorage',
  handler: async (blob, context) => {
    context.log(`Blob ${context.triggerMetadata.name} size: ${blob.length}`);
  }
});

// Queue Trigger + output binding
app.storageQueue('queueTrigger', {
  queueName: 'orders',
  connection: 'AzureWebJobsStorage',
  return: app.output.storageBlob({
    path: 'processed/{rand-guid}.json',
    connection: 'AzureWebJobsStorage',
  }),
  handler: async (message, context) => {
    const order = JSON.parse(message);
    const processed = { ...order, processedAt: new Date().toISOString() };
    return JSON.stringify(processed);
  }
});

// Cosmos DB Trigger — fires on document changes
app.cosmosDB('cosmosTrigger', {
  databaseName: 'mydb',
  containerName: 'orders',
  connection: 'CosmosDBConnection',
  leaseContainerName: 'leases',
  createLeaseContainerIfNotExists: true,
  handler: async (documents, context) => {
    for (const doc of documents) {
      context.log('Changed document:', doc.id);
    }
  }
});
```

## Durable Functions

```javascript
// Orchestrator — coordinates long-running workflows
const df = require('durable-functions');

// Orchestrator function
df.app.orchestration('orderOrchestrator', function*(context) {
  const order = context.df.getInput();

  // Sequential activities
  const validated = yield context.df.callActivity('validateOrder', order);
  const charged   = yield context.df.callActivity('chargePayment', validated);

  // Parallel fan-out/fan-in
  const tasks = [
    context.df.callActivity('sendConfirmationEmail', charged),
    context.df.callActivity('updateInventory', charged),
    context.df.callActivity('notifyWarehouse', charged),
  ];
  const results = yield context.df.Task.all(tasks);

  // Wait for external event (human approval)
  const approval = yield context.df.waitForExternalEvent('managerApproval', '1d');
  if (!approval) throw new Error('Order not approved within 24 hours');

  return { orderId: order.id, status: 'completed', results };
});

// Activity functions
df.app.activity('validateOrder', {
  handler: async (order) => {
    // Validate order logic
    return { ...order, validated: true };
  }
});

// HTTP starter
app.http('orderStart', {
  route: 'orders',
  methods: ['POST'],
  extraInputs: [df.input.durableClient()],
  handler: async (req, context) => {
    const client = df.getClient(context);
    const order = await req.json();
    const instanceId = await client.startNew('orderOrchestrator', { input: order });
    return client.createCheckStatusResponse(req, instanceId);
  }
});
```

## Deployment

```bash
# Create function app
az functionapp create \
  --name $FUNC_APP \
  --resource-group $RG \
  --storage-account $STORAGE_NAME \
  --consumption-plan-location $LOCATION \
  --runtime node \
  --runtime-version 18 \
  --functions-version 4 \
  --os-type Linux

# Deploy using Azure Functions Core Tools
func azure functionapp publish $FUNC_APP

# Deploy using ZIP
az functionapp deployment source config-zip \
  --name $FUNC_APP \
  --resource-group $RG \
  --src ./function.zip

# Configure app settings
az functionapp config appsettings set \
  --name $FUNC_APP \
  --resource-group $RG \
  --settings \
    COSMOS_CONNECTION="AccountEndpoint=..." \
    STORAGE_CONNECTION="DefaultEndpointsProtocol=..."

# Enable Application Insights
az functionapp update \
  --name $FUNC_APP \
  --resource-group $RG \
  --set "properties.siteConfig.appSettings[0].name=APPINSIGHTS_INSTRUMENTATIONKEY" \
  --set "properties.siteConfig.appSettings[0].value=$AI_KEY"
```

## Interview Questions

### Q1: What is the difference between Consumption, Premium, and Dedicated plans?
**Answer:**
- **Consumption**: Auto-scales to zero, pay per execution (first 1M free), cold starts (0-10s), 5-min timeout. Best for: sporadic workloads.
- **Premium**: Pre-warmed instances (no cold starts), VNet integration, unlimited timeout, more powerful instances. Best for: latency-sensitive, VNet-connected workloads.
- **Dedicated**: Runs on App Service Plan, always-on, predictable cost. Best for: continuous workloads, existing App Service Plan.

### Q2: What is a cold start and how do you mitigate it?
**Answer:**
Cold start = delay when a function scales from zero (new instance initialization). Mitigation:
1. Use **Premium plan** (pre-warmed instances)
2. Use **Always Ready** instances in Premium
3. Use **timer trigger** to ping the function periodically (Consumption)
4. Minimize dependencies and startup code
5. Use .NET or Node.js (faster cold starts than Java)

### Q3: What are Durable Functions and when do you use them?
**Answer:**
Durable Functions extend Azure Functions with stateful workflows. Use for:
- **Function chaining**: sequential steps
- **Fan-out/fan-in**: parallel execution + aggregation
- **Human interaction**: wait for external events/approvals
- **Monitoring**: polling patterns
- **Sagas**: distributed transactions with compensation

### Q4: How do you secure Azure Functions?
**Answer:**
1. **Auth levels**: anonymous, function (key), admin (master key)
2. **Azure AD authentication**: use Easy Auth or custom middleware
3. **Managed Identity**: access other Azure services without credentials
4. **VNet integration**: restrict inbound/outbound traffic
5. **Private endpoints**: no public internet access
6. **Key Vault references**: store secrets in Key Vault, reference in app settings

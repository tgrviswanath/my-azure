/**
 * Azure Functions — Order Processing System
 * Demonstrates: HTTP triggers, Service Bus, Cosmos DB, Blob Storage
 */

const { app, output, input } = require('@azure/functions');
const { CosmosClient } = require('@azure/cosmos');
const { BlobServiceClient } = require('@azure/storage-blob');
const { DefaultAzureCredential } = require('@azure/identity');

// ── Cosmos DB client (using Managed Identity) ─────────────────────────────────
const cosmosClient = new CosmosClient({
  endpoint: process.env.COSMOS_ENDPOINT,
  aadCredentials: new DefaultAzureCredential(),
});
const container = cosmosClient
  .database(process.env.COSMOS_DATABASE || 'orders-db')
  .container(process.env.COSMOS_CONTAINER || 'orders');

// ── Service Bus output binding ────────────────────────────────────────────────
const serviceBusOutput = output.serviceBusQueue({
  queueName: 'orders-queue',
  connection: 'ServiceBusConnection',
});

// ── 1. Create Order (HTTP → Service Bus) ──────────────────────────────────────
app.http('createOrder', {
  methods: ['POST'],
  authLevel: 'function',
  route: 'orders',
  return: serviceBusOutput,
  handler: async (request, context) => {
    context.log('CreateOrder triggered');

    let body;
    try {
      body = await request.json();
    } catch {
      return { status: 400, jsonBody: { error: 'Invalid JSON body' } };
    }

    // Validate
    const { productId, quantity, userId } = body;
    if (!productId || !quantity || !userId) {
      return {
        status: 422,
        jsonBody: { error: 'productId, quantity, and userId are required' },
      };
    }
    if (quantity <= 0 || quantity > 100) {
      return { status: 422, jsonBody: { error: 'quantity must be 1-100' } };
    }

    const order = {
      id:         `order-${Date.now()}-${Math.random().toString(36).slice(2)}`,
      productId,
      quantity:   parseInt(quantity),
      userId,
      status:     'pending',
      createdAt:  new Date().toISOString(),
    };

    // Track custom event
    context.log('Order created', { orderId: order.id, userId });

    // Return order ID to client, send to Service Bus for processing
    return {
      status: 202,
      jsonBody: { orderId: order.id, status: 'pending', message: 'Order queued for processing' },
      // This goes to Service Bus via output binding
      value: JSON.stringify(order),
    };
  },
});

// ── 2. Process Order (Service Bus → Cosmos DB) ────────────────────────────────
app.serviceBusQueue('processOrder', {
  queueName: 'orders-queue',
  connection: 'ServiceBusConnection',
  handler: async (message, context) => {
    context.log('ProcessOrder triggered');

    let order;
    try {
      order = typeof message === 'string' ? JSON.parse(message) : message;
    } catch (err) {
      context.log.error('Failed to parse message:', err);
      throw err; // Dead-letter the message
    }

    try {
      // Simulate processing (inventory check, payment, etc.)
      await simulateInventoryCheck(order.productId, order.quantity);
      await simulatePaymentProcessing(order.userId, order.quantity * 9.99);

      // Save to Cosmos DB
      const processedOrder = {
        ...order,
        status:      'completed',
        processedAt: new Date().toISOString(),
        total:       order.quantity * 9.99,
      };

      await container.items.upsert(processedOrder);
      context.log('Order processed successfully', { orderId: order.id });

    } catch (err) {
      // Save failed order
      await container.items.upsert({
        ...order,
        status:    'failed',
        error:     err.message,
        failedAt:  new Date().toISOString(),
      });
      context.log.error('Order processing failed', { orderId: order.id, error: err.message });
      throw err; // Retry or dead-letter
    }
  },
});

// ── 3. Get Order (HTTP → Cosmos DB) ──────────────────────────────────────────
app.http('getOrder', {
  methods: ['GET'],
  authLevel: 'function',
  route: 'orders/{orderId}',
  handler: async (request, context) => {
    const { orderId } = request.params;

    try {
      const { resource: order } = await container.item(orderId, orderId).read();
      if (!order) {
        return { status: 404, jsonBody: { error: 'Order not found' } };
      }
      return { status: 200, jsonBody: order };
    } catch (err) {
      if (err.code === 404) {
        return { status: 404, jsonBody: { error: 'Order not found' } };
      }
      context.log.error('Error fetching order:', err);
      return { status: 500, jsonBody: { error: 'Internal server error' } };
    }
  },
});

// ── 4. List Orders (HTTP → Cosmos DB) ────────────────────────────────────────
app.http('listOrders', {
  methods: ['GET'],
  authLevel: 'function',
  route: 'orders',
  handler: async (request, context) => {
    const userId = request.query.get('userId');
    const status = request.query.get('status');
    const limit  = parseInt(request.query.get('limit') || '20');

    let query = 'SELECT * FROM c WHERE 1=1';
    const parameters = [];

    if (userId) {
      query += ' AND c.userId = @userId';
      parameters.push({ name: '@userId', value: userId });
    }
    if (status) {
      query += ' AND c.status = @status';
      parameters.push({ name: '@status', value: status });
    }
    query += ' ORDER BY c.createdAt DESC OFFSET 0 LIMIT @limit';
    parameters.push({ name: '@limit', value: limit });

    const { resources: orders } = await container.items
      .query({ query, parameters })
      .fetchAll();

    return { status: 200, jsonBody: { orders, count: orders.length } };
  },
});

// ── 5. Upload File (HTTP → Blob Storage) ─────────────────────────────────────
app.http('uploadFile', {
  methods: ['POST'],
  authLevel: 'function',
  route: 'files',
  handler: async (request, context) => {
    const contentType = request.headers.get('content-type') || '';
    if (!contentType.includes('multipart/form-data') && !contentType.includes('application/octet-stream')) {
      return { status: 400, jsonBody: { error: 'Expected multipart/form-data or octet-stream' } };
    }

    const blobClient = new BlobServiceClient(
      `https://${process.env.STORAGE_ACCOUNT_NAME}.blob.core.windows.net`,
      new DefaultAzureCredential()
    );
    const containerClient = blobClient.getContainerClient('uploads');

    const fileName = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    const blockBlobClient = containerClient.getBlockBlobClient(fileName);

    const buffer = Buffer.from(await request.arrayBuffer());
    await blockBlobClient.upload(buffer, buffer.length, {
      blobHTTPHeaders: { blobContentType: contentType },
    });

    return {
      status: 201,
      jsonBody: {
        fileName,
        url: blockBlobClient.url,
        size: buffer.length,
      },
    };
  },
});

// ── 6. Daily Cleanup (Timer) ──────────────────────────────────────────────────
app.timer('dailyCleanup', {
  schedule: '0 0 2 * * *',  // 2 AM daily
  handler: async (myTimer, context) => {
    context.log('Daily cleanup started');

    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - 90);

    const { resources: oldOrders } = await container.items
      .query({
        query: 'SELECT c.id FROM c WHERE c.status = "completed" AND c.createdAt < @cutoff',
        parameters: [{ name: '@cutoff', value: cutoffDate.toISOString() }],
      })
      .fetchAll();

    let archived = 0;
    for (const order of oldOrders) {
      await container.item(order.id, order.id).patch([
        { op: 'add', path: '/archived', value: true },
        { op: 'add', path: '/archivedAt', value: new Date().toISOString() },
      ]);
      archived++;
    }

    context.log(`Cleanup complete: archived ${archived} orders`);
  },
});

// ── 7. Cosmos DB Change Feed ──────────────────────────────────────────────────
app.cosmosDB('orderChangeFeed', {
  databaseName: process.env.COSMOS_DATABASE || 'orders-db',
  containerName: process.env.COSMOS_CONTAINER || 'orders',
  connection: 'CosmosDBConnection',
  leaseContainerName: 'leases',
  createLeaseContainerIfNotExists: true,
  handler: async (documents, context) => {
    for (const doc of documents) {
      if (doc.status === 'completed') {
        context.log('Order completed, sending notification', { orderId: doc.id });
        // Send notification, update analytics, etc.
      }
    }
  },
});

// ── Helpers ───────────────────────────────────────────────────────────────────
async function simulateInventoryCheck(productId, quantity) {
  await new Promise(r => setTimeout(r, 50));
  if (Math.random() < 0.02) throw new Error('Insufficient inventory');
}

async function simulatePaymentProcessing(userId, amount) {
  await new Promise(r => setTimeout(r, 100));
  if (Math.random() < 0.01) throw new Error('Payment declined');
}

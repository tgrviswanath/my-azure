/**
 * Azure Function — Order Management
 * Triggers: HTTP (create/get order), Service Bus (process order), Timer (cleanup)
 */

const { app } = require('@azure/functions');
const { CosmosClient } = require('@azure/cosmos');
const { ServiceBusClient } = require('@azure/service-bus');
const { DefaultAzureCredential } = require('@azure/identity');
const { SecretClient } = require('@azure/keyvault-secrets');
const { v4: uuidv4 } = require('uuid');

// ── Clients (initialized once, reused across warm invocations) ────────────────
const credential = new DefaultAzureCredential();

const cosmosClient = new CosmosClient({
    endpoint: process.env.COSMOS_ENDPOINT,
    aadCredentials: credential
});

const database = cosmosClient.database(process.env.COSMOS_DATABASE || 'orders-db');
const container = database.container('orders');

const sbClient = new ServiceBusClient(
    process.env.SERVICE_BUS_NAMESPACE,
    credential
);

// ── POST /api/orders — Create Order ──────────────────────────────────────────
app.http('createOrder', {
    methods: ['POST'],
    authLevel: 'anonymous',
    route: 'orders',
    handler: async (request, context) => {
        context.log('CreateOrder triggered');

        try {
            // Parse and validate body
            const body = await request.json();

            if (!body.customerId || !body.items || !Array.isArray(body.items) || body.items.length === 0) {
                return {
                    status: 400,
                    jsonBody: { error: 'customerId and items[] are required' }
                };
            }

            // Build order document
            const orderId = uuidv4();
            const now = new Date().toISOString();
            const total = body.items.reduce((sum, item) => sum + (item.price * item.quantity), 0);

            const order = {
                id: orderId,
                customerId: body.customerId,
                items: body.items,
                total: Math.round(total * 100) / 100,
                status: 'PENDING',
                createdAt: now,
                updatedAt: now,
                _partitionKey: body.customerId
            };

            // Save to Cosmos DB
            const { resource } = await container.items.create(order);
            context.log(`Order created: ${orderId}`);

            // Queue for async processing
            const sender = sbClient.createSender(process.env.SERVICE_BUS_QUEUE || 'orders');
            await sender.sendMessages({
                body: { orderId, customerId: body.customerId },
                messageId: orderId,
                contentType: 'application/json'
            });
            await sender.close();

            return {
                status: 201,
                headers: { 'Content-Type': 'application/json' },
                jsonBody: { orderId, status: 'PENDING', total: order.total }
            };

        } catch (error) {
            context.log.error('CreateOrder error:', error.message);
            return {
                status: 500,
                jsonBody: { error: 'Internal server error' }
            };
        }
    }
});

// ── GET /api/orders/{orderId} — Get Order ─────────────────────────────────────
app.http('getOrder', {
    methods: ['GET'],
    authLevel: 'anonymous',
    route: 'orders/{orderId}',
    handler: async (request, context) => {
        const orderId = request.params.orderId;
        const customerId = request.query.get('customerId');

        if (!customerId) {
            return { status: 400, jsonBody: { error: 'customerId query param required' } };
        }

        try {
            const { resource } = await container.item(orderId, customerId).read();

            if (!resource) {
                return { status: 404, jsonBody: { error: 'Order not found' } };
            }

            return { status: 200, jsonBody: resource };

        } catch (error) {
            if (error.code === 404) {
                return { status: 404, jsonBody: { error: 'Order not found' } };
            }
            context.log.error('GetOrder error:', error.message);
            return { status: 500, jsonBody: { error: 'Internal server error' } };
        }
    }
});

// ── GET /api/orders — List Orders for Customer ────────────────────────────────
app.http('listOrders', {
    methods: ['GET'],
    authLevel: 'anonymous',
    route: 'orders',
    handler: async (request, context) => {
        const customerId = request.query.get('customerId');
        const status = request.query.get('status');
        const limit = parseInt(request.query.get('limit') || '20');

        if (!customerId) {
            return { status: 400, jsonBody: { error: 'customerId query param required' } };
        }

        try {
            let query = `SELECT * FROM c WHERE c.customerId = @customerId`;
            const parameters = [{ name: '@customerId', value: customerId }];

            if (status) {
                query += ` AND c.status = @status`;
                parameters.push({ name: '@status', value: status });
            }

            query += ` ORDER BY c.createdAt DESC OFFSET 0 LIMIT @limit`;
            parameters.push({ name: '@limit', value: limit });

            const { resources } = await container.items.query({
                query,
                parameters
            }).fetchAll();

            return {
                status: 200,
                jsonBody: { orders: resources, count: resources.length }
            };

        } catch (error) {
            context.log.error('ListOrders error:', error.message);
            return { status: 500, jsonBody: { error: 'Internal server error' } };
        }
    }
});

// ── Service Bus Trigger — Process Order ───────────────────────────────────────
app.serviceBusQueue('processOrder', {
    queueName: 'orders',
    connection: 'SERVICE_BUS_CONNECTION',
    handler: async (message, context) => {
        const { orderId, customerId } = message;
        context.log(`Processing order: ${orderId}`);

        try {
            // Read current order
            const { resource: order } = await container.item(orderId, customerId).read();

            if (!order) {
                context.log.error(`Order not found: ${orderId}`);
                return; // Don't retry — order doesn't exist
            }

            // Simulate processing (inventory check, payment, etc.)
            await simulateInventoryCheck(order.items);
            await simulatePaymentProcessing(order.total, customerId);

            // Update status
            await container.item(orderId, customerId).replace({
                ...order,
                status: 'CONFIRMED',
                updatedAt: new Date().toISOString(),
                processedAt: new Date().toISOString()
            });

            context.log(`Order confirmed: ${orderId}`);

        } catch (error) {
            context.log.error(`ProcessOrder failed for ${orderId}:`, error.message);
            throw error; // Rethrow to trigger Service Bus retry / DLQ
        }
    }
});

// ── Timer Trigger — Daily Cleanup ─────────────────────────────────────────────
app.timer('dailyCleanup', {
    schedule: '0 0 2 * * *', // 2 AM daily
    handler: async (timer, context) => {
        context.log('Daily cleanup started');

        const cutoffDate = new Date();
        cutoffDate.setDate(cutoffDate.getDate() - 90); // 90 days ago

        try {
            const { resources: oldOrders } = await container.items.query({
                query: `SELECT c.id, c._partitionKey FROM c 
                        WHERE c.status IN ('DELIVERED', 'CANCELLED') 
                        AND c.updatedAt < @cutoff`,
                parameters: [{ name: '@cutoff', value: cutoffDate.toISOString() }]
            }).fetchAll();

            let deleted = 0;
            for (const order of oldOrders) {
                await container.item(order.id, order._partitionKey).delete();
                deleted++;
            }

            context.log(`Cleanup complete: deleted ${deleted} old orders`);

        } catch (error) {
            context.log.error('Cleanup error:', error.message);
            throw error;
        }
    }
});

// ── Cosmos DB Change Feed — React to Changes ──────────────────────────────────
app.cosmosDB('orderChangeFeed', {
    databaseName: process.env.COSMOS_DATABASE || 'orders-db',
    containerName: 'orders',
    leaseContainerName: 'leases',
    connection: 'COSMOS_CONNECTION',
    handler: async (documents, context) => {
        context.log(`Change feed: ${documents.length} documents changed`);

        for (const doc of documents) {
            if (doc.status === 'CONFIRMED') {
                // Send confirmation notification
                context.log(`Order confirmed, sending notification: ${doc.id}`);
                await sendNotification(doc.customerId, doc.id, doc.total);
            }
        }
    }
});

// ── Helper Functions ──────────────────────────────────────────────────────────
async function simulateInventoryCheck(items) {
    // In production: call inventory service
    await new Promise(resolve => setTimeout(resolve, 100));
    return true;
}

async function simulatePaymentProcessing(amount, customerId) {
    // In production: call payment service
    await new Promise(resolve => setTimeout(resolve, 200));
    return { transactionId: uuidv4() };
}

async function sendNotification(customerId, orderId, total) {
    // In production: send email/SMS via Communication Services
    console.log(`Notification: Customer ${customerId}, Order ${orderId}, Total $${total}`);
}

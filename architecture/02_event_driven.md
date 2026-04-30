# Event-Driven Architecture on Azure

## Event-Driven Patterns

```
Event-Driven Architecture = components communicate via events
├── Producer: emits events (doesn't know consumers)
├── Event Broker: routes events (Service Bus, Event Grid, Event Hubs)
└── Consumer: reacts to events (Functions, Logic Apps, services)

Benefits:
  Loose coupling:    producers/consumers independent
  Scalability:       consumers scale independently
  Resilience:        failures isolated, retry built-in
  Auditability:      event log = audit trail
```

## Azure Messaging Services Comparison

```
Service Bus (Enterprise Messaging)
├── Queues: point-to-point, guaranteed delivery, FIFO
├── Topics: publish-subscribe, multiple subscribers
├── Features: dead-letter, sessions, transactions, duplicate detection
├── Max message size: 256KB (Standard), 100MB (Premium)
├── Retention: up to 14 days
└── Use for: order processing, financial transactions, workflows

Event Grid (Event Routing)
├── Push-based, serverless
├── Sources: Azure services, custom topics, partner events
├── Handlers: Functions, Logic Apps, webhooks, Service Bus
├── Retry: up to 24 hours with exponential backoff
├── Filtering: event type, subject prefix/suffix
└── Use for: reacting to Azure resource changes, serverless triggers

Event Hubs (Streaming)
├── High-throughput: millions of events/second
├── Kafka-compatible endpoint
├── Consumer groups: multiple independent readers
├── Retention: 1-7 days (Standard), up to 90 days (Premium)
├── Capture: auto-save to ADLS/Blob
└── Use for: telemetry, logs, IoT, analytics pipelines
```

## Service Bus — Deep Dive

```bash
# Create Service Bus namespace
az servicebus namespace create \
  --name sbns-myapp-prod \
  --resource-group $RG \
  --location $LOCATION \
  --sku Premium \
  --capacity 1 \
  --zone-redundant true

# Create queue with dead-letter
az servicebus queue create \
  --name orders \
  --namespace-name sbns-myapp-prod \
  --resource-group $RG \
  --max-size 5120 \
  --default-message-time-to-live P14D \
  --dead-lettering-on-message-expiration true \
  --enable-duplicate-detection true \
  --duplicate-detection-history-time-window PT10M \
  --lock-duration PT5M \
  --max-delivery-count 10

# Create topic + subscriptions
az servicebus topic create \
  --name order-events \
  --namespace-name sbns-myapp-prod \
  --resource-group $RG

az servicebus topic subscription create \
  --name inventory-sub \
  --topic-name order-events \
  --namespace-name sbns-myapp-prod \
  --resource-group $RG \
  --dead-letter-on-filter-evaluation-exceptions true \
  --max-delivery-count 10

# Add filter to subscription
az servicebus topic subscription rule create \
  --name high-value-orders \
  --subscription-name inventory-sub \
  --topic-name order-events \
  --namespace-name sbns-myapp-prod \
  --resource-group $RG \
  --filter-sql-expression "amount > 1000"
```

```javascript
// Service Bus — Producer (Node.js)
const { ServiceBusClient } = require('@azure/service-bus');
const { DefaultAzureCredential } = require('@azure/identity');

const client = new ServiceBusClient(
  'sbns-myapp-prod.servicebus.windows.net',
  new DefaultAzureCredential()
);

async function sendOrder(order) {
  const sender = client.createSender('orders');
  try {
    await sender.sendMessages({
      body: order,
      contentType: 'application/json',
      subject: 'OrderCreated',
      messageId: order.id,
      sessionId: order.customerId,  // for ordered processing per customer
      applicationProperties: {
        orderType: order.type,
        amount: order.total,
        region: order.region,
      },
    });
    console.log(`Order ${order.id} sent to Service Bus`);
  } finally {
    await sender.close();
  }
}

// Service Bus — Consumer with error handling
async function processOrders() {
  const receiver = client.createReceiver('orders', {
    receiveMode: 'peekLock',  // don't delete until processed
  });

  receiver.subscribe({
    processMessage: async (message) => {
      const order = message.body;
      try {
        await processOrder(order);
        await receiver.completeMessage(message);  // remove from queue
      } catch (err) {
        if (isRetryable(err) && message.deliveryCount < 10) {
          await receiver.abandonMessage(message);  // return to queue
        } else {
          await receiver.deadLetterMessage(message, {
            deadLetterReason: 'ProcessingFailed',
            deadLetterErrorDescription: err.message,
          });
        }
      }
    },
    processError: async (err) => {
      console.error('Service Bus error:', err);
    },
  });
}
```

## Event Grid — Deep Dive

```bash
# Create custom topic
az eventgrid topic create \
  --name egt-myapp-prod \
  --resource-group $RG \
  --location $LOCATION \
  --input-schema CloudEventSchemaV1_0

# Subscribe Azure Function to topic
az eventgrid event-subscription create \
  --name sub-process-orders \
  --source-resource-id $TOPIC_ID \
  --endpoint $FUNCTION_URL \
  --endpoint-type webhook \
  --included-event-types OrderCreated OrderUpdated \
  --subject-begins-with /orders/ \
  --deadletter-endpoint $STORAGE_BLOB_ID \
  --max-delivery-attempts 30 \
  --event-ttl 1440

# Subscribe to Azure resource events (e.g., blob created)
az eventgrid event-subscription create \
  --name sub-blob-created \
  --source-resource-id $STORAGE_ACCOUNT_ID \
  --endpoint $FUNCTION_URL \
  --endpoint-type webhook \
  --included-event-types Microsoft.Storage.BlobCreated \
  --subject-begins-with /blobServices/default/containers/uploads/
```

```javascript
// Event Grid — Publish event
const { EventGridPublisherClient, CloudEvent } = require('@azure/eventgrid');
const { DefaultAzureCredential } = require('@azure/identity');

const client = new EventGridPublisherClient(
  'https://egt-myapp-prod.eastus-1.eventgrid.azure.net/api/events',
  'CloudEvent',
  new DefaultAzureCredential()
);

await client.send([
  new CloudEvent({
    type: 'com.myapp.order.created',
    source: '/orders/service',
    id: order.id,
    data: {
      orderId: order.id,
      customerId: order.customerId,
      amount: order.total,
      items: order.items,
    },
    datacontenttype: 'application/json',
    subject: `/orders/${order.id}`,
  })
]);

// Event Grid — Receive (Azure Function)
app.http('eventGridHandler', {
  methods: ['POST'],
  authLevel: 'anonymous',
  handler: async (request, context) => {
    const events = await request.json();

    // Handle validation handshake
    if (Array.isArray(events) && events[0]?.eventType === 'Microsoft.EventGrid.SubscriptionValidationEvent') {
      return {
        status: 200,
        jsonBody: { validationResponse: events[0].data.validationCode }
      };
    }

    for (const event of events) {
      context.log('Processing event:', event.type, event.subject);
      await handleEvent(event);
    }
    return { status: 200 };
  }
});
```

## Event Hubs — Deep Dive

```bash
# Create Event Hubs namespace
az eventhubs namespace create \
  --name evhns-telemetry-prod \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard \
  --capacity 4 \
  --enable-kafka true \
  --zone-redundant true

# Create Event Hub
az eventhubs eventhub create \
  --name telemetry \
  --namespace-name evhns-telemetry-prod \
  --resource-group $RG \
  --partition-count 8 \
  --message-retention 7 \
  --enable-capture true \
  --capture-interval 300 \
  --capture-size-limit 314572800 \
  --destination-name EventHubArchive.AzureBlockBlob \
  --storage-account $STORAGE_ID \
  --blob-container telemetry-archive \
  --archive-name-format "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
```

```javascript
// Event Hubs — Producer
const { EventHubProducerClient } = require('@azure/event-hubs');
const { DefaultAzureCredential } = require('@azure/identity');

const producer = new EventHubProducerClient(
  'evhns-telemetry-prod.servicebus.windows.net',
  'telemetry',
  new DefaultAzureCredential()
);

// Send batch (efficient)
async function sendTelemetry(events) {
  const batch = await producer.createBatch({
    partitionKey: events[0].deviceId,  // same device → same partition → ordered
  });

  for (const event of events) {
    if (!batch.tryAdd({ body: event })) {
      await producer.sendBatch(batch);
      batch = await producer.createBatch({ partitionKey: events[0].deviceId });
      batch.tryAdd({ body: event });
    }
  }
  await producer.sendBatch(batch);
}

// Event Hubs — Consumer with checkpointing
const { EventHubConsumerClient, earliestEventPosition } = require('@azure/event-hubs');
const { BlobCheckpointStore } = require('@azure/eventhubs-checkpointstore-blob');

const checkpointStore = new BlobCheckpointStore(containerClient);
const consumer = new EventHubConsumerClient(
  '$Default',
  'evhns-telemetry-prod.servicebus.windows.net',
  'telemetry',
  new DefaultAzureCredential(),
  checkpointStore
);

consumer.subscribe({
  processEvents: async (events, context) => {
    for (const event of events) {
      await processEvent(event.body);
    }
    // Checkpoint after processing batch
    await context.updateCheckpoint(events[events.length - 1]);
  },
  processError: async (err, context) => {
    console.error('Consumer error:', err);
  },
}, { startPosition: earliestEventPosition });
```

## Interview Questions

### Q1: When would you use Service Bus vs Event Grid vs Event Hubs?
**Answer:**
- **Service Bus**: Reliable message delivery, guaranteed ordering, dead-letter queue, transactions. Use for: order processing, financial transactions, command patterns where every message must be processed exactly once.
- **Event Grid**: Event routing, push-based, serverless triggers. Use for: reacting to Azure resource changes (blob created, VM started), webhook notifications, event-driven automation.
- **Event Hubs**: High-throughput streaming (millions/sec), Kafka-compatible, time-series. Use for: IoT telemetry, application logs, clickstream analytics, real-time dashboards.

### Q2: What is the difference between a queue and a topic in Service Bus?
**Answer:**
- **Queue**: Point-to-point. One sender, one receiver. Message consumed by one consumer. Use for: task distribution, load leveling.
- **Topic**: Publish-subscribe. One sender, multiple subscribers. Each subscription gets a copy. Supports filters. Use for: broadcasting events to multiple services.

### Q3: How do you handle poison messages in Service Bus?
**Answer:**
Poison messages are messages that repeatedly fail processing. Service Bus handles via:
1. **Max delivery count**: after N failed attempts, message moved to dead-letter queue
2. **Dead-letter queue**: separate queue for failed messages
3. **Monitor DLQ**: alert when DLQ has messages
4. **Process DLQ**: separate consumer to analyze and handle failed messages
5. **Retry policy**: exponential backoff before abandoning

### Q4: What is Event Grid's retry policy?
**Answer:**
Event Grid retries delivery for up to 24 hours with exponential backoff (10 seconds → 30 seconds → 1 minute → ... → 10 minutes max). After 24 hours or 30 attempts, event is dead-lettered (if configured) or dropped. Configure dead-letter endpoint (Storage Blob) to capture undelivered events.

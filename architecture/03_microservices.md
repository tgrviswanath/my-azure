# Microservices Architecture on Azure

## Microservices Patterns

```
Microservices = independently deployable services, each owning its data

Key Principles:
  Single Responsibility:  Each service does one thing well
  Loose Coupling:         Services communicate via APIs/events
  High Cohesion:          Related functionality in same service
  Own Data:               Each service has its own database
  Independent Deploy:     Deploy without coordinating with others
  Failure Isolation:      One service failure doesn't cascade

Azure Services for Microservices:
  Compute:      AKS, Azure Container Apps, App Service
  API Gateway:  Azure API Management
  Messaging:    Service Bus, Event Grid, Event Hubs
  Config:       Azure App Configuration
  Secrets:      Key Vault
  Discovery:    AKS DNS, Container Apps environments
  Tracing:      Application Insights (distributed tracing)
  Mesh:         Dapr, Istio on AKS
```

## API Management (APIM)

```bash
# Create APIM instance
az apim create \
  --name apim-myapp-prod \
  --resource-group $RG \
  --location $LOCATION \
  --publisher-email "admin@company.com" \
  --publisher-name "My Company" \
  --sku-name Premium \
  --sku-capacity 1 \
  --virtual-network External \
  --enable-managed-identity true

# Import API from OpenAPI spec
az apim api import \
  --resource-group $RG \
  --service-name apim-myapp-prod \
  --api-id orders-api \
  --path /orders \
  --specification-format OpenApi \
  --specification-url https://raw.githubusercontent.com/user/repo/main/openapi.yaml \
  --display-name "Orders API" \
  --protocols https

# Add rate limiting policy
az apim api policy create \
  --resource-group $RG \
  --service-name apim-myapp-prod \
  --api-id orders-api \
  --xml-policy '<policies>
    <inbound>
      <rate-limit calls="100" renewal-period="60" />
      <quota calls="10000" renewal-period="86400" />
      <validate-jwt header-name="Authorization" failed-validation-httpcode="401">
        <openid-config url="https://login.microsoftonline.com/{tenant}/.well-known/openid-configuration" />
        <required-claims>
          <claim name="aud"><value>api://myapp</value></claim>
        </required-claims>
      </validate-jwt>
      <set-header name="X-Request-ID" exists-action="skip">
        <value>@(context.RequestId.ToString())</value>
      </set-header>
    </inbound>
    <backend>
      <forward-request />
    </backend>
    <outbound>
      <set-header name="X-Powered-By" exists-action="delete" />
    </outbound>
    <on-error>
      <return-response>
        <set-status code="500" reason="Internal Server Error" />
        <set-body>{"error": "An unexpected error occurred"}</set-body>
      </return-response>
    </on-error>
  </policies>'
```

## Azure Container Apps

```bash
# Create Container Apps environment
az containerapp env create \
  --name cae-myapp-prod \
  --resource-group $RG \
  --location $LOCATION \
  --logs-workspace-id $LAW_ID \
  --infrastructure-subnet-resource-id $SUBNET_ID

# Deploy microservice
az containerapp create \
  --name order-service \
  --resource-group $RG \
  --environment cae-myapp-prod \
  --image myregistry.azurecr.io/order-service:v1.0.0 \
  --registry-server myregistry.azurecr.io \
  --registry-identity system \
  --target-port 3001 \
  --ingress external \
  --min-replicas 2 \
  --max-replicas 20 \
  --cpu 0.5 \
  --memory 1.0Gi \
  --env-vars \
    NODE_ENV=production \
    "DATABASE_URL=secretref:database-url" \
  --secrets "database-url=keyvaultref:${KV_URI}/secrets/DatabaseUrl,identityref:system" \
  --scale-rule-name http-rule \
  --scale-rule-type http \
  --scale-rule-http-concurrency 100

# Dapr integration
az containerapp update \
  --name order-service \
  --resource-group $RG \
  --enable-dapr true \
  --dapr-app-id order-service \
  --dapr-app-port 3001 \
  --dapr-app-protocol http
```

## Dapr on AKS

```yaml
# dapr-components.yaml — Service Bus pub/sub
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: pubsub
  namespace: production
spec:
  type: pubsub.azure.servicebus.topics
  version: v1
  metadata:
  - name: connectionString
    secretKeyRef:
      name: servicebus-secret
      key: connectionString
  - name: maxConcurrentHandlers
    value: "10"
---
# State store (Redis)
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
  namespace: production
spec:
  type: state.redis
  version: v1
  metadata:
  - name: redisHost
    value: "redis-cache.redis.cache.windows.net:6380"
  - name: redisPassword
    secretKeyRef:
      name: redis-secret
      key: password
  - name: enableTLS
    value: "true"
```

```javascript
// Dapr service invocation (no service discovery needed)
const { DaprClient } = require('@dapr/dapr');
const client = new DaprClient();

// Call another service
const result = await client.invoker.invoke(
  'product-service',    // app-id
  'products/123',       // method
  HttpMethod.GET
);

// Publish event
await client.pubsub.publish('pubsub', 'order-created', {
  orderId: order.id,
  customerId: order.customerId,
  amount: order.total,
});

// Subscribe to events
const server = new DaprServer();
await server.pubsub.subscribe('pubsub', 'order-created', async (data) => {
  console.log('Order created:', data);
  await processOrder(data);
});
```

## Circuit Breaker Pattern

```javascript
// Circuit breaker with exponential backoff
class CircuitBreaker {
  constructor(options = {}) {
    this.failureThreshold  = options.failureThreshold  || 5;
    this.successThreshold  = options.successThreshold  || 2;
    this.timeout           = options.timeout           || 60000; // 1 min
    this.state             = 'CLOSED';
    this.failureCount      = 0;
    this.successCount      = 0;
    this.lastFailureTime   = null;
  }

  async call(fn) {
    if (this.state === 'OPEN') {
      if (Date.now() - this.lastFailureTime > this.timeout) {
        this.state = 'HALF_OPEN';
      } else {
        throw new Error('Circuit breaker is OPEN');
      }
    }

    try {
      const result = await fn();
      this.onSuccess();
      return result;
    } catch (err) {
      this.onFailure();
      throw err;
    }
  }

  onSuccess() {
    this.failureCount = 0;
    if (this.state === 'HALF_OPEN') {
      this.successCount++;
      if (this.successCount >= this.successThreshold) {
        this.state = 'CLOSED';
        this.successCount = 0;
      }
    }
  }

  onFailure() {
    this.failureCount++;
    this.lastFailureTime = Date.now();
    if (this.failureCount >= this.failureThreshold) {
      this.state = 'OPEN';
    }
  }
}

// Usage
const breaker = new CircuitBreaker({ failureThreshold: 3, timeout: 30000 });

async function callProductService(productId) {
  return breaker.call(() =>
    fetch(`http://product-service/products/${productId}`).then(r => r.json())
  );
}
```

## Saga Pattern (Distributed Transactions)

```javascript
// Choreography-based saga using Service Bus
// Each service publishes events, others react

// Order Service
async function createOrder(orderData) {
  const order = await db.orders.create({ ...orderData, status: 'pending' });

  // Publish event — inventory service will react
  await serviceBus.publish('order-created', {
    orderId: order.id,
    items: order.items,
    customerId: order.customerId,
  });

  return order;
}

// Inventory Service — reacts to order-created
serviceBus.subscribe('order-created', async (event) => {
  try {
    await reserveInventory(event.items);
    await serviceBus.publish('inventory-reserved', { orderId: event.orderId });
  } catch (err) {
    // Compensating transaction
    await serviceBus.publish('inventory-reservation-failed', {
      orderId: event.orderId,
      reason: err.message,
    });
  }
});

// Order Service — reacts to inventory-reservation-failed
serviceBus.subscribe('inventory-reservation-failed', async (event) => {
  await db.orders.update(event.orderId, { status: 'cancelled' });
  await serviceBus.publish('order-cancelled', { orderId: event.orderId });
});
```

## Interview Questions

### Q1: What is the difference between microservices and monolith?
**Answer:**
- **Monolith**: Single deployable unit. Simple to develop initially, hard to scale independently, one failure can affect all. Good for: small teams, simple domains.
- **Microservices**: Independent services, each with own data. Scale independently, technology flexibility, complex operations. Good for: large teams, complex domains, different scaling needs.
- **Key trade-off**: Microservices add distributed systems complexity (network failures, eventual consistency, distributed tracing).

### Q2: How do you handle distributed transactions in microservices?
**Answer:**
Avoid distributed transactions when possible. Patterns:
1. **Saga**: sequence of local transactions with compensating transactions on failure
   - Choreography: services react to events (loose coupling)
   - Orchestration: central coordinator (Durable Functions)
2. **Outbox pattern**: write event to DB in same transaction, then publish
3. **Two-phase commit**: avoid — too complex, poor availability
4. **Eventual consistency**: accept that data will be consistent eventually

### Q3: What is Azure API Management and what problems does it solve?
**Answer:**
APIM is an API gateway that sits in front of backend services. Solves:
- **Security**: JWT validation, OAuth, API keys, IP filtering
- **Rate limiting**: protect backends from overload
- **Transformation**: modify requests/responses without changing backends
- **Versioning**: manage multiple API versions
- **Analytics**: usage metrics, developer portal
- **Caching**: reduce backend load
- **Routing**: route to different backends based on rules

### Q4: What is Dapr and why use it with microservices?
**Answer:**
Dapr (Distributed Application Runtime) is a portable, event-driven runtime for microservices. Provides building blocks: service invocation, pub/sub, state management, secrets, bindings, actors. Benefits:
- Language-agnostic (sidecar pattern)
- Abstracts infrastructure (swap Redis for Cosmos DB without code changes)
- Built-in retry, circuit breaking, distributed tracing
- Works on AKS, Container Apps, local development

# Steps — Project 4.5 Service Bus Microservices

## Phase 1 — Deploy
```bash
cd terraform && terraform init && terraform apply -auto-approve
export SERVICE_BUS_CONNECTION_STRING=$(terraform output -raw service_bus_connection_string)
```

## Phase 2 — Publish Orders
```bash
pip install azure-servicebus
python src/order_publisher.py
```

## Phase 3 — Monitor
```bash
# Check queue depth
az servicebus queue show \
  --resource-group rg-service-bus \
  --namespace-name sb-microservices-001 \
  --name orders \
  --query "countDetails"
```

## Screenshots to Take
- [ ] Orders published to queue
- [ ] Function processing messages
- [ ] Dead-letter queue handling failed messages

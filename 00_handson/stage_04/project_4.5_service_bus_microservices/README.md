# Project 4.5 — Service Bus Microservices

## What This Does
Async order processing using Azure Service Bus queues with dead-letter queue handling.

## Flow
```
Order API → Service Bus Queue → Order Processor Function → DB
                             ↓ (on failure)
                         Dead-Letter Queue → Alert Function
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve
python src/order_publisher.py
```

## Lessons Learned
- Service Bus guarantees at-least-once delivery
- Dead-letter queue captures messages that fail after max retries
- Use sessions for ordered processing (FIFO per session)
- Peek-lock mode: message locked during processing, deleted on success

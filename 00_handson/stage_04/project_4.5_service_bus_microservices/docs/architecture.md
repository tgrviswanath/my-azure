# Architecture — Project 4.5 Service Bus Microservices

## Flow

```
Order API
  │  publish message
  ▼
Service Bus Queue: orders
  │  max_delivery_count = 3
  │  lock_duration = 1 min
  ▼
Azure Function: process_order
  ├── Success → message deleted from queue
  └── Failure (3x) → message moved to dead-letter queue
                          │
                          ▼
                    Azure Function: handle_dead_letter
                          └── Alert / manual review
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Peek-lock | Message locked during processing, deleted on success |
| Dead-letter queue | Holds messages that failed max_delivery_count times |
| max_delivery_count | Number of retries before dead-lettering |
| Sessions | FIFO ordering per session ID |
| At-least-once | Service Bus guarantees delivery but may duplicate |

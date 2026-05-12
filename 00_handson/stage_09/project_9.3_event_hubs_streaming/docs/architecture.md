# Architecture — Project 9.3: Azure Event Hubs + Stream Analytics

## ASCII Diagram

```
                    REAL-TIME STREAMING ARCHITECTURE
                    =================================

  PRODUCERS                                              CONSUMERS
  ┌──────────────┐                                      ┌──────────────────┐
  │ Python       │                                      │ Stream Analytics │
  │ Producer     │                                      │ (analytics-cg)   │
  │              │                                      │                  │
  │ order_id     │                                      │ SELECT product,  │
  │ product      │──────────────────────────────────────│   SUM(amount),   │
  │ amount       │                                      │   COUNT(*)       │
  │ customer_id  │                                      │ GROUP BY product,│
  │ event_time   │                                      │ TumblingWindow   │
  └──────────────┘                                      │ (minute, 1)      │
                                                        └────────┬─────────┘
  ┌──────────────┐                                               │
  │ IoT Devices  │                                               ▼
  │ (future)     │──┐                                   ┌──────────────────┐
  └──────────────┘  │                                   │ ADLS Gen2        │
                    │   EVENT HUBS NAMESPACE             │ output/          │
                    │   ┌──────────────────────────┐    │ aggregated/      │
                    │   │                          │    │ 2024/01/15/      │
                    └──▶│  Event Hub: orders-hub   │    │ 14/0_0.json      │
                        │                          │    └──────────────────┘
                        │  Partitions: 4           │
                        │  ┌──┐ ┌──┐ ┌──┐ ┌──┐   │    ┌──────────────────┐
                        │  │P0│ │P1│ │P2│ │P3│   │    │ Your Application │
                        │  └──┘ └──┘ └──┘ └──┘   │    │ (app-cg)         │
                        │                          │    │                  │
                        │  Retention: 1 day        │    │ Real-time        │
                        │  Consumer Groups:        │    │ dashboard        │
                        │  • $Default              │    └──────────────────┘
                        │  • analytics-cg ─────────┘
                        │  • app-cg ────────────────────────────────────────▶
                        └──────────────────────────┘

  PARTITION KEY STRATEGY
  ┌──────────────────────────────────────────────────────────────┐
  │ partition_key = customer_id                                  │
  │                                                              │
  │ customer_id=C001 → always goes to Partition 2               │
  │ customer_id=C002 → always goes to Partition 0               │
  │                                                              │
  │ Benefit: All events for a customer are ordered              │
  │ within their partition                                       │
  └──────────────────────────────────────────────────────────────┘

  STREAM ANALYTICS WINDOWING
  ┌──────────────────────────────────────────────────────────────┐
  │                                                              │
  │  TumblingWindow(minute, 1) — non-overlapping 1-min windows  │
  │  ├──────────────┤├──────────────┤├──────────────┤           │
  │  │  00:00-01:00 ││  01:00-02:00 ││  02:00-03:00 │           │
  │  │  Widget A: 5 ││  Widget A: 3 ││  Widget A: 7 │           │
  │  │  Widget B: 3 ││  Widget B: 8 ││  Widget B: 2 │           │
  │  └──────────────┘└──────────────┘└──────────────┘           │
  │                                                              │
  │  HoppingWindow(minute, 1, 30sec) — overlapping windows      │
  │  ├──────────────┤                                           │
  │  │  00:00-01:00 │                                           │
  │  │       ├──────────────┤                                   │
  │  │       │  00:30-01:30 │                                   │
  │  └───────┘└─────────────┘                                   │
  └──────────────────────────────────────────────────────────────┘
```

## Key Concepts

| Concept | Description | Analogy |
|---|---|---|
| **Event Hub Namespace** | Container for Event Hubs | Kafka cluster |
| **Event Hub** | Partitioned log of events | Kafka topic |
| **Partition** | Ordered, immutable sequence of events | Kafka partition |
| **Consumer Group** | Independent cursor position per consumer | Kafka consumer group |
| **Throughput Unit (TU)** | 1 MB/s ingress, 2 MB/s egress | Kafka broker capacity |
| **Offset** | Position of event within a partition | Kafka offset |
| **Retention** | How long events are kept (1-7 days Standard) | Kafka retention.ms |
| **Streaming Unit (SU)** | Stream Analytics compute unit | Flink parallelism |
| **TumblingWindow** | Non-overlapping fixed-size time window | Batch per minute |
| **HoppingWindow** | Overlapping sliding window | Rolling average |
| **SessionWindow** | Activity-based window (gap timeout) | User session |

## Event Schema

```json
{
  "order_id": "ORD-001",
  "customer_id": "C001",
  "product": "Widget A",
  "amount": 45.99,
  "quantity": 2,
  "status": "pending",
  "region": "us-east",
  "event_time": "2024-01-15T14:30:00.000Z"
}
```

## Stream Analytics Query

```sql
-- Tumbling window: revenue per product per minute
SELECT
    product,
    COUNT(*) AS order_count,
    SUM(CAST(amount AS float)) AS total_revenue,
    AVG(CAST(amount AS float)) AS avg_order_value,
    System.Timestamp() AS window_end
INTO [adls-output]
FROM [orders-input] TIMESTAMP BY event_time
GROUP BY
    product,
    TumblingWindow(Duration(minute, 1))

-- Alert: detect revenue spike (> $1000 in 1 minute)
SELECT
    product,
    SUM(CAST(amount AS float)) AS total_revenue,
    System.Timestamp() AS window_end
INTO [alerts-output]
FROM [orders-input] TIMESTAMP BY event_time
GROUP BY
    product,
    TumblingWindow(Duration(minute, 1))
HAVING SUM(CAST(amount AS float)) > 1000
```

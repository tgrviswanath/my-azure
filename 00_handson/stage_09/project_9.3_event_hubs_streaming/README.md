# Project 9.3 — Real-Time Streaming with Azure Event Hubs + Stream Analytics

## What This Does

Builds a real-time streaming pipeline: a Python producer sends simulated order events to Azure Event Hubs (partitioned, high-throughput message broker), Azure Stream Analytics reads the stream and applies windowed aggregations (tumbling window — total revenue per product per 1-minute window), and outputs results to ADLS Gen2 and optionally Synapse Analytics for dashboarding.

## Services Used

| Service | Purpose | SKU |
|---|---|---|
| Event Hubs Namespace | Message broker namespace | Standard (1 TU) |
| Event Hub | Partitioned event stream (like Kafka topic) | 4 partitions |
| Stream Analytics Job | Real-time SQL-like stream processing | 1 Streaming Unit |
| ADLS Gen2 | Output sink for aggregated results | Standard LRS |
| Azure Monitor | Metrics for Event Hubs (incoming/outgoing messages) | Free |

## Architecture

```
PRODUCER                EVENT HUBS              STREAM ANALYTICS        SINK
┌──────────┐           ┌──────────────────┐    ┌──────────────────┐   ┌──────────┐
│ Python   │──events──▶│ Namespace        │    │ Job              │   │ ADLS     │
│ Producer │           │ ┌──────────────┐ │    │                  │   │ Gen2     │
│          │           │ │ Event Hub    │─┼───▶│ SELECT           │──▶│ output/  │
│ 100 msgs │           │ │ orders-hub   │ │    │   product,       │   │ *.json   │
│ 0.1s     │           │ │ 4 partitions │ │    │   SUM(amount),   │   └──────────┘
│ delay    │           │ └──────────────┘ │    │   COUNT(*)       │
└──────────┘           │                  │    │ GROUP BY         │   ┌──────────┐
                       │ Retention: 1 day │    │   product,       │   │ Synapse  │
                       │ Consumer Groups: │    │   TumblingWindow │──▶│ SQL Pool │
                       │  $Default        │    │   (Duration(     │   │ (opt.)   │
                       │  analytics-cg    │    │    minute, 1))   │   └──────────┘
                       └──────────────────┘    └──────────────────┘
```

## How to Run

### Prerequisites
```bash
az login
export RG="rg-eventhubs-lab"
export LOCATION="eastus"
```

### Deploy
```bash
cd terraform
terraform init
terraform apply -auto-approve

# Install producer dependencies
pip install azure-eventhub azure-identity

# Run producer (sends 100 events)
cd ../code
python producer.py
```

### Expected Output
```
Sending 100 order events to Event Hub...
[001] Sent: order_id=ORD-001 product=Widget A amount=45.99 partition=2 offset=0 seq=0
[002] Sent: order_id=ORD-002 product=Widget B amount=29.99 partition=0 offset=0 seq=0
...
[100] Sent: order_id=ORD-100 product=Widget C amount=89.99 partition=3 offset=96 seq=24

Summary:
  Events sent: 100
  Duration: 10.3s
  Throughput: 9.7 events/sec
  Partitions used: {0: 25, 1: 26, 2: 24, 3: 25}
```

## Lessons Learned

- **Partition key matters**: Use a consistent partition key (e.g., `customer_id`) to ensure ordered processing per customer. Random keys distribute load but lose ordering.
- **Consumer groups**: Each independent consumer (Stream Analytics, your app, monitoring) needs its own consumer group. Sharing `$Default` causes checkpoint conflicts.
- **Stream Analytics SQL**: The `TumblingWindow` function is non-overlapping. Use `HoppingWindow` for sliding windows or `SessionWindow` for activity-based windows.
- **Checkpointing**: Stream Analytics automatically checkpoints. If the job restarts, it resumes from the last checkpoint — no data loss.
- **Throughput Units**: 1 TU = 1 MB/s ingress, 2 MB/s egress. Scale up TUs if you see throttling errors.

## Code

See `code/producer.py` — sends 100 simulated order events with 0.1s delay, shows partition key, offset, and sequence number for each event.

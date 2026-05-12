# Architecture — Project 4.6 Durable Functions Workflow

## Flow

```
HTTP POST /api/orchestrators/document_workflow
  │
  ▼
Orchestrator: document_workflow
  │
  ├── Activity: validate_document  → {valid: true}
  ├── Activity: process_document   → {pages: 10, word_count: 2500}
  └── Activity: send_notification  → "notification_sent"
  │
  ▼
HTTP GET /runtime/webhooks/durabletask/instances/{id}
  → {"runtimeStatus": "Completed", "output": {...}}
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Orchestrator | Coordinates activities — must be deterministic |
| Activity | Does actual work (I/O, computation) |
| Instance ID | Unique ID to track workflow status |
| Fan-out/fan-in | Run activities in parallel, wait for all |
| State persistence | Stored in Azure Storage Tables |

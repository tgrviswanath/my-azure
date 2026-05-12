# Architecture — Project 0.1 Local Cloud Development Setup

## Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    Your Local Machine                    │
│                                                          │
│   Azure CLI / Terraform / Python SDK                     │
│   (connection string: UseDevelopmentStorage=true)        │
│              │                                           │
│              ▼                                           │
│   ┌──────────────────────────────────────────────────┐  │
│   │              Docker Desktop                       │  │
│   │                                                   │  │
│   │   ┌───────────────────────────────────────────┐  │  │
│   │   │    Azurite  :10000/:10001/:10002          │  │  │
│   │   │                                           │  │  │
│   │   │  ┌──────┐  ┌───────┐  ┌──────────────┐  │  │  │
│   │   │  │ Blob │  │ Queue │  │    Table     │  │  │  │
│   │   │  │:10000│  │:10001 │  │    :10002    │  │  │  │
│   │   │  └──────┘  └───────┘  └──────────────┘  │  │  │
│   │   └───────────────────────────────────────────┘  │  │
│   │                                                   │  │
│   │   ┌───────────────────────────────────────────┐  │  │
│   │   │  Azure Functions Core Tools  :7071        │  │  │
│   │   └───────────────────────────────────────────┘  │  │
│   └──────────────────────────────────────────────────┘  │
│                                                          │
│   ✅ No Azure subscription needed                        │
│   ✅ No costs                                            │
│   ✅ Safe to experiment                                  │
└─────────────────────────────────────────────────────────┘
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Azurite | Official Microsoft Azure Storage emulator (replaces legacy Azure Storage Emulator) |
| Connection string | `UseDevelopmentStorage=true` redirects SDK calls to localhost |
| Port 10000 | Blob Storage endpoint — stores files/objects |
| Port 10001 | Queue Storage endpoint — async message passing |
| Port 10002 | Table Storage endpoint — NoSQL key-value store |
| Functions Core Tools | Run Azure Functions locally without any Azure subscription |
| Docker volume | Persists Azurite data between container restarts |

## Data Flow

```
Python Script
    │
    │  azure-storage-blob SDK
    │  (connection string points to localhost)
    ▼
Azurite Container (Docker)
    │
    ├── /data/blob/   ← Blob containers and files
    ├── /data/queue/  ← Queue messages
    └── /data/table/  ← Table entities
```

## Why Use Azurite Instead of Real Azure?
- No subscription required — great for CI/CD pipelines
- No network latency — faster test cycles
- No accidental charges — safe for learning
- Offline development — works without internet
- Identical API surface — code works unchanged in real Azure

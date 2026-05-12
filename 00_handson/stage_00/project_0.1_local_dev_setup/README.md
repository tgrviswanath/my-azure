# Project 0.1 — Local Cloud Development Setup

## What This Does
Emulates Azure services locally using Azurite. Allows safe development and testing without Azure costs or risk.

## Tools Used
| Tool | Purpose |
|------|---------|
| Docker + Docker Compose | Run Azurite and containers |
| Azurite | Emulate Azure Storage locally |
| Azure Functions Core Tools | Run Functions locally |
| Azure CLI | Interact with Azure via terminal |
| Terraform | Infrastructure as code |
| Git | Version control |
| VS Code + Azure Extensions | Editor |

## Services Emulated Locally
- Azure Blob Storage (Azurite)
- Azure Queue Storage (Azurite)
- Azure Table Storage (Azurite)
- Azure Functions (Core Tools)
- Cosmos DB Emulator

## How to Run
```bash
docker compose up -d
curl http://localhost:10000/devstoreaccount1
```

## Folder Structure
```
project_0.1_local_dev_setup/
├── README.md
├── steps.md
├── docker-compose.yml
├── terraform/
│   └── main.tf
├── docs/
│   └── architecture.md
├── code/
│   └── azurite_demo.py
└── cost_estimate.md
```

## Lessons Learned
- Azurite ports: 10000 (Blob), 10001 (Queue), 10002 (Table)
- Connection string: `UseDevelopmentStorage=true`
- Azure Functions Core Tools: `func start` runs functions locally
- Cosmos DB Emulator: https://localhost:8081 with fixed key
- Always use `overwrite=True` when uploading blobs in dev to avoid conflicts
- Azurite persists data in Docker volume — restart won't lose your test data

## Code

### `code/azurite_demo.py` — Run Azure Storage locally

```bash
pip install azure-storage-blob azure-storage-queue

docker compose up -d
python code/azurite_demo.py
```

What it does:
- Creates a Blob container and uploads 3 sample files
- Creates a Queue and sends/receives messages
- Prints summary of all local operations

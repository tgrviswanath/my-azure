# Architecture — Project 1.5 Python Azure Automation

## Diagram

```
  Python Script (local machine or Azure VM)
      │
      │  DefaultAzureCredential
      │  (tries: env vars → managed identity → az login → browser)
      ▼
  ┌──────────────────────────────────────────────────────────┐
  │              Azure SDK Authentication                    │
  │                                                          │
  │   Local Dev:  az login → Azure CLI token                 │
  │   Azure VM:   Managed Identity → no secrets needed       │
  │   CI/CD:      Service Principal → env vars               │
  └──────────────────────────────────────────────────────────┘
      │
      │ Authenticated requests (HTTPS)
      ▼
  ┌──────────────────────────────────────────────────────────┐
  │                  Azure Resources                         │
  │                                                          │
  │   ┌──────────────────────────────────────────────────┐  │
  │   │  Azure Blob Storage                              │  │
  │   │  BlobServiceClient → ContainerClient → BlobClient│  │
  │   │                                                  │  │
  │   │  uploads/          backups/                      │  │
  │   │  ├── file1.json    ├── backup_20240101.tar.gz    │  │
  │   │  ├── file2.json    └── backup_20240102.tar.gz    │  │
  │   │  └── report.txt                                  │  │
  │   └──────────────────────────────────────────────────┘  │
  │                                                          │
  │   ┌──────────────────────────────────────────────────┐  │
  │   │  Azure Virtual Machines                          │  │
  │   │  ComputeManagementClient                         │  │
  │   │                                                  │  │
  │   │  vm-web-server  → start/stop/deallocate          │  │
  │   │  vm-dev-box     → start/stop/deallocate          │  │
  │   └──────────────────────────────────────────────────┘  │
  └──────────────────────────────────────────────────────────┘
```

## SDK Client Hierarchy

```
azure.identity
    └── DefaultAzureCredential  ← use this everywhere

azure.storage.blob
    └── BlobServiceClient (account level)
            └── ContainerClient (container level)
                    └── BlobClient (individual blob)

azure.mgmt.compute
    └── ComputeManagementClient
            ├── virtual_machines.list()
            ├── virtual_machines.begin_start()
            └── virtual_machines.begin_deallocate()

azure.mgmt.resource
    └── ResourceManagementClient
            └── resource_groups.list()
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| DefaultAzureCredential | Tries multiple auth methods in order — works locally and in Azure |
| BlobServiceClient | Top-level client for a storage account |
| ContainerClient | Scoped to a single blob container |
| begin_* methods | Long-running operations return a poller — call `.result()` to wait |
| Managed Identity | Best auth for Azure-hosted scripts — no secrets needed |
| Idempotent uploads | `overwrite=True` makes uploads safe to re-run |

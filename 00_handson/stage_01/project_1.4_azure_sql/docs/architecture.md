# Architecture — Project 1.4 Azure SQL Database

## Diagram

```
  Application / Python Script / sqlcmd
      │
      │ TCP 1433 (TLS encrypted)
      ▼
  ┌──────────────────────────────────────────────────────────┐
  │              Azure SQL Server (logical)                  │
  │              sql-lab-server.database.windows.net         │
  │                                                          │
  │   Firewall Rules:                                        │
  │   ✅ Your IP: x.x.x.x                                   │
  │   ✅ Azure Services: 0.0.0.0                             │
  │   ❌ All other IPs: blocked                              │
  │                                                          │
  │   ┌──────────────────────────────────────────────────┐  │
  │   │  Database: labdb (Basic tier, 5 DTU)             │  │
  │   │                                                  │  │
  │   │  Tables:                                         │  │
  │   │  ┌─────────────────────────────────────────┐    │  │
  │   │  │  orders                                 │    │  │
  │   │  │  id | customer | product | amount | ... │    │  │
  │   │  └─────────────────────────────────────────┘    │  │
  │   │                                                  │  │
  │   │  Built-in features:                              │  │
  │   │  ✅ Automatic backups (7-35 days retention)      │  │
  │   │  ✅ High availability (99.99% SLA)               │  │
  │   │  ✅ Automatic patching                           │  │
  │   │  ✅ Threat detection                             │  │
  │   └──────────────────────────────────────────────────┘  │
  │                                                          │
  │   Primary Region: East US                               │
  └──────────────────────────────────────────────────────────┘
                          │
                          │ Geo-Replication (async)
                          ▼
  ┌──────────────────────────────────────────────────────────┐
  │   Secondary (Read Replica) — West US                     │
  │   sql-lab-server-westus.database.windows.net             │
  │   ✅ Readable secondary                                  │
  │   ✅ Failover target for DR                              │
  └──────────────────────────────────────────────────────────┘
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Logical Server | Container for databases — no compute, just a namespace |
| DTU | Database Transaction Unit — blended measure of CPU/IO/memory |
| Firewall Rule | IP-based access control at the server level |
| Geo-Replication | Async read replica in another region for DR |
| Automatic Backups | Full (weekly), differential (12h), log (5-10 min) |
| Connection Encryption | All connections use TLS — `Encrypt=True` in connection string |
| Azure AD Auth | Preferred over SQL auth — no passwords in connection strings |

## Connection Methods

```
┌─────────────────────────────────────────────────────────┐
│  SQL Authentication (this lab)                          │
│  Username + Password in connection string               │
│  Good for: learning, quick setup                        │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  Azure AD Authentication (recommended for production)   │
│  Uses managed identity or Azure AD user token           │
│  Good for: production, no secrets in code               │
└─────────────────────────────────────────────────────────┘
```

# Project 5.7 — Redis Caching with Azure Cache for Redis

## What This Does

Demonstrates the cache-aside pattern using Azure Cache for Redis. The application first checks Redis for cached data; on a cache hit it returns immediately, on a miss it queries Azure SQL, stores the result in Redis with a TTL, then returns the data. Includes latency benchmarking to quantify the performance improvement.

## Services Used

| Service | SKU / Tier | Purpose |
|---|---|---|
| Azure Cache for Redis | C1 Standard (1 GB) | In-memory cache with persistence |
| Azure SQL Database | Basic (5 DTU) | Persistent data store (simulated) |
| Azure App Service / Functions | Consumption / B1 | Application host |
| Azure Resource Group | — | Logical container |

## Architecture

```
Client Request
      │
      ▼
  Application
      │
      ├──► Redis Cache ──► Cache HIT ──► Return cached data (< 1 ms)
      │         │
      │    Cache MISS
      │         │
      ▼         ▼
  Azure SQL Database
      │
      └──► Store result in Redis (TTL = 300 s) ──► Return data
```

## How to Run

```bash
# 1. Deploy infrastructure
cd terraform
terraform init
terraform apply -auto-approve

# 2. Get Redis connection details
REDIS_HOST=$(terraform output -raw redis_hostname)
REDIS_KEY=$(terraform output -raw redis_primary_key)

# 3. Install Python dependencies
pip install redis azure-identity azure-mgmt-redis

# 4. Set environment variables
export REDIS_HOST=$REDIS_HOST
export REDIS_KEY=$REDIS_KEY
export REDIS_PORT=6380

# 5. Run cache pattern demo
cd ../code
python cache_patterns.py

# 6. Observe latency output
# Expected: cache miss ~50-200ms, cache hit ~0.5-2ms
```

## Lessons Learned

- The cache-aside pattern keeps the cache and DB loosely coupled — the app controls what gets cached and for how long.
- TTL selection is critical: too short causes excessive DB load, too long risks stale data.
- Redis on Azure uses SSL by default on port 6380; always set `ssl=True` in redis-py.
- C0 Basic has no SLA and no replication — use C1 Standard or higher for anything beyond local dev.
- Serializing complex objects with `json.dumps` before storing in Redis avoids type mismatch issues on retrieval.
- Connection pooling (`ConnectionPool`) is essential under load to avoid per-request TCP handshake overhead.

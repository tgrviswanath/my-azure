# Architecture — Project 5.7

## Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        Azure Region (East US)                   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Resource Group: rg-redis-proj57             │   │
│  │                                                          │   │
│  │   ┌─────────────┐        ┌──────────────────────────┐   │   │
│  │   │   Client    │        │   Azure Cache for Redis  │   │   │
│  │   │  (App Svc   │──SSL──►│   C1 Standard, 1 GB      │   │   │
│  │   │   / Func)   │◄──────│   Port 6380 (TLS)        │   │   │
│  │   └──────┬──────┘        │   maxmemory-policy:      │   │   │
│  │          │               │   allkeys-lru            │   │   │
│  │          │ cache miss     └──────────────────────────┘   │   │
│  │          ▼                                               │   │
│  │   ┌─────────────┐                                       │   │
│  │   │  Azure SQL  │  ◄── Fallback data source             │   │
│  │   │  Database   │      (cache miss path only)           │   │
│  │   │  Basic 5DTU │                                       │   │
│  │   └─────────────┘                                       │   │
│  │                                                          │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘

Cache-Aside Flow:
─────────────────
  READ:
    App ──► Redis GET key
              ├── HIT  ──► return value  (fast path, ~1ms)
              └── MISS ──► SQL SELECT
                              └──► Redis SET key value EX 300
                                      └──► return value  (slow path, ~100ms)

  WRITE (write-through variant):
    App ──► SQL UPDATE
              └──► Redis DEL key  (invalidate, not update)
                      └──► next read will repopulate cache
```

## Key Concepts

| Concept | Description |
|---|---|
| Cache-Aside (Lazy Loading) | Application code manages cache population. Cache is only populated on a miss, keeping unused data out of memory. |
| TTL (Time-To-Live) | Each key has an expiry (`EX 300` = 5 minutes). Prevents stale data accumulating indefinitely. |
| Cache Invalidation | On write, delete the cache key rather than updating it. Simpler and avoids race conditions. |
| SSL/TLS on port 6380 | Azure Cache for Redis enforces TLS. Non-SSL port 6379 is disabled by default. Always use `ssl=True`. |
| Connection Pooling | `redis.ConnectionPool` reuses TCP connections. Critical for high-throughput apps to avoid per-request handshake cost. |
| maxmemory-policy | `allkeys-lru` evicts least-recently-used keys when memory is full. Appropriate for a pure cache workload. |
| Serialization | Redis stores strings. Complex objects must be serialized (`json.dumps`) before SET and deserialized (`json.loads`) after GET. |
| Persistence (RDB) | C1 Standard includes RDB snapshots. Allows cache warm-up after a Redis restart instead of cold-start. |

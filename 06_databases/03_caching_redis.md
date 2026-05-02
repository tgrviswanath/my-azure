# Azure Cache for Redis — Deep Dive

## What is Azure Cache for Redis?
A fully managed, in-memory data store based on Redis. Provides sub-millisecond latency for caching, session management, real-time leaderboards, and pub/sub messaging.

---

## Tiers

| Tier | Max Memory | Replication | Clustering | Use Case |
|------|-----------|-------------|-----------|---------|
| Basic | 53 GB | ❌ | ❌ | Dev/test only |
| Standard | 53 GB | ✅ Primary+Replica | ❌ | Production, HA |
| Premium | 1.2 TB | ✅ | ✅ Up to 10 shards | High throughput, persistence |
| Enterprise | 14 TB | ✅ | ✅ | Largest scale, Redis modules |
| Enterprise Flash | 14 TB | ✅ | ✅ | Cost-optimized large cache |

---

## Create and Configure

```bash
# Create Standard C1 cache (1GB, HA)
az redis create \
  --name redis-myapp-prod \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard \
  --vm-size C1 \
  --enable-non-ssl-port false \
  --minimum-tls-version 1.2 \
  --redis-configuration maxmemory-policy=allkeys-lru

# Get connection string
REDIS_HOST=$(az redis show \
  --name redis-myapp-prod \
  --resource-group $RG \
  --query hostName --output tsv)

REDIS_KEY=$(az redis list-keys \
  --name redis-myapp-prod \
  --resource-group $RG \
  --query primaryKey --output tsv)

echo "Redis: $REDIS_HOST:6380 (SSL)"

# Create Premium with clustering (3 shards)
az redis create \
  --name redis-myapp-premium \
  --resource-group $RG \
  --location $LOCATION \
  --sku Premium \
  --vm-size P3 \
  --shard-count 3 \
  --enable-non-ssl-port false \
  --minimum-tls-version 1.2 \
  --redis-configuration \
    maxmemory-policy=allkeys-lru \
    rdb-backup-enabled=true \
    rdb-backup-frequency=60 \
    rdb-backup-max-snapshot-count=1 \
    rdb-storage-connection-string="$STORAGE_CONNECTION"

# Private endpoint for Redis
az network private-endpoint create \
  --name pe-redis-prod \
  --resource-group $RG \
  --vnet-name vnet-app-prod \
  --subnet snet-pe \
  --private-connection-resource-id $(az redis show \
    --name redis-myapp-prod --resource-group $RG --query id --output tsv) \
  --group-id redisCache \
  --connection-name conn-redis
```

---

## Common Patterns

### Session Store (Node.js)

```javascript
const redis = require('ioredis');

// Connection with TLS (required for Azure Cache for Redis)
const client = new redis({
    host: process.env.REDIS_HOST,
    port: 6380,
    password: process.env.REDIS_KEY,
    tls: { servername: process.env.REDIS_HOST },
    retryStrategy: (times) => Math.min(times * 50, 2000),
    maxRetriesPerRequest: 3
});

// Session management
async function setSession(sessionId, userId, data, ttlSeconds = 3600) {
    const sessionData = JSON.stringify({ userId, ...data, createdAt: Date.now() });
    await client.setex(`session:${sessionId}`, ttlSeconds, sessionData);
    return sessionId;
}

async function getSession(sessionId) {
    const data = await client.get(`session:${sessionId}`);
    if (!data) return null;
    // Refresh TTL on access
    await client.expire(`session:${sessionId}`, 3600);
    return JSON.parse(data);
}

async function deleteSession(sessionId) {
    await client.del(`session:${sessionId}`);
}
```

### Database Query Cache (Python)

```python
import redis
import json
import hashlib
import time
from functools import wraps

r = redis.Redis(
    host=os.environ['REDIS_HOST'],
    port=6380,
    password=os.environ['REDIS_KEY'],
    ssl=True,
    decode_responses=True
)

def cache(ttl=300, key_prefix=''):
    """Decorator to cache function results in Redis."""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            # Build cache key from function name + args
            cache_key = f"{key_prefix}{func.__name__}:{hashlib.md5(str(args).encode()).hexdigest()}"
            
            # Try cache first
            cached = r.get(cache_key)
            if cached:
                return json.loads(cached)
            
            # Cache miss — call function
            result = func(*args, **kwargs)
            
            # Store in cache
            r.setex(cache_key, ttl, json.dumps(result, default=str))
            return result
        return wrapper
    return decorator

@cache(ttl=300, key_prefix='product:')
def get_product(product_id: str) -> dict:
    # Expensive DB query
    return db.query("SELECT * FROM products WHERE id = %s", product_id)

def invalidate_product(product_id: str):
    """Invalidate cache when product is updated."""
    pattern = f"product:get_product:*"
    keys = r.keys(pattern)
    if keys:
        r.delete(*keys)
```

### Rate Limiting

```python
def check_rate_limit(identifier: str, limit: int = 100, window: int = 60) -> dict:
    """
    Sliding window rate limiter using Redis sorted sets.
    Returns: {'allowed': bool, 'remaining': int, 'reset_at': int}
    """
    now = time.time()
    window_start = now - window
    key = f"rate_limit:{identifier}"
    
    pipe = r.pipeline()
    # Remove old entries outside window
    pipe.zremrangebyscore(key, 0, window_start)
    # Count current requests
    pipe.zcard(key)
    # Add current request
    pipe.zadd(key, {str(now): now})
    # Set expiry
    pipe.expire(key, window)
    results = pipe.execute()
    
    current_count = results[1]
    allowed = current_count < limit
    
    return {
        'allowed': allowed,
        'remaining': max(0, limit - current_count - 1),
        'reset_at': int(now + window)
    }
```

### Distributed Lock

```python
import uuid

def acquire_lock(resource: str, ttl: int = 30) -> str | None:
    """Acquire distributed lock. Returns lock_id if acquired, None if not."""
    lock_id = str(uuid.uuid4())
    # SET NX EX — atomic set-if-not-exists with expiry
    acquired = r.set(f"lock:{resource}", lock_id, nx=True, ex=ttl)
    return lock_id if acquired else None

def release_lock(resource: str, lock_id: str) -> bool:
    """Release lock only if we own it (atomic check-and-delete)."""
    script = """
    if redis.call('get', KEYS[1]) == ARGV[1] then
        return redis.call('del', KEYS[1])
    else
        return 0
    end
    """
    result = r.eval(script, 1, f"lock:{resource}", lock_id)
    return bool(result)

# Usage
lock_id = acquire_lock("order-123", ttl=30)
if lock_id:
    try:
        process_order("order-123")
    finally:
        release_lock("order-123", lock_id)
else:
    raise Exception("Could not acquire lock — order being processed")
```

### Leaderboard (Sorted Sets)

```python
def update_score(user_id: str, score: float, leaderboard: str = "global"):
    r.zadd(f"leaderboard:{leaderboard}", {user_id: score})

def get_top_players(n: int = 10, leaderboard: str = "global") -> list:
    return r.zrevrange(f"leaderboard:{leaderboard}", 0, n - 1, withscores=True)

def get_player_rank(user_id: str, leaderboard: str = "global") -> int | None:
    rank = r.zrevrank(f"leaderboard:{leaderboard}", user_id)
    return rank + 1 if rank is not None else None

def get_player_score(user_id: str, leaderboard: str = "global") -> float | None:
    return r.zscore(f"leaderboard:{leaderboard}", user_id)
```

---

## Geo-Replication (Premium)

```bash
# Create primary cache
az redis create \
  --name redis-primary-eastus \
  --resource-group $RG_EAST \
  --location eastus \
  --sku Premium \
  --vm-size P1

# Create secondary cache (same SKU, different region)
az redis create \
  --name redis-secondary-westus \
  --resource-group $RG_WEST \
  --location westus \
  --sku Premium \
  --vm-size P1

# Link for geo-replication
az redis geo-replication link \
  --name redis-primary-eastus \
  --resource-group $RG_EAST \
  --server-to-link $(az redis show \
    --name redis-secondary-westus \
    --resource-group $RG_WEST \
    --query id --output tsv)
```

---

## Eviction Policies

| Policy | Behavior | Best For |
|--------|---------|---------|
| `noeviction` | Return error when full | Critical data, never evict |
| `allkeys-lru` | Evict least recently used | General caching |
| `volatile-lru` | Evict LRU with TTL set | Mixed TTL/no-TTL data |
| `allkeys-lfu` | Evict least frequently used | Frequency-based caching |
| `allkeys-random` | Evict random key | Random access patterns |
| `volatile-ttl` | Evict soonest-to-expire | TTL-based eviction |

```bash
# Set eviction policy
az redis update \
  --name redis-myapp-prod \
  --resource-group $RG \
  --redis-configuration maxmemory-policy=allkeys-lru
```

---

## Monitoring

```bash
# Key metrics to monitor
# CacheHits / CacheMisses → Hit ratio (target > 90%)
# UsedMemory → Memory pressure (alert at 80%)
# ConnectedClients → Connection count
# ServerLoad → CPU usage (alert at 80%)
# Evictions → Should be 0 (if > 0, increase cache size)

# Create alert for high memory
az monitor metrics alert create \
  --name redis-high-memory \
  --resource-group $RG \
  --scopes $(az redis show --name redis-myapp-prod --resource-group $RG --query id --output tsv) \
  --condition "avg UsedMemoryPercentage > 80" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action $ACTION_GROUP_ID \
  --description "Redis memory usage above 80%"
```

---

## Interview Q&A

### Q1: What is the difference between Azure Cache for Redis tiers?
**Basic**: Single node, no SLA, dev/test only. **Standard**: Primary + replica, 99.9% SLA, automatic failover. **Premium**: Clustering (up to 10 shards), persistence (RDB/AOF), VNet injection, geo-replication. **Enterprise**: Redis Enterprise engine, Redis modules (RediSearch, RedisJSON), 99.999% SLA. Choose Standard for most production, Premium for large datasets or geo-replication.

### Q2: What caching strategy would you use for a product catalog?
Cache-aside (lazy loading) with write-through on updates. On read: check Redis, miss → query SQL, store in Redis with TTL (e.g., 5 minutes). On product update: update SQL, then delete or update Redis key. Use longer TTLs for stable data (categories: 1hr), shorter for frequently changing data (prices: 1min). Consider cache stampede protection with mutex or probabilistic early expiration.

### Q3: How do you handle Redis connection failures in production?
1. Use connection pooling with retry logic (ioredis retryStrategy, StackExchange.Redis reconnect)
2. Circuit breaker pattern — stop trying after N failures, use fallback (DB direct)
3. Set appropriate timeouts (connect: 5s, command: 1s)
4. Use `WAIT` command for critical writes requiring replication confirmation
5. Monitor `ConnectedClients` and `ServerLoad` metrics
6. Enable geo-replication for cross-region failover
7. Design application to degrade gracefully without cache (slower, not broken)

### Q4: What is a cache stampede and how do you prevent it?
Cache stampede (thundering herd): many requests hit a cache miss simultaneously, all query the database at once, overwhelming it. Prevention: (1) Mutex/lock — only one request fetches from DB, others wait, (2) Probabilistic early expiration — refresh cache slightly before TTL expires, (3) Background refresh — async refresh before expiry, (4) Stale-while-revalidate — serve stale data while refreshing asynchronously.

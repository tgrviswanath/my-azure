"""
Project 5.7 — Azure Cache for Redis: Cache-Aside Pattern Demo
=============================================================
Demonstrates:
  - Connecting to Azure Cache for Redis with SSL via redis-py
  - Cache-aside (lazy loading) pattern
  - TTL-based expiry
  - Session storage pattern
  - Latency benchmarking: cache hit vs cache miss

Requirements:
    pip install redis azure-identity azure-mgmt-redis

Environment variables:
    REDIS_HOST      — e.g. redis-proj57-abc123.redis.cache.windows.net
    REDIS_KEY       — primary access key from Terraform output
    REDIS_PORT      — 6380 (default, SSL)
"""

import json
import os
import time
import argparse
import logging
import statistics
from typing import Optional, Any
from datetime import datetime

import redis
from redis import ConnectionPool

# ── Logging ────────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)


# ── Redis Connection ───────────────────────────────────────────────────────────

def get_redis_client() -> redis.StrictRedis:
    """
    Create a Redis client connected to Azure Cache for Redis over TLS.
    Uses a ConnectionPool to reuse TCP connections across calls.
    """
    host = os.environ.get("REDIS_HOST")
    key  = os.environ.get("REDIS_KEY")
    port = int(os.environ.get("REDIS_PORT", 6380))

    if not host or not key:
        raise EnvironmentError(
            "REDIS_HOST and REDIS_KEY environment variables must be set.\n"
            "Run: export REDIS_HOST=$(cd terraform && terraform output -raw redis_hostname)\n"
            "     export REDIS_KEY=$(cd terraform && terraform output -raw redis_primary_key)"
        )

    pool = ConnectionPool(
        host=host,
        port=port,
        password=key,
        ssl=True,
        ssl_cert_reqs=None,          # Azure uses a valid cert; set to ssl.CERT_REQUIRED in prod
        decode_responses=True,
        max_connections=20,
        socket_connect_timeout=5,
        socket_timeout=5,
        retry_on_timeout=True,
    )
    client = redis.StrictRedis(connection_pool=pool)

    # Verify connectivity
    client.ping()
    info = client.info("server")
    log.info("Connected to Redis %s on %s:%d", info["redis_version"], host, port)
    return client


# ── Simulated Database Layer ───────────────────────────────────────────────────

# In a real app this would be pyodbc / SQLAlchemy hitting Azure SQL.
# Here we simulate with an in-memory dict + artificial latency.
_FAKE_DB: dict[str, dict] = {
    "1001": {"id": "1001", "name": "Alice Nguyen",  "email": "alice@example.com",  "role": "admin"},
    "1002": {"id": "1002", "name": "Bob Tanaka",    "email": "bob@example.com",    "role": "user"},
    "1003": {"id": "1003", "name": "Carol Okonkwo", "email": "carol@example.com",  "role": "user"},
}

def db_get_user(user_id: str, simulate_latency_ms: int = 100) -> Optional[dict]:
    """Simulate a slow database query."""
    time.sleep(simulate_latency_ms / 1000)
    return _FAKE_DB.get(user_id)


# ── Cache-Aside Pattern ────────────────────────────────────────────────────────

CACHE_TTL_SECONDS = 300  # 5 minutes


def get_user(r: redis.StrictRedis, user_id: str) -> Optional[dict]:
    """
    Cache-aside read:
      1. Try Redis first.
      2. On miss, query the DB.
      3. Store result in Redis with TTL.
      4. Return data.
    """
    cache_key = f"user:{user_id}"

    # Step 1 — check cache
    cached = r.get(cache_key)
    if cached is not None:
        log.info("CACHE HIT  key=%s", cache_key)
        return json.loads(cached)

    # Step 2 — cache miss, go to DB
    log.info("CACHE MISS key=%s — querying database...", cache_key)
    user = db_get_user(user_id)

    if user is None:
        log.warning("User %s not found in database", user_id)
        return None

    # Step 3 — populate cache
    r.set(cache_key, json.dumps(user), ex=CACHE_TTL_SECONDS)
    log.info("CACHE SET  key=%s  TTL=%ds", cache_key, CACHE_TTL_SECONDS)

    return user


def invalidate_user(r: redis.StrictRedis, user_id: str) -> None:
    """
    Cache invalidation on write:
    Delete the cache key so the next read repopulates from DB.
    Simpler and safer than trying to update the cached value.
    """
    cache_key = f"user:{user_id}"
    deleted = r.delete(cache_key)
    if deleted:
        log.info("CACHE INVALIDATED key=%s", cache_key)
    else:
        log.info("CACHE KEY not present (nothing to invalidate): %s", cache_key)


def update_user(r: redis.StrictRedis, user_id: str, updates: dict) -> Optional[dict]:
    """Write-through: update DB then invalidate cache."""
    if user_id not in _FAKE_DB:
        return None
    _FAKE_DB[user_id].update(updates)
    invalidate_user(r, user_id)
    return _FAKE_DB[user_id]


# ── TTL Expiry Demo ────────────────────────────────────────────────────────────

def demo_ttl_expiry(r: redis.StrictRedis) -> None:
    """Show a key expiring after its TTL."""
    log.info("\n── TTL Expiry Demo ──────────────────────────────────────")
    key = "ttl_demo"
    r.set(key, "I will expire in 5 seconds", ex=5)
    log.info("SET %s with TTL=5s", key)

    for elapsed in [1, 3, 5, 6]:
        time.sleep(1)
        val = r.get(key)
        ttl = r.ttl(key)
        log.info("t+%ds  value=%s  TTL=%s", elapsed, val, ttl)


# ── Session Storage Pattern ────────────────────────────────────────────────────

def create_session(r: redis.StrictRedis, session_id: str, user_id: str) -> None:
    """Store a user session in Redis with a 30-minute TTL."""
    session_key = f"session:{session_id}"
    session_data = {
        "user_id": user_id,
        "created_at": datetime.utcnow().isoformat(),
        "last_active": datetime.utcnow().isoformat(),
    }
    r.set(session_key, json.dumps(session_data), ex=1800)  # 30 min
    log.info("SESSION CREATED  key=%s  user=%s  TTL=1800s", session_key, user_id)


def get_session(r: redis.StrictRedis, session_id: str) -> Optional[dict]:
    """Retrieve a session and slide the TTL (rolling expiry)."""
    session_key = f"session:{session_id}"
    raw = r.get(session_key)
    if raw is None:
        log.info("SESSION EXPIRED or NOT FOUND: %s", session_key)
        return None

    session = json.loads(raw)
    session["last_active"] = datetime.utcnow().isoformat()

    # Slide the TTL — reset to 30 min on each access
    r.set(session_key, json.dumps(session), ex=1800)
    log.info("SESSION HIT  key=%s  user=%s  TTL reset to 1800s", session_key, session["user_id"])
    return session


# ── Latency Benchmark ──────────────────────────────────────────────────────────

def benchmark(r: redis.StrictRedis, iterations: int = 100) -> None:
    """
    Measure average latency for cache hits vs cache misses.
    Clears the cache before running to ensure a clean baseline.
    """
    log.info("\n── Latency Benchmark (%d iterations) ──────────────────", iterations)

    # Flush only our test keys
    for uid in _FAKE_DB:
        r.delete(f"user:{uid}")

    miss_latencies: list[float] = []
    hit_latencies:  list[float] = []

    user_ids = list(_FAKE_DB.keys())

    # Warm up — one miss per user to populate cache
    for uid in user_ids:
        t0 = time.perf_counter()
        get_user(r, uid)
        miss_latencies.append((time.perf_counter() - t0) * 1000)

    # Now measure hits
    for i in range(iterations):
        uid = user_ids[i % len(user_ids)]
        t0 = time.perf_counter()
        get_user(r, uid)
        hit_latencies.append((time.perf_counter() - t0) * 1000)

    miss_avg = statistics.mean(miss_latencies)
    hit_avg  = statistics.mean(hit_latencies)
    speedup  = miss_avg / hit_avg if hit_avg > 0 else float("inf")

    print("\n" + "=" * 50)
    print(f"  Cache MISS avg latency : {miss_avg:>8.2f} ms")
    print(f"  Cache HIT  avg latency : {hit_avg:>8.2f} ms")
    print(f"  Speedup factor         : {speedup:>8.1f}x")
    print("=" * 50 + "\n")


# ── Main Demo ──────────────────────────────────────────────────────────────────

def main(run_benchmark: bool = False) -> None:
    r = get_redis_client()

    # ── 1. Cache-aside reads ──────────────────────────────────────────────────
    log.info("\n── Cache-Aside Pattern Demo ─────────────────────────────")

    # First call — cache miss, goes to DB
    user = get_user(r, "1001")
    log.info("Result: %s", user)

    # Second call — cache hit
    user = get_user(r, "1001")
    log.info("Result: %s", user)

    # Check TTL remaining
    ttl = r.ttl("user:1001")
    log.info("TTL remaining for user:1001 = %d seconds", ttl)

    # ── 2. Cache invalidation on write ───────────────────────────────────────
    log.info("\n── Write + Invalidation Demo ────────────────────────────")
    updated = update_user(r, "1001", {"role": "superadmin"})
    log.info("Updated in DB: %s", updated)

    # Next read will miss cache and fetch updated data from DB
    user = get_user(r, "1001")
    log.info("After invalidation, fresh read: %s", user)

    # ── 3. TTL expiry ─────────────────────────────────────────────────────────
    demo_ttl_expiry(r)

    # ── 4. Session storage ────────────────────────────────────────────────────
    log.info("\n── Session Storage Demo ─────────────────────────────────")
    session_id = "sess_abc123xyz"
    create_session(r, session_id, "1002")
    session = get_session(r, session_id)
    log.info("Session data: %s", session)

    # ── 5. Benchmark ──────────────────────────────────────────────────────────
    if run_benchmark:
        benchmark(r, iterations=100)

    log.info("\nDemo complete.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Azure Cache for Redis — cache-aside demo")
    parser.add_argument(
        "--benchmark",
        action="store_true",
        help="Run latency benchmark (100 iterations)",
    )
    args = parser.parse_args()
    main(run_benchmark=args.benchmark)

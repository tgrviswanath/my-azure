# Steps — Project 5.7 Redis Cache with Azure Cache for Redis

## Phase 1 — Deploy Redis via Terraform

```bash
# Navigate to terraform directory
cd stage_05/project_5.7_redis_cache/terraform

# Initialize Terraform and download azurerm provider
terraform init

# Preview what will be created
terraform plan -out=tfplan

# Deploy Azure Cache for Redis (takes ~15-20 minutes)
terraform apply tfplan

# Capture outputs for later use
terraform output -raw redis_hostname
terraform output -raw redis_primary_key
terraform output -raw redis_port

# Verify Redis is running in the portal or via CLI
az redis show \
  --name $(terraform output -raw redis_name) \
  --resource-group $(terraform output -raw resource_group_name) \
  --query "provisioningState" \
  --output tsv
# Expected: Succeeded
```

## Phase 2 — Connect with redis-py

```bash
# Install required packages
pip install redis azure-identity azure-mgmt-redis

# Export connection details as environment variables
export REDIS_HOST=$(cd terraform && terraform output -raw redis_hostname)
export REDIS_KEY=$(cd terraform && terraform output -raw redis_primary_key)
export REDIS_PORT=6380

# Quick connectivity test from Python REPL
python3 - <<'EOF'
import redis, os, ssl

r = redis.StrictRedis(
    host=os.environ["REDIS_HOST"],
    port=int(os.environ.get("REDIS_PORT", 6380)),
    password=os.environ["REDIS_KEY"],
    ssl=True,
    ssl_cert_reqs=None,
    decode_responses=True
)
r.ping()
print("Connected to Redis:", r.info("server")["redis_version"])
EOF

# Test basic set/get
python3 - <<'EOF'
import redis, os
r = redis.StrictRedis(
    host=os.environ["REDIS_HOST"],
    port=6380,
    password=os.environ["REDIS_KEY"],
    ssl=True,
    decode_responses=True
)
r.set("test_key", "hello_azure", ex=60)
print(r.get("test_key"))   # hello_azure
print(r.ttl("test_key"))   # ~60
EOF
```

## Phase 3 — Implement Cache-Aside Pattern

```bash
# Run the full cache-aside demo
cd ../code
python cache_patterns.py

# The script will:
# 1. Attempt to GET user:1001 from Redis → cache miss
# 2. Simulate DB query (sleep 100ms)
# 3. SET user:1001 in Redis with TTL=300s
# 4. Return data and log latency

# Second call (within TTL):
# 1. GET user:1001 from Redis → cache hit
# 2. Return immediately, log latency

# Verify keys in Redis
python3 - <<'EOF'
import redis, os
r = redis.StrictRedis(
    host=os.environ["REDIS_HOST"],
    port=6380,
    password=os.environ["REDIS_KEY"],
    ssl=True,
    decode_responses=True
)
# List all cached keys
keys = r.keys("user:*")
print("Cached keys:", keys)
for k in keys:
    print(f"  {k} → TTL: {r.ttl(k)}s  Value: {r.get(k)[:60]}...")
EOF

# Test TTL expiry — set a short TTL and watch it expire
python3 - <<'EOF'
import redis, os, time
r = redis.StrictRedis(
    host=os.environ["REDIS_HOST"],
    port=6380,
    password=os.environ["REDIS_KEY"],
    ssl=True,
    decode_responses=True
)
r.set("expire_test", "will_vanish", ex=5)
print("Set key with 5s TTL")
time.sleep(3)
print("After 3s:", r.get("expire_test"))   # will_vanish
time.sleep(3)
print("After 6s:", r.get("expire_test"))   # None
EOF
```

## Phase 4 — Measure Latency Improvement

```bash
# Run the latency benchmark included in cache_patterns.py
python cache_patterns.py --benchmark

# Expected output:
# Running 100 iterations...
# Cache MISS avg latency : 112.4 ms  (simulated DB query)
# Cache HIT  avg latency :   0.8 ms
# Speedup factor         : 140.5x

# Monitor Redis metrics in Azure Monitor
az monitor metrics list \
  --resource $(az redis show \
    --name redisproj57 \
    --resource-group rg-redis-proj57 \
    --query id -o tsv) \
  --metric "cachehits,cachemisses,connectedclients" \
  --interval PT1M \
  --output table

# Check memory usage
az redis show \
  --name redisproj57 \
  --resource-group rg-redis-proj57 \
  --query "[usedMemory, usedMemoryRss, maxmemoryPolicy]" \
  --output json

# Clean up after testing
cd ../terraform
terraform destroy -auto-approve
```

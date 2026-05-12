# Steps — Project 5.2 Multi-container Application

## Phase 1 — Start Stack
```bash
cp .env.example .env
docker compose up -d
docker compose ps
docker compose logs backend
```

## Phase 2 — Test
```bash
# Create item
curl -X POST http://localhost:4000/items \
  -H "Content-Type: application/json" -d '{"name":"Test Item"}'

# List items (first call: from DB)
curl http://localhost:4000/items

# List items (second call: from Redis cache)
curl http://localhost:4000/items
```

## Phase 3 — Cleanup
```bash
docker compose down -v   # -v removes volumes
```

## Screenshots to Take
- [ ] All 3 services running (`docker compose ps`)
- [ ] First request showing `source: db`
- [ ] Second request showing `source: cache`

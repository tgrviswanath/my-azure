# Architecture — Project 5.2 Multi-container Application

## Docker Compose Network

```
backend:4000
  ├── → postgres:5432  (DB queries)
  └── → redis:6379     (cache reads/writes)

All services on same Docker network — communicate by service name
Named volumes: postgres_data, redis_data (persist across restarts)
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Service name DNS | `postgres` resolves to container IP automatically |
| Named volumes | Data persists when containers restart |
| Health check | `depends_on` waits for postgres to be ready |
| Cache-aside | Check Redis first, fall back to DB, populate cache |

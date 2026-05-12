# Project 5.2 — Multi-container Application

## What This Does
Runs Frontend + Backend + PostgreSQL + Redis together using Docker Compose.

## How to Run
```bash
docker compose up -d
curl http://localhost:3000        # Frontend
curl http://localhost:4000/health # Backend API
```

## Lessons Learned
- Use named volumes for database persistence
- Services communicate by service name (e.g., `postgres`, `redis`)
- Use `.env.example` — never commit `.env` with real credentials

## Services Used
| Service | Purpose |
|---------|---------|
| Node.js + Express | Backend API |
| PostgreSQL | Relational database |
| Redis | Session cache |
| Docker Compose | Multi-container orchestration |

## Architecture
```
Browser → Frontend (port 80)
              │
              ▼
         Backend API (port 3000)
              ├── PostgreSQL (port 5432) — persistent data
              └── Redis (port 6379) — session cache
```

## Code

### `backend/server.js` — Node.js Express API

```bash
# Start all services
cp .env.example .env
docker compose up -d

# Check health
curl http://localhost:3000/health
curl http://localhost:3000/api/items

# View logs
docker compose logs -f backend

# Run health check script
pip install requests
python code/health_check.py

# Stop
docker compose down
```

### `code/health_check.py` — Verify all containers are healthy

```bash
pip install requests
python code/health_check.py
```

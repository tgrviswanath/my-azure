# Project 5.1 — Single-service Docker Application

## What This Does
Containerizes a Python Flask app and runs it locally with Docker.

## How to Run
```bash
docker build -t myapp:latest .
docker run -p 8000:8000 myapp:latest
curl http://localhost:8000/health
```

## Lessons Learned
- Use multi-stage builds to keep images small
- Never run as root in containers
- Use `.dockerignore` to exclude unnecessary files

## Services Used
| Tool | Purpose |
|------|---------|
| Docker | Container runtime |
| Flask | Python web framework |
| Azure Container Registry | Push image for cloud deployment |

## Architecture
```
Developer
    │ docker build
    ▼
Docker Image (myapp:latest)
    │ docker run -p 8080:8080
    ▼
Container (Flask app)
    ├── GET /health → {"status": "healthy"}
    ├── GET /       → app info
    └── GET /api/items → sample data
```

## Code

### `code/app.py` — Flask application

```bash
pip install flask

# Run directly
python code/app.py

# Or with Docker
docker build -t handson-app .
docker run -p 8080:8080 handson-app

# Test
curl http://localhost:8080/health
curl http://localhost:8080/api/items
```

### `Dockerfile` — Multi-stage build

```bash
# Build image
docker build -t handson-app:v1.0 .

# Check image size
docker images handson-app

# Run with environment variable
docker run -p 8080:8080 -e APP_VERSION=1.0.0 handson-app:v1.0
```

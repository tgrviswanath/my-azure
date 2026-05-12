# Architecture — Project 5.1 Single-service Docker Application

## Container Structure

```
Dockerfile (multi-stage)
  └── python:3.11-slim base
        ├── Install dependencies
        ├── Copy app code
        ├── Create non-root user
        └── EXPOSE 8000 → CMD python app.py

Host: localhost:8000 → Container: 8000
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Multi-stage build | Separate build and runtime stages for smaller image |
| Non-root user | Security best practice — never run as root |
| `.dockerignore` | Exclude `.git`, `__pycache__`, `.env` from image |
| Health check | `/health` endpoint for container orchestrators |

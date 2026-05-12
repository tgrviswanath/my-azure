# Steps — Project 5.1 Single-service Docker Application

## Phase 1 — Build and Run Locally
```bash
docker build -t myapp:latest .
docker run -p 8000:8000 myapp:latest
curl http://localhost:8000/health
curl http://localhost:8000/
```

## Phase 2 — Inspect Container
```bash
docker ps
docker logs <container_id>
docker exec -it <container_id> /bin/sh
docker stats <container_id>
```

## Phase 3 — Push to ACR (preview for 5.3)
```bash
az acr login --name <acr_name>
docker tag myapp:latest <acr_name>.azurecr.io/myapp:latest
docker push <acr_name>.azurecr.io/myapp:latest
```

## Screenshots to Take
- [ ] `docker build` succeeding
- [ ] App responding on localhost:8000
- [ ] `docker ps` showing running container

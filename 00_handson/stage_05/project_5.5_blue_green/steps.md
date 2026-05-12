# Steps — Project 5.5 Blue-Green Deployment

## Phase 1 — Deploy Blue (v1)
```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-blue
spec:
  replicas: 2
  selector:
    matchLabels: {app: myapp, version: blue}
  template:
    metadata:
      labels: {app: myapp, version: blue}
    spec:
      containers:
        - name: myapp
          image: acrhandson001.azurecr.io/myapp:v1.0
          ports: [{containerPort: 8000}]
EOF

kubectl patch service myapp-svc -p '{"spec":{"selector":{"version":"blue"}}}'
```

## Phase 2 — Deploy Green (v2) Alongside
```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-green
spec:
  replicas: 2
  selector:
    matchLabels: {app: myapp, version: green}
  template:
    metadata:
      labels: {app: myapp, version: green}
    spec:
      containers:
        - name: myapp
          image: acrhandson001.azurecr.io/myapp:v2.0
          ports: [{containerPort: 8000}]
EOF
```

## Phase 3 — Switch Traffic
```bash
# Verify green is healthy first
kubectl get pods -l version=green

# Switch
kubectl patch service myapp-svc -p '{"spec":{"selector":{"version":"green"}}}'

# Rollback if needed
kubectl patch service myapp-svc -p '{"spec":{"selector":{"version":"blue"}}}'
```

## Screenshots to Take
- [ ] Blue and green deployments running simultaneously
- [ ] Service selector switched to green
- [ ] Zero downtime during switch

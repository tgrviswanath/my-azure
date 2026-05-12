# Architecture — Project 5.5 Blue-Green Deployment

## Flow

```
Service: myapp-svc
  selector: version=blue  ──→  Deployment: myapp-blue (v1.0) [LIVE]
                                Deployment: myapp-green (v2.0) [STANDBY]

After switch:
  selector: version=green ──→  Deployment: myapp-green (v2.0) [LIVE]
                                Deployment: myapp-blue (v1.0) [STANDBY → delete]
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Blue-green | Two identical environments, instant traffic switch |
| Service selector | Label-based routing — change label = change target |
| Zero downtime | No pod restarts during switch |
| Rollback | Switch selector back to blue instantly |
| Canary alternative | Gradual shift using weighted ingress rules |

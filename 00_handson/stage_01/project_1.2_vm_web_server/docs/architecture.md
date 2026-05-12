# Architecture — Project 1.2 Linux Web Server on Azure VM

## Diagram

```
  Internet
      │
      │ HTTP :80 / HTTPS :443 / SSH :22
      ▼
  ┌──────────────────────────────────────────────────────────┐
  │                  Azure (East US)                         │
  │                                                          │
  │  Public IP: x.x.x.x (Static)                            │
  │      │                                                   │
  │      ▼                                                   │
  │  ┌──────────────────────────────────────────────────┐   │
  │  │   Network Security Group (vm-web-nsg)            │   │
  │  │                                                  │   │
  │  │   Priority  Name          Port  Action           │   │
  │  │   100       Allow-SSH     22    Allow ✅          │   │
  │  │   110       Allow-HTTP    80    Allow ✅          │   │
  │  │   120       Allow-HTTPS   443   Allow ✅          │   │
  │  │   65500     DenyAllInbound *    Deny  ❌          │   │
  │  └──────────────────────────────────────────────────┘   │
  │      │                                                   │
  │      ▼                                                   │
  │  ┌──────────────────────────────────────────────────┐   │
  │  │   Azure VM: B2s (Ubuntu 22.04 LTS)               │   │
  │  │   Private IP: 10.0.1.4                           │   │
  │  │                                                  │   │
  │  │   ┌──────────────────────────────────────────┐  │   │
  │  │   │  Nginx (port 80/443)                     │  │   │
  │  │   │                                          │  │   │
  │  │   │  /          → /var/www/html (static)     │  │   │
  │  │   │  /api/      → localhost:8080 (proxy)     │  │   │
  │  │   └──────────────────────────────────────────┘  │   │
  │  │                                                  │   │
  │  │   ┌──────────────────────────────────────────┐  │   │
  │  │   │  Backend App (port 8080) — optional      │  │   │
  │  │   └──────────────────────────────────────────┘  │   │
  │  └──────────────────────────────────────────────────┘   │
  │                                                          │
  │  VNet: 10.0.0.0/16  │  Subnet: 10.0.1.0/24             │
  └──────────────────────────────────────────────────────────┘
```

## Nginx Reverse Proxy Flow

```
Client Request: GET /api/users
    │
    ▼
Nginx (port 80)
    │
    │ location /api/ { proxy_pass http://localhost:8080/; }
    ▼
Backend App (port 8080)
    │
    ▼
Response → Nginx → Client
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| NSG | Stateful firewall — only inbound rules needed for request/response |
| Priority | Lower number = evaluated first. 100 beats 200. |
| B2s | Burstable VM — good for variable workloads, cheap baseline |
| cloud-init | `custom_data` in Terraform runs bash script on first boot |
| Reverse proxy | Nginx forwards `/api/` requests to backend app on localhost |
| `systemctl enable` | Ensures Nginx starts automatically after VM reboot |
| Static IP | Public IP stays the same even if VM is stopped/started |

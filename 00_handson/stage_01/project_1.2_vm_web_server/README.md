# Project 1.2 — Linux Web Server on Azure VM

## What This Does
Deploys a production-style Linux web server on an Azure VM with Nginx, NSG firewall rules, and a reverse proxy configuration. Demonstrates Azure compute fundamentals and network security.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure Virtual Machine (B2s) | Ubuntu 22.04 LTS compute |
| Azure Network Security Group | Firewall — allow 80, 443, 22 |
| Azure Public IP | Static external IP |
| Azure Virtual Network | Isolated network |
| Nginx | Web server + reverse proxy |

## How to Deploy
```bash
cd terraform
terraform init
terraform apply -auto-approve

# Get public IP
terraform output public_ip

# SSH in
ssh -i ~/.ssh/azure_lab azureuser@<public_ip>

# Nginx is auto-installed via cloud-init
curl http://<public_ip>
```

## Folder Structure
```
project_1.2_vm_web_server/
├── README.md
├── steps.md
├── cost_estimate.md
├── docs/
│   └── architecture.md
├── terraform/
│   └── main.tf
└── code/
    └── setup_nginx.sh
```

## Lessons Learned
- B2s (2 vCPU, 4 GB RAM) handles moderate web traffic comfortably
- NSG rules are evaluated by priority — lower number = higher priority
- `cloud-init` via `custom_data` in Terraform runs on first boot only
- Nginx reverse proxy: `proxy_pass http://localhost:8080` forwards to app
- Always use `systemctl enable nginx` so it restarts after VM reboot
- Azure VM auto-shutdown can be configured to save costs during off-hours
- `az vm run-command invoke` lets you run commands without SSH

## Nginx Configuration
- Port 80: serves static files from `/var/www/html`
- Port 443: HTTPS (requires cert — use Let's Encrypt or Azure App Gateway)
- Reverse proxy: forwards `/api/` to backend app on port 8080

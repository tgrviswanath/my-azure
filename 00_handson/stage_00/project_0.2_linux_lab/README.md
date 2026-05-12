# Project 0.2 — Linux Lab on Azure VM

## What This Does
Provisions an Ubuntu Azure VM and walks through Linux fundamentals: Nginx web server setup, user/permission management, cron job scheduling, and log analysis with journalctl and grep.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure Virtual Machine (B1s) | Ubuntu 22.04 LTS compute |
| Azure Network Security Group | Firewall rules for SSH/HTTP |
| Azure Public IP | External access to the VM |
| Azure Virtual Network | Isolated network for the VM |
| Nginx | Web server running on the VM |

## How to Deploy
```bash
cd terraform
terraform init
terraform apply -auto-approve

# SSH into the VM
ssh -i ~/.ssh/azure_lab azureuser@<public_ip>

# Run setup script
bash scripts/setup_nginx.sh
```

## Folder Structure
```
project_0.2_linux_lab/
├── README.md
├── steps.md
├── cost_estimate.md
├── docs/
│   └── architecture.md
├── terraform/
│   └── main.tf
└── scripts/
    └── setup_nginx.sh
```

## Lessons Learned
- Azure VM B1s (1 vCPU, 1 GB RAM) is sufficient for a basic Nginx lab
- NSG rules are stateful — only need inbound rules for SSH and HTTP
- `cloud-init` via `custom_data` in Terraform automates first-boot setup
- `journalctl -u nginx --since "1 hour ago"` is the Azure-native way to read service logs
- Always use SSH key authentication — never password auth on public VMs
- `az vm deallocate` stops billing for compute (disk still billed)

## Key Linux Commands Practiced
- `systemctl start/stop/status nginx`
- `useradd`, `usermod`, `chmod`, `chown`
- `crontab -e` for scheduled tasks
- `journalctl`, `grep`, `awk`, `tail -f /var/log/nginx/access.log`

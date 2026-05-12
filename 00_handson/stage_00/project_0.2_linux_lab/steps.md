# Steps — Project 0.2 Linux Lab on Azure VM

## Phase 1 — Provision Azure VM

### 1.1 Generate SSH key
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/azure_lab -C "azure-lab-vm"
```

### 1.2 Deploy with Terraform
```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### 1.3 Get the public IP
```bash
terraform output public_ip
```

### 1.4 SSH into the VM
```bash
ssh -i ~/.ssh/azure_lab azureuser@<public_ip>
```

---

## Phase 2 — Install and Configure Nginx

### 2.1 Update packages
```bash
sudo apt update && sudo apt upgrade -y
```

### 2.2 Install Nginx
```bash
sudo apt install nginx -y
sudo systemctl status nginx
```

### 2.3 Test Nginx
```bash
curl http://localhost
# Expected: "Welcome to nginx!"
```

### 2.4 Customize the default page
```bash
echo "<h1>Azure Linux Lab - $(hostname)</h1>" | sudo tee /var/www/html/index.html
curl http://localhost
```

### 2.5 Test from your local machine
```bash
curl http://<public_ip>
```

---

## Phase 3 — User and Permission Management

### 3.1 Create a new user
```bash
sudo useradd -m -s /bin/bash webadmin
sudo passwd webadmin
```

### 3.2 Add user to sudo group
```bash
sudo usermod -aG sudo webadmin
```

### 3.3 Create a web directory for the user
```bash
sudo mkdir -p /var/www/webadmin
sudo chown webadmin:webadmin /var/www/webadmin
sudo chmod 755 /var/www/webadmin
```

### 3.4 Switch to the new user and create a file
```bash
sudo su - webadmin
echo "<h1>WebAdmin Page</h1>" > /var/www/webadmin/index.html
exit
```

### 3.5 Configure Nginx to serve the new directory
```bash
sudo tee /etc/nginx/sites-available/webadmin <<EOF
server {
    listen 8080;
    root /var/www/webadmin;
    index index.html;
}
EOF

sudo ln -s /etc/nginx/sites-available/webadmin /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 3.6 Update NSG to allow port 8080 (via Azure Portal or CLI)
```bash
az network nsg rule create \
  --resource-group azure-linux-lab-rg \
  --nsg-name linux-lab-nsg \
  --name Allow-8080 \
  --priority 120 \
  --source-address-prefixes '*' \
  --destination-port-ranges 8080 \
  --access Allow \
  --protocol Tcp
```

### 3.7 Test
```bash
curl http://<public_ip>:8080
```

---

## Phase 4 — Cron Jobs

### 4.1 Create a backup script
```bash
cat > /home/azureuser/backup_logs.sh <<'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
tar -czf /home/azureuser/backups/nginx_logs_$DATE.tar.gz /var/log/nginx/*.log
find /home/azureuser/backups -name "*.tar.gz" -mtime +7 -delete
EOF

chmod +x /home/azureuser/backup_logs.sh
mkdir -p /home/azureuser/backups
```

### 4.2 Schedule with cron (runs daily at 2 AM)
```bash
crontab -e
# Add this line:
0 2 * * * /home/azureuser/backup_logs.sh
```

### 4.3 Test the script manually
```bash
/home/azureuser/backup_logs.sh
ls -lh /home/azureuser/backups/
```

---

## Phase 5 — Log Analysis

### 5.1 View Nginx service logs
```bash
sudo journalctl -u nginx --since "1 hour ago"
```

### 5.2 Analyze access logs
```bash
sudo tail -f /var/log/nginx/access.log
```

### 5.3 Count requests by IP
```bash
sudo awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -10
```

### 5.4 Find 404 errors
```bash
sudo grep " 404 " /var/log/nginx/access.log
```

### 5.5 Monitor system resources
```bash
htop
# or
top
df -h
free -h
```

---

## Phase 6 — Cleanup

```bash
cd terraform
terraform destroy -auto-approve
```

---

## Screenshots to Take
- [ ] SSH connection to Azure VM
- [ ] Nginx default page in browser
- [ ] Custom webadmin page on port 8080
- [ ] Cron job entry in `crontab -l`
- [ ] Log analysis output showing top IPs

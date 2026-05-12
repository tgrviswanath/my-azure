# Steps — Project 1.2 Linux Web Server on Azure VM

## Phase 1 — Create VM

### 1.1 Generate SSH key (if not already done)
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/azure_lab -C "azure-vm-lab"
```

### 1.2 Deploy with Terraform
```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### 1.3 Get outputs
```bash
terraform output public_ip
terraform output ssh_command
terraform output http_url
```

---

## Phase 2 — SSH Into the VM

### 2.1 Connect via SSH
```bash
ssh -i ~/.ssh/azure_lab azureuser@<public_ip>
```

### 2.2 Verify cloud-init completed
```bash
sudo cloud-init status
sudo cat /var/log/cloud-init-output.log | tail -20
```

### 2.3 Check Nginx is running
```bash
sudo systemctl status nginx
curl http://localhost
```

---

## Phase 3 — Configure Nginx

### 3.1 Run the setup script
```bash
# Upload and run the setup script
scp -i ~/.ssh/azure_lab code/setup_nginx.sh azureuser@<public_ip>:~/
ssh -i ~/.ssh/azure_lab azureuser@<public_ip> "bash ~/setup_nginx.sh"
```

### 3.2 Configure reverse proxy for a backend app
```bash
sudo tee /etc/nginx/sites-available/reverse-proxy <<'EOF'
server {
    listen 80;
    server_name _;

    # Serve static files
    location / {
        root /var/www/html;
        index index.html;
        try_files $uri $uri/ =404;
    }

    # Reverse proxy to backend app
    location /api/ {
        proxy_pass http://localhost:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/reverse-proxy /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

### 3.3 Test the configuration
```bash
sudo nginx -t
# Expected: syntax is ok / test is successful
```

---

## Phase 4 — Configure NSG

### 4.1 View current NSG rules
```bash
az network nsg rule list \
  --resource-group vm-web-server-rg \
  --nsg-name vm-web-nsg \
  --output table
```

### 4.2 Add HTTPS rule
```bash
az network nsg rule create \
  --resource-group vm-web-server-rg \
  --nsg-name vm-web-nsg \
  --name Allow-HTTPS \
  --priority 120 \
  --source-address-prefixes '*' \
  --destination-port-ranges 443 \
  --access Allow \
  --protocol Tcp
```

### 4.3 Restrict SSH to your IP only (security best practice)
```bash
MY_IP=$(curl -s ifconfig.me)
az network nsg rule update \
  --resource-group vm-web-server-rg \
  --nsg-name vm-web-nsg \
  --name Allow-SSH \
  --source-address-prefixes $MY_IP
```

---

## Phase 5 — Test HTTP

### 5.1 Test from local machine
```bash
PUBLIC_IP=$(terraform output -raw public_ip)
curl http://$PUBLIC_IP
curl -I http://$PUBLIC_IP  # Check headers
```

### 5.2 Load test with Apache Bench
```bash
ab -n 1000 -c 10 http://$PUBLIC_IP/
```

### 5.3 Monitor Nginx access logs
```bash
ssh -i ~/.ssh/azure_lab azureuser@$PUBLIC_IP \
  "sudo tail -f /var/log/nginx/access.log"
```

---

## Phase 6 — Auto-Shutdown (Cost Saving)

```bash
az vm auto-shutdown \
  --resource-group vm-web-server-rg \
  --name vm-web-server \
  --time 2200 \
  --email "your-email@example.com"
```

---

## Phase 7 — Cleanup

```bash
cd terraform
terraform destroy -auto-approve
```

---

## Screenshots to Take
- [ ] SSH connection to VM
- [ ] Nginx status: active (running)
- [ ] Website loading in browser via public IP
- [ ] NSG rules showing 80/443/22 allowed
- [ ] Nginx access log showing requests

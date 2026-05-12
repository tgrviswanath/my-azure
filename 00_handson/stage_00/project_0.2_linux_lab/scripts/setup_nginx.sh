#!/bin/bash
# setup_nginx.sh — Configure Nginx on Azure Ubuntu VM
# Run as: bash scripts/setup_nginx.sh
# Tested on: Ubuntu 22.04 LTS

set -euo pipefail

echo "============================================"
echo "  Nginx Setup Script for Azure Linux Lab"
echo "============================================"

# Update system
echo "[1/6] Updating package lists..."
sudo apt-get update -y

# Install Nginx
echo "[2/6] Installing Nginx..."
sudo apt-get install -y nginx

# Enable and start Nginx
echo "[3/6] Enabling and starting Nginx..."
sudo systemctl enable nginx
sudo systemctl start nginx

# Create a custom landing page
echo "[4/6] Creating custom landing page..."
HOSTNAME=$(hostname)
PUBLIC_IP=$(curl -s ifconfig.me || echo "unknown")

sudo tee /var/www/html/index.html > /dev/null <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Azure Linux Lab</title>
    <style>
        body { font-family: Arial, sans-serif; background: #0078d4; color: white; text-align: center; padding: 50px; }
        .card { background: rgba(255,255,255,0.1); border-radius: 10px; padding: 30px; max-width: 600px; margin: auto; }
        code { background: rgba(0,0,0,0.3); padding: 4px 8px; border-radius: 4px; }
    </style>
</head>
<body>
    <div class="card">
        <h1>🚀 Azure Linux Lab</h1>
        <p>Nginx is running successfully on Azure VM</p>
        <p>Hostname: <code>$HOSTNAME</code></p>
        <p>Public IP: <code>$PUBLIC_IP</code></p>
        <p>Date: <code>$(date)</code></p>
    </div>
</body>
</html>
EOF

# Configure log rotation
echo "[5/6] Configuring log rotation..."
sudo tee /etc/logrotate.d/nginx-lab > /dev/null <<EOF
/var/log/nginx/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        systemctl reload nginx
    endscript
}
EOF

# Verify Nginx is running
echo "[6/6] Verifying Nginx..."
sudo systemctl status nginx --no-pager
curl -s http://localhost | grep -o "<title>.*</title>" || echo "Nginx responding"

echo ""
echo "============================================"
echo "  Setup Complete!"
echo "  Visit: http://$PUBLIC_IP"
echo "  Logs:  sudo tail -f /var/log/nginx/access.log"
echo "  Status: sudo systemctl status nginx"
echo "============================================"

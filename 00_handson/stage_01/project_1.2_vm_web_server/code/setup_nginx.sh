#!/bin/bash
# setup_nginx.sh — Full Nginx web server setup for Azure VM
# Installs Nginx, configures reverse proxy, sets up SSL-ready config
#
# Run: bash code/setup_nginx.sh
# Tested on: Ubuntu 22.04 LTS (Azure VM B2s)

set -euo pipefail

echo "============================================"
echo "  Nginx Web Server Setup — Azure VM"
echo "============================================"

# 1. Update and install
echo "[1/7] Installing Nginx..."
sudo apt-get update -y
sudo apt-get install -y nginx curl

# 2. Enable and start
echo "[2/7] Enabling Nginx service..."
sudo systemctl enable nginx
sudo systemctl start nginx

# 3. Get public IP
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)

# 4. Create main landing page
echo "[3/7] Creating landing page..."
sudo tee /var/www/html/index.html > /dev/null <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Azure VM Web Server</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; background: #0078d4;
               color: white; text-align: center; padding: 60px 20px; }
        .card { background: rgba(255,255,255,0.15); border-radius: 12px;
                padding: 40px; max-width: 600px; margin: auto; }
        code { background: rgba(0,0,0,0.3); padding: 3px 8px; border-radius: 4px; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        td { padding: 8px 12px; border-bottom: 1px solid rgba(255,255,255,0.2); }
        td:first-child { text-align: left; opacity: 0.8; }
        td:last-child { text-align: right; font-weight: bold; }
    </style>
</head>
<body>
    <div class="card">
        <h1>🚀 Azure VM Web Server</h1>
        <p>Nginx is running successfully</p>
        <table>
            <tr><td>Hostname</td><td><code>$HOSTNAME</code></td></tr>
            <tr><td>Public IP</td><td><code>$PUBLIC_IP</code></td></tr>
            <tr><td>OS</td><td><code>Ubuntu 22.04 LTS</code></td></tr>
            <tr><td>VM Size</td><td><code>Standard_B2s</code></td></tr>
            <tr><td>Web Server</td><td><code>Nginx</code></td></tr>
        </table>
    </div>
</body>
</html>
EOF

# 5. Configure Nginx with reverse proxy
echo "[4/7] Configuring Nginx reverse proxy..."
sudo tee /etc/nginx/sites-available/default > /dev/null <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html;
    server_name _;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";

    # Gzip compression
    gzip on;
    gzip_types text/html text/css application/javascript application/json;

    # Static files
    location / {
        try_files $uri $uri/ =404;
    }

    # Reverse proxy to backend app
    location /api/ {
        proxy_pass http://localhost:8080/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # Health check endpoint
    location /health {
        return 200 '{"status":"ok","server":"nginx"}';
        add_header Content-Type application/json;
    }
}
NGINX

# 6. Test and reload
echo "[5/7] Testing Nginx configuration..."
sudo nginx -t

echo "[6/7] Reloading Nginx..."
sudo systemctl reload nginx

# 7. Configure log rotation
echo "[7/7] Setting up log rotation..."
sudo tee /etc/logrotate.d/nginx-vm > /dev/null <<'EOF'
/var/log/nginx/*.log {
    daily
    missingok
    rotate 14
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

# Final status
echo ""
sudo systemctl status nginx --no-pager -l
echo ""
echo "============================================"
echo "  Setup Complete!"
echo ""
echo "  Website:      http://$PUBLIC_IP"
echo "  Health check: http://$PUBLIC_IP/health"
echo "  API proxy:    http://$PUBLIC_IP/api/"
echo ""
echo "  Logs: sudo tail -f /var/log/nginx/access.log"
echo "============================================"

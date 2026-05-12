#!/bin/bash
# setup.sh — Linux Foundations Lab setup script

set -e

echo "=== Updating packages ==="
sudo apt update && sudo apt upgrade -y

echo "=== Installing tools ==="
sudo apt install -y nginx htop curl wget git unzip net-tools

echo "=== Configuring Nginx ==="
sudo systemctl start nginx
sudo systemctl enable nginx

echo "=== Creating lab user ==="
sudo useradd -m -s /bin/bash labuser 2>/dev/null || echo "User already exists"
sudo mkdir -p /home/labuser/.ssh
sudo chmod 700 /home/labuser/.ssh

echo "=== Setting up cron example ==="
(crontab -l 2>/dev/null; echo "*/5 * * * * echo 'health check' >> /tmp/health.log") | crontab -

echo "=== Setup complete ==="
echo "Nginx status:"
sudo systemctl status nginx --no-pager

#!/bin/bash

# UrBackup Docker Compose Fix for Ubuntu 24.04
# Fixes "ModuleNotFoundError: No module named 'distutils'" error

set -e

echo "🔧 UrBackup Docker Compose Fix for Ubuntu 24.04"
echo "================================================="

# Check if we're in the right directory
if [[ ! -f "docker-compose.yml" ]]; then
    echo "❌ docker-compose.yml not found in current directory"
    echo "Please run this script from your UrBackup installation directory"
    echo "Example: cd /home/urbackup/urbackup-docker && bash fix.sh"
    exit 1
fi

echo "✅ Found docker-compose.yml"

# Stop current containers if running
echo "🛑 Stopping current containers..."
sudo docker-compose down 2>/dev/null || echo "No containers were running"

# Remove old docker-compose
echo "🗑️  Removing old docker-compose..."
sudo apt remove -y docker-compose 2>/dev/null || true
sudo rm -f /usr/local/bin/docker-compose 2>/dev/null || true

# Install distutils as fallback
echo "📦 Installing python3-distutils..."
sudo apt update
sudo apt install -y python3-distutils

# Install Docker Compose plugin
echo "🐳 Installing Docker Compose plugin..."
sudo apt install -y docker-compose-plugin

# Test Docker Compose plugin
echo "🧪 Testing Docker Compose..."
if docker compose version; then
    echo "✅ Docker Compose plugin working!"
else
    echo "❌ Docker Compose plugin not working. Trying alternative..."
    # Try installing via Docker CLI plugin
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    if docker-compose version; then
        echo "✅ Alternative docker-compose working!"
        USE_LEGACY=true
    else
        echo "❌ Unable to fix Docker Compose. Please reinstall Docker completely."
        exit 1
    fi
fi

# Start UrBackup with correct command
echo "🚀 Starting UrBackup server..."
if [[ "$USE_LEGACY" == "true" ]]; then
    sudo docker-compose up -d
else
    sudo docker compose up -d
fi

# Wait a bit for startup
sleep 10

# Check status
echo "📊 Checking status..."
if [[ "$USE_LEGACY" == "true" ]]; then
    sudo docker-compose ps
else
    sudo docker compose ps
fi

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

echo
echo "🎉 Fix completed successfully!"
echo "================================"
echo "UrBackup Web Interface: http://$SERVER_IP:55414"
echo
echo "Use these commands going forward:"
if [[ "$USE_LEGACY" == "true" ]]; then
    echo "  docker-compose up -d      # start"
    echo "  docker-compose down       # stop"
    echo "  docker-compose ps         # status"
    echo "  docker-compose logs -f    # logs"
else
    echo "  docker compose up -d      # start (note the space!)"
    echo "  docker compose down       # stop"
    echo "  docker compose ps         # status"  
    echo "  docker compose logs -f    # logs"
fi
echo

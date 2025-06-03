#!/bin/bash

# Quick Fix for Docker Compose issue in Ubuntu 24.04
# Run this if you get "ModuleNotFoundError: No module named 'distutils'"

set -e

echo "🔧 Fixing Docker Compose distutils issue..."

# Remove old docker-compose
echo "Removing old docker-compose..."
sudo apt remove -y docker-compose 2>/dev/null || true
sudo rm -f /usr/local/bin/docker-compose 2>/dev/null || true

# Install distutils if needed (fallback)
echo "Installing python3-distutils and required packages..."
sudo apt update
sudo apt install -y python3-distutils curl wget gpg ca-certificates 2>/dev/null || true

# Make sure docker-compose-plugin is installed
echo "Installing Docker Compose plugin..."
sudo apt install -y docker-compose-plugin

# Test new Docker Compose
echo "Testing Docker Compose..."
if docker compose version; then
    echo "✅ Docker Compose plugin working!"
else
    echo "❌ Still having issues. Please reinstall Docker completely."
    exit 1
fi

# Fix existing docker-compose.yml files to use new syntax
if [[ -f "docker-compose.yml" ]]; then
    echo "Found docker-compose.yml in current directory"
    echo "You can now use: docker compose up -d (note the space)"
    echo "Instead of: docker-compose up -d"
fi

echo "🎉 Fix completed! Use 'docker compose' (with space) instead of 'docker-compose'"

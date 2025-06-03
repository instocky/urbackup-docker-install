#!/bin/bash

# UrBackup Docker Quick Installer
# One-liner installation for Ubuntu

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}UrBackup Docker Quick Installer${NC}"
echo "======================================"

# Basic checks
if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}Error: Don't run as root!${NC}"
    exit 1
fi

# Install Docker if needed
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Installing Docker...${NC}"
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
fi

# Install Docker Compose Plugin if needed  
if ! docker compose version &> /dev/null; then
    echo -e "${YELLOW}Installing Docker Compose Plugin...${NC}"
    sudo apt update && sudo apt install -y docker-compose-plugin
    # Remove old docker-compose
    sudo apt remove -y docker-compose 2>/dev/null || true
    sudo rm -f /usr/local/bin/docker-compose 2>/dev/null || true
fi

# Create working directory
INSTALL_DIR="$HOME/urbackup-docker"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create directory structure
mkdir -p urbackup/{backups,database,config}

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  urbackup-server:
    image: uroni/urbackup-server:latest
    container_name: urbackup-server
    restart: unless-stopped
    ports:
      - "55413:55413"
      - "55414:55414" 
      - "35623:35623"
    volumes:
      - ./urbackup/backups:/var/urbackup:rw
      - ./urbackup/database:/var/lib/urbackup:rw
      - ./urbackup/config:/etc/urbackup:rw
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Moscow
EOF

# Create management script
cat > urbackup.sh << 'EOF'
#!/bin/bash
case "$1" in
    start) docker compose up -d ;;
    stop) docker compose down ;;
    restart) docker compose restart ;;
    status) docker compose ps ;;
    logs) docker compose logs -f ;;
    *) echo "Usage: $0 {start|stop|restart|status|logs}" ;;
esac
EOF

chmod +x urbackup.sh

# Start UrBackup
echo -e "${YELLOW}Starting UrBackup...${NC}"
if docker ps &> /dev/null; then
    docker compose up -d
else
    sudo docker compose up -d
fi

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

echo
echo -e "${GREEN}✅ UrBackup installed successfully!${NC}"
echo "======================================"
echo -e "Web Interface: ${BLUE}http://$SERVER_IP:55414${NC}"
echo -e "Working Directory: ${BLUE}$INSTALL_DIR${NC}"
echo
echo "Management commands:"
echo "  cd $INSTALL_DIR"
echo "  ./urbackup.sh start|stop|restart|status|logs"
echo

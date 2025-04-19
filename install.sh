#!/bin/bash

# Colors for pretty output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print header
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}     OpenVPN Provision Service Installer     ${NC}"
echo -e "${GREEN}==============================================${NC}"

# Check if running with sudo/root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root or with sudo${NC}"
  exit 1
fi

echo -e "${YELLOW}Checking system requirements...${NC}"

# Install necessary system tools
echo -e "${YELLOW}Installing required system packages...${NC}"
apt-get update -qq && apt-get install -y -qq lsof curl

# Check for Docker and Docker Compose
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker not found. Installing Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    echo -e "${GREEN}Docker installed successfully${NC}"
else
    echo -e "${GREEN}Docker is already installed${NC}"
fi

# Check Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo -e "${YELLOW}Docker Compose not found. Installing Docker Compose...${NC}"

    # Install Docker Compose v2
    apt-get install -y docker-compose-plugin

    # Create symbolic link for docker-compose command
    ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    echo -e "${GREEN}Docker Compose installed successfully${NC}"

    # Verify docker-compose is working
    docker-compose --version || {
        echo -e "${YELLOW}Docker Compose plugin installed but command not found. Installing standalone version...${NC}"
        curl -SL "https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-linux-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        echo -e "${GREEN}Docker Compose standalone version installed${NC}"
    }
else
    echo -e "${GREEN}Docker Compose is already installed${NC}"
fi

# Create directories
echo -e "${YELLOW}Creating necessary directories...${NC}"
mkdir -p ./templates
mkdir -p ./static

# Check if port 8100 is available
if command -v lsof &> /dev/null; then
    if lsof -Pi :8100 -sTCP:LISTEN -t >/dev/null ; then
        echo -e "${RED}Port 8100 is already in use. Please free up this port or modify docker-compose.yml to use a different port.${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}lsof not available, skipping port check${NC}"
fi

# Add current user to docker group
if [ -z "$SUDO_USER" ]; then
    current_user=$(whoami)
else
    current_user=$SUDO_USER
fi

if [ "$current_user" != "root" ]; then
    echo -e "${YELLOW}Adding user ${current_user} to docker group...${NC}"
    usermod -aG docker $current_user
    echo -e "${GREEN}User added to docker group. You may need to log out and back in for this to take effect.${NC}"
fi

# Determine which docker compose command to use
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
    # Create a compatibility alias
    echo -e "#!/bin/bash\ndocker compose \"\$@\"" > /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}Created docker-compose compatibility script${NC}"
else
    echo -e "${RED}Neither docker-compose nor docker compose is available.${NC}"
    echo -e "${RED}Something went wrong with Docker Compose installation.${NC}"
    exit 1
fi

# Start the services
echo -e "${YELLOW}Starting the OpenVPN Provision Service...${NC}"
$DOCKER_COMPOSE down 2>/dev/null || true
$DOCKER_COMPOSE up -d

# Check if services are running
if [ $? -eq 0 ]; then
    echo -e "${GREEN}OpenVPN Provision Service is now running!${NC}"
    echo -e "${GREEN}==============================================${NC}"
    echo -e "${GREEN}The service is available at: http://localhost:8100${NC}"
    echo -e "${GREEN}OpenVPN management interface on port 1194${NC}"
    echo -e "${GREEN}Redis is running on port 6378${NC}"
    echo -e "${GREEN}==============================================${NC}"
    echo -e "${YELLOW}To stop the service:${NC} $DOCKER_COMPOSE down"
    echo -e "${YELLOW}To view logs:${NC} $DOCKER_COMPOSE logs -f"
else
    echo -e "${RED}Failed to start the service. Please check the logs with '$DOCKER_COMPOSE logs'${NC}"
fi

# Create a helper script to manage the service
cat > manage.sh << 'EOF'
#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Determine which docker compose command to use
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    echo -e "${RED}Neither docker-compose nor docker compose is available.${NC}"
    echo -e "${RED}Please make sure Docker Compose is installed.${NC}"
    exit 1
fi

case "$1" in
    start)
        echo -e "${YELLOW}Starting OpenVPN Provision Service...${NC}"
        $DOCKER_COMPOSE up -d
        ;;
    stop)
        echo -e "${YELLOW}Stopping OpenVPN Provision Service...${NC}"
        $DOCKER_COMPOSE down
        ;;
    restart)
        echo -e "${YELLOW}Restarting OpenVPN Provision Service...${NC}"
        $DOCKER_COMPOSE down
        $DOCKER_COMPOSE up -d
        ;;
    status)
        echo -e "${YELLOW}Service status:${NC}"
        $DOCKER_COMPOSE ps
        ;;
    logs)
        echo -e "${YELLOW}Showing logs (Ctrl+C to exit):${NC}"
        $DOCKER_COMPOSE logs -f
        ;;
    *)
        echo -e "${YELLOW}Usage:${NC} ./manage.sh {start|stop|restart|status|logs}"
        exit 1
esac
EOF

chmod +x manage.sh
chmod +x redis_test.py

# Install python-redis for the test script
echo -e "${YELLOW}Installing Python Redis package...${NC}"
if [ -f /etc/debian_version ]; then
    # Debian-based system - use apt
    apt-get install -y python3-redis
else
    # Non-Debian system - try pip
    apt-get install -y python3-pip
    pip3 install redis --break-system-packages
fi

echo -e "${GREEN}A management script has been created: ./manage.sh${NC}"
echo -e "${YELLOW}Usage:${NC} ./manage.sh {start|stop|restart|status|logs}"
echo -e "${GREEN}A Redis test script has been created: ./redis_test.py${NC}"
echo -e "${YELLOW}Usage:${NC} ./redis_test.py [host] [port]"

# Verify Docker status
echo -e "\n${YELLOW}Verifying Docker status:${NC}"
docker ps

# Check if docker-compose is working
echo -e "\n${YELLOW}Verifying docker-compose:${NC}"
if command -v docker-compose &> /dev/null; then
    docker-compose version
    echo -e "${GREEN}Docker Compose is available${NC}"
else
    echo -e "${RED}Docker Compose command not found. You may need to use 'docker compose' (with a space) instead.${NC}"
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        echo -e "${GREEN}Docker Compose plugin is available.${NC}"
        echo -e "${YELLOW}Use 'docker compose' instead of 'docker-compose'${NC}"

        # Create an alias script for compatibility
        echo -e "#!/bin/bash\ndocker compose \"\$@\"" > /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        echo -e "${GREEN}Created docker-compose compatibility script${NC}"
    fi
fi

echo -e "\n${GREEN}Installation complete!${NC}"
echo -e "${YELLOW}If you encounter any issues, please run:${NC}"
echo -e "  ./redis_test.py  # To test Redis connectivity"
echo -e "  docker ps        # To check container status"
echo -e "  ./manage.sh status  # To check service status"
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
    
    # Install Docker Compose v2 through the plugin system
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -SL https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    
    echo -e "${GREEN}Docker Compose installed successfully${NC}"
else
    echo -e "${GREEN}Docker Compose is already installed${NC}"
fi

# Create directories
echo -e "${YELLOW}Creating necessary directories...${NC}"
mkdir -p ./templates
mkdir -p ./static

# Check if port 8100 is available
if lsof -Pi :8100 -sTCP:LISTEN -t >/dev/null ; then
    echo -e "${RED}Port 8100 is already in use. Please free up this port or modify docker-compose.yml to use a different port.${NC}"
    exit 1
fi

# Start the services
echo -e "${YELLOW}Starting the OpenVPN Provision Service...${NC}"
docker-compose down
docker-compose up -d

# Check if services are running
if [ $? -eq 0 ]; then
    echo -e "${GREEN}OpenVPN Provision Service is now running!${NC}"
    echo -e "${GREEN}==============================================${NC}"
    echo -e "${GREEN}The service is available at: http://localhost:8100${NC}"
    echo -e "${GREEN}OpenVPN management interface on port 1194${NC}"
    echo -e "${GREEN}Redis is running on port 6378${NC}"
    echo -e "${GREEN}==============================================${NC}"
    echo -e "${YELLOW}To stop the service:${NC} docker-compose down"
    echo -e "${YELLOW}To view logs:${NC} docker-compose logs -f"
else
    echo -e "${RED}Failed to start the service. Please check the logs with 'docker-compose logs'${NC}"
fi

# Create a helper script to manage the service
cat > manage.sh << 'EOF'
#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

case "$1" in
    start)
        echo -e "${YELLOW}Starting OpenVPN Provision Service...${NC}"
        docker-compose up -d
        ;;
    stop)
        echo -e "${YELLOW}Stopping OpenVPN Provision Service...${NC}"
        docker-compose down
        ;;
    restart)
        echo -e "${YELLOW}Restarting OpenVPN Provision Service...${NC}"
        docker-compose down
        docker-compose up -d
        ;;
    status)
        echo -e "${YELLOW}Service status:${NC}"
        docker-compose ps
        ;;
    logs)
        echo -e "${YELLOW}Showing logs (Ctrl+C to exit):${NC}"
        docker-compose logs -f
        ;;
    *)
        echo -e "${YELLOW}Usage:${NC} ./manage.sh {start|stop|restart|status|logs}"
        exit 1
esac
EOF

chmod +x manage.sh
chmod +x redis_test.py

echo -e "${GREEN}A management script has been created: ./manage.sh${NC}"
echo -e "${YELLOW}Usage:${NC} ./manage.sh {start|stop|restart|status|logs}"
echo -e "${GREEN}A Redis test script has been created: ./redis_test.py${NC}"
echo -e "${YELLOW}Usage:${NC} ./redis_test.py [host] [port]"
echo -e "${GREEN}Installation complete!${NC}" 
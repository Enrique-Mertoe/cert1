#!/bin/bash

# Colors for pretty output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

# Function to check and stop existing services
check_and_stop_services() {
    echo -e "\n${YELLOW}Checking for existing services...${NC}"

    # Check if containers with our service names exist
    if docker ps -a | grep -E 'web|redis|celery_worker|openvpn' > /dev/null; then
        echo -e "${RED}Existing Docker containers found that may be related to this project:${NC}"
        docker ps -a | grep -E 'web|redis|celery_worker|openvpn'

        echo -e "\n${RED}WARNING: Continuing will stop and remove these containers!${NC}"
        read -p "Are you sure you want to continue? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Installation cancelled.${NC}"
            exit 1
        fi

        echo -e "${YELLOW}Stopping and removing existing containers...${NC}"
        docker ps -a -q --filter name=web --filter name=redis --filter name=celery_worker --filter name=openvpn | xargs -r docker stop
        docker ps -a -q --filter name=web --filter name=redis --filter name=celery_worker --filter name=openvpn | xargs -r docker rm
    else
        echo -e "${GREEN}No existing containers found that match this project.${NC}"
    fi

    # Check for existing Docker volumes
    if docker volume ls | grep -E 'openvpn_client|hotspot_templates|openvpn_easyrsa' > /dev/null; then
        echo -e "${RED}Existing Docker volumes found that may be related to this project:${NC}"
        docker volume ls | grep -E 'openvpn_client|hotspot_templates|openvpn_easyrsa'

        echo -e "\n${RED}WARNING: Continuing will remove these volumes and ALL DATA stored in them!${NC}"
        read -p "Are you sure you want to continue? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Installation cancelled.${NC}"
            exit 1
        fi

        echo -e "${YELLOW}Removing existing volumes...${NC}"
        docker volume rm $(docker volume ls -q --filter name=openvpn_client --filter name=hotspot_templates --filter name=openvpn_easyrsa) 2>/dev/null || true
    else
        echo -e "${GREEN}No existing volumes found that match this project.${NC}"
    fi

    # Check for processes using port 8100
    if command -v lsof &> /dev/null; then
        if lsof -Pi :8100 -sTCP:LISTEN > /dev/null; then
            echo -e "${RED}Port 8100 is already in use by the following process:${NC}"
            lsof -Pi :8100 -sTCP:LISTEN

            echo -e "\n${RED}WARNING: Continuing will attempt to stop the process using port 8100!${NC}"
            read -p "Are you sure you want to continue? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}Installation cancelled.${NC}"
                exit 1
            fi

            echo -e "${YELLOW}Attempting to free port 8100...${NC}"
            PID=$(lsof -Pi :8100 -sTCP:LISTEN -t)
            if [ ! -z "$PID" ]; then
                echo -e "${YELLOW}Stopping process with PID $PID...${NC}"
                kill -15 $PID 2>/dev/null || true
                sleep 2
                # Check if it's still running and force kill if needed
                if lsof -Pi :8100 -sTCP:LISTEN > /dev/null; then
                    echo -e "${YELLOW}Process still running, attempting force kill...${NC}"
                    kill -9 $PID 2>/dev/null || true
                    sleep 1
                fi
            fi

            # Final check
            if lsof -Pi :8100 -sTCP:LISTEN > /dev/null; then
                echo -e "${RED}Failed to free port 8100. Please manually stop the process using this port or modify docker-compose.yml to use a different port.${NC}"
                exit 1
            else
                echo -e "${GREEN}Successfully freed port 8100.${NC}"
            fi
        fi
    fi
}

# Ask for confirmation before proceeding
echo -e "\n${BLUE}===== IMPORTANT NOTICE =====${NC}"
echo -e "${RED}This installation script will:${NC}"
echo -e "  1. ${RED}Stop and remove any existing Docker containers related to this project${NC}"
echo -e "  2. ${RED}Remove any existing Docker volumes related to this project (WILL DELETE DATA)${NC}"
echo -e "  3. ${RED}Free port 8100 if it's in use (will stop the using process)${NC}"
echo -e "  4. ${RED}Install or reconfigure Docker and Docker Compose${NC}"
echo -e "  5. ${RED}Create new configurations and start services${NC}"
echo -e "${BLUE}===========================${NC}\n"

read -p "Do you want to proceed with the installation? (yes/no): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}Installation cancelled.${NC}"
    exit 1
fi

# Check and stop existing services
check_and_stop_services

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

# Clean any existing Docker resources
echo -e "${YELLOW}Cleaning existing Docker resources...${NC}"
$DOCKER_COMPOSE down -v 2>/dev/null || true

# Start the services
echo -e "${YELLOW}Starting the OpenVPN Provision Service...${NC}"
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
    clean)
        echo -e "${RED}WARNING: This will remove all containers, volumes, and data!${NC}"
        read -p "Are you sure you want to continue? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Stopping and removing all containers and volumes...${NC}"
            $DOCKER_COMPOSE down -v
            echo -e "${GREEN}Clean completed.${NC}"
        else
            echo -e "${YELLOW}Clean operation cancelled.${NC}"
        fi
        ;;
    *)
        echo -e "${YELLOW}Usage:${NC} ./manage.sh {start|stop|restart|status|logs|clean}"
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
echo -e "${YELLOW}Management commands:${NC}"
echo -e "  ${GREEN}./manage.sh start${NC}     # Start services"
echo -e "  ${GREEN}./manage.sh stop${NC}      # Stop services"
echo -e "  ${GREEN}./manage.sh restart${NC}   # Restart services"
echo -e "  ${GREEN}./manage.sh status${NC}    # Check service status"
echo -e "  ${GREEN}./manage.sh logs${NC}      # View logs"
echo -e "  ${GREEN}./manage.sh clean${NC}     # Remove all containers, volumes and data"
echo -e "\n${YELLOW}Troubleshooting:${NC}"
echo -e "  ${GREEN}./redis_test.py${NC}       # Test Redis connectivity"
echo -e "  ${GREEN}docker ps${NC}             # Check container status"
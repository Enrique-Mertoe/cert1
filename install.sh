#!/bin/bash

# Colors for pretty output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
UPDATE_MODE=false
HELP_MODE=false

# Process command line arguments
for arg in "$@"; do
    case $arg in
        --update|-u)
            UPDATE_MODE=true
            shift
            ;;
        --help|-h)
            HELP_MODE=true
            shift
            ;;
        *)
            # Unknown option
            echo -e "${RED}Unknown option: $arg${NC}"
            HELP_MODE=true
            shift
            ;;
    esac
done

# Show help information
if [ "$HELP_MODE" = true ]; then
    echo -e "${GREEN}==============================================${NC}"
    echo -e "${GREEN}     OpenVPN Provision Service Installer     ${NC}"
    echo -e "${GREEN}==============================================${NC}"
    echo -e "\nUsage: $0 [OPTIONS]"
    echo -e "\nOptions:"
    echo -e "  --update, -u    Update mode: only rebuild containers without reinstalling dependencies"
    echo -e "  --help, -h      Show this help message"
    echo -e "\nExamples:"
    echo -e "  $0              Full installation"
    echo -e "  $0 --update     Update code only (useful after git pull)"
    exit 0
fi

# Print header
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}     OpenVPN Provision Service Installer     ${NC}"
if [ "$UPDATE_MODE" = true ]; then
    echo -e "${GREEN}              UPDATE MODE                    ${NC}"
fi
echo -e "${GREEN}==============================================${NC}"

# Check if running with sudo/root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root or with sudo${NC}"
  exit 1
fi

# Function to check for existing services and report without prompting
check_existing_services() {
    echo -e "\n${YELLOW}Checking for existing services...${NC}"

    # Check if containers with our service names exist
    if docker ps -a | grep -E 'web|redis|celery_worker|openvpn' > /dev/null; then
        echo -e "${RED}Existing Docker containers found that will be stopped and removed:${NC}"
        docker ps -a | grep -E 'web|redis|celery_worker|openvpn'
    else
        echo -e "${GREEN}No existing containers found that match this project.${NC}"
    fi

    # Check for existing Docker volumes
    if docker volume ls | grep -E 'openvpn_client|hotspot_templates|openvpn_easyrsa' > /dev/null; then
        echo -e "${RED}Existing Docker volumes found that will be removed:${NC}"
        docker volume ls | grep -E 'openvpn_client|hotspot_templates|openvpn_easyrsa'
    else
        echo -e "${GREEN}No existing volumes found that match this project.${NC}"
    fi

    # Check for processes using port 8100
    if command -v lsof &> /dev/null; then
        if lsof -Pi :8100 -sTCP:LISTEN > /dev/null; then
            echo -e "${RED}Port 8100 is already in use by the following process:${NC}"
            lsof -Pi :8100 -sTCP:LISTEN
            echo -e "${RED}This process will be stopped.${NC}"
        fi
    fi
}

# Function to stop existing services and clean up resources
clean_existing_services() {
    echo -e "\n${YELLOW}Cleaning up existing services...${NC}"

    # Stop and remove containers
    echo -e "${YELLOW}Stopping and removing any existing containers...${NC}"
    docker ps -a -q --filter name=web --filter name=redis --filter name=celery_worker --filter name=openvpn | xargs -r docker stop 2>/dev/null || true
    docker ps -a -q --filter name=web --filter name=redis --filter name=celery_worker --filter name=openvpn | xargs -r docker rm 2>/dev/null || true

    # Remove volumes if not in update mode
    if [ "$UPDATE_MODE" = false ]; then
        echo -e "${YELLOW}Removing any existing volumes...${NC}"
        docker volume ls -q --filter name=openvpn_client --filter name=hotspot_templates --filter name=openvpn_easyrsa | xargs -r docker volume rm 2>/dev/null || true
    else
        echo -e "${GREEN}Update mode: Preserving existing volumes and data${NC}"
    fi

    # Free port 8100 if needed
    if command -v lsof &> /dev/null; then
        if lsof -Pi :8100 -sTCP:LISTEN > /dev/null; then
            echo -e "${YELLOW}Freeing port 8100...${NC}"
            PID=$(lsof -Pi :8100 -sTCP:LISTEN -t)
            if [ ! -z "$PID" ]; then
                echo -e "${YELLOW}Stopping process with PID $PID...${NC}"
                kill -15 $PID 2>/dev/null || kill -9 $PID 2>/dev/null || true
                sleep 2
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

if [ "$UPDATE_MODE" = true ]; then
    # Update mode - simplified confirmation and process
    echo -e "\n${BLUE}===== UPDATE MODE =====${NC}"
    echo -e "${YELLOW}This will:${NC}"
    echo -e "  1. ${YELLOW}Stop existing containers${NC}"
    echo -e "  2. ${GREEN}Preserve existing volumes and data${NC}"
    echo -e "  3. ${YELLOW}Rebuild containers with the latest code${NC}"
    echo -e "${BLUE}======================${NC}"

    # Check for existing containers only
    if docker ps -a | grep -E 'web|redis|celery_worker|openvpn' > /dev/null; then
        echo -e "${YELLOW}Existing Docker containers found that will be stopped and rebuilt:${NC}"
        docker ps -a | grep -E 'web|redis|celery_worker|openvpn'
    else
        echo -e "${GREEN}No existing containers found that match this project.${NC}"
    fi

    read -p "Continue with the update? (yes/no): " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${YELLOW}Update cancelled.${NC}"
        exit 1
    fi

    # Stop containers but preserve volumes
    echo -e "${YELLOW}Stopping existing containers...${NC}"
    docker ps -a -q --filter name=web --filter name=redis --filter name=celery_worker --filter name=openvpn | xargs -r docker stop 2>/dev/null || true
    docker ps -a -q --filter name=web --filter name=redis --filter name=celery_worker --filter name=openvpn | xargs -r docker rm 2>/dev/null || true

    # Determine which docker compose command to use
    if command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    else
        echo -e "${RED}Neither docker-compose nor docker compose is available.${NC}"
        echo -e "${RED}Please run the installer without the update flag first.${NC}"
        exit 1
    fi

    # Build and start the services
    echo -e "${YELLOW}Rebuilding containers with latest code...${NC}"
    $DOCKER_COMPOSE build --no-cache
    $DOCKER_COMPOSE up -d

    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}Update completed successfully!${NC}"
        echo -e "${GREEN}Services have been rebuilt and restarted.${NC}"
        echo -e "${GREEN}The service is available at: http://localhost:8100${NC}"

        # Start services using manage.sh
        echo -e "\n${YELLOW}Starting services with manage.sh...${NC}"
        ./manage.sh start

        # Show service status
        echo -e "\n${YELLOW}Current service status:${NC}"
        ./manage.sh status
    else
        echo -e "\n${RED}Failed to update services.${NC}"
        echo -e "${YELLOW}Check the logs with:${NC} $DOCKER_COMPOSE logs"
        exit 1
    fi

    exit 0
fi

# Full installation mode from here
# Ask for a single confirmation before proceeding
echo -e "\n${BLUE}===== IMPORTANT NOTICE =====${NC}"
echo -e "${RED}This installation script will:${NC}"
echo -e "  1. ${RED}Stop and remove any existing Docker containers related to this project${NC}"
echo -e "  2. ${RED}Remove any existing Docker volumes related to this project (WILL DELETE DATA)${NC}"
echo -e "  3. ${RED}Free port 8100 if it's in use (will stop the using process)${NC}"
echo -e "  4. ${RED}Install or reconfigure Docker and Docker Compose${NC}"
echo -e "  5. ${RED}Create new configurations and start services${NC}"
echo -e "${BLUE}===========================${NC}"

# Check and show what will be affected
check_existing_services

echo -e "\n${RED}WARNING: All the above components will be affected without further confirmation.${NC}"
echo -e "${YELLOW}TIP: Use --update flag for a lighter update after code changes (preserves data).${NC}"
read -p "Do you want to proceed with the installation? (yes/no): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}Installation cancelled.${NC}"
    exit 1
fi

# Clean up existing services without further prompts
clean_existing_services

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
    echo -e "${GREEN}Redis is running on port 6379${NC}"
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
    rebuild)
        echo -e "${YELLOW}Rebuilding and restarting services (preserves data)...${NC}"
        $DOCKER_COMPOSE down
        $DOCKER_COMPOSE build --no-cache
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
        echo -e "${YELLOW}Usage:${NC} ./manage.sh {start|stop|restart|rebuild|status|logs|clean}"
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
echo -e "  ${GREEN}./manage.sh rebuild${NC}   # Rebuild containers with latest code (keeps data)"
echo -e "  ${GREEN}./manage.sh status${NC}    # Check service status"
echo -e "  ${GREEN}./manage.sh logs${NC}      # View logs"
echo -e "  ${GREEN}./manage.sh clean${NC}     # Remove all containers, volumes and data"
echo -e "\n${YELLOW}For quick updates after code changes:${NC}"
echo -e "  ${GREEN}sudo ./install.sh --update${NC}  # Update code without reinstalling dependencies"
echo -e "\n${YELLOW}Troubleshooting:${NC}"
echo -e "  ${GREEN}./redis_test.py${NC}       # Test Redis connectivity"
echo -e "  ${GREEN}docker ps${NC}             # Check container status"

# Start services using manage.sh
echo -e "\n${YELLOW}Starting services with manage.sh...${NC}"
./manage.sh start

# Show service status
echo -e "\n${YELLOW}Current service status:${NC}"
./manage.sh status
#!/bin/bash

# Colors for pretty output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
UPDATE_MODE=false
GIT_UPDATE_MODE=false
HELP_MODE=false
GIT_CONTINUE=false

# Process command line arguments
for arg in "$@"; do
    case $arg in
        --update|-u)
            UPDATE_MODE=true
            shift
            ;;
        --git-update|-g)
            GIT_UPDATE_MODE=true
            shift
            ;;
        --continue)
            GIT_CONTINUE=true
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
    echo -e "  --update, -u         Update mode: only rebuild containers without reinstalling dependencies"
    echo -e "  --git-update, -g     Git update mode: pull latest code from GitHub with conflict resolution"
    echo -e "  --continue           Continue a previous Git update after resolving conflicts"
    echo -e "  --help, -h           Show this help message"
    echo -e "\nExamples:"
    echo -e "  $0                   Full installation"
    echo -e "  $0 --update          Update code only (useful after local changes)"
    echo -e "  $0 --git-update      Pull latest code from GitHub with conflict resolution"
    echo -e "  $0 --continue        Continue Git update after resolving conflicts"
    exit 0
fi

# Print header
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}     OpenVPN Provision Service Installer     ${NC}"
if [ "$UPDATE_MODE" = true ]; then
    echo -e "${GREEN}              UPDATE MODE                    ${NC}"
elif [ "$GIT_UPDATE_MODE" = true ]; then
    echo -e "${GREEN}           GIT UPDATE MODE                   ${NC}"
elif [ "$GIT_CONTINUE" = true ]; then
    echo -e "${GREEN}      CONTINUE GIT UPDATE MODE               ${NC}"
fi
echo -e "${GREEN}==============================================${NC}"

# Check if running with sudo/root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root or with sudo${NC}"
  exit 1
fi

# Git update functions
handle_git_update() {
    echo -e "${YELLOW}Checking for Git repository...${NC}"
    if [ ! -d .git ]; then
        echo -e "${RED}This directory is not a Git repository.${NC}"
        echo -e "${YELLOW}Cannot perform update from GitHub.${NC}"
        return 1
    fi

    # Store current branch
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    echo -e "${YELLOW}Current branch: ${CURRENT_BRANCH}${NC}"

    # Check if there are uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        echo -e "${RED}You have uncommitted changes in your repository.${NC}"
        echo -e "${YELLOW}Options:${NC}"
        echo -e "  1. Stash changes and proceed with update"
        echo -e "  2. Continue anyway (might cause conflicts)"
        echo -e "  3. Cancel update"
        read -p "Choose an option (1-3): " GIT_OPTION

        case $GIT_OPTION in
            1)
                echo -e "${YELLOW}Stashing changes...${NC}"
                git stash
                if [ $? -ne 0 ]; then
                    echo -e "${RED}Failed to stash changes. Aborting update.${NC}"
                    return 1
                fi
                echo -e "${GREEN}Changes stashed successfully.${NC}"
                ;;
            2)
                echo -e "${YELLOW}Continuing with uncommitted changes...${NC}"
                ;;
            *)
                echo -e "${YELLOW}Update cancelled.${NC}"
                return 1
                ;;
        esac
    fi

    # Try to pull changes
    echo -e "${YELLOW}Pulling latest code from GitHub...${NC}"
    PULL_RESULT=$(git pull 2>&1)
    PULL_STATUS=$?

    if [ $PULL_STATUS -eq 0 ]; then
        if [[ $PULL_RESULT == *"Already up to date"* ]]; then
            echo -e "${GREEN}Repository is already up to date.${NC}"
            read -p "Do you want to rebuild the services anyway? (y/n): " REBUILD_ANYWAY
            if [[ ! $REBUILD_ANYWAY =~ ^[Yy]$ ]]; then
                return 0
            fi
        else
            echo -e "${GREEN}Successfully pulled latest changes.${NC}"
        fi
    else
        # Handle merge conflicts or other issues
        if [[ $PULL_RESULT == *"Merge conflict"* ]]; then
            echo -e "${RED}Merge conflicts detected.${NC}"
            echo -e "${YELLOW}Options:${NC}"
            echo -e "  1. Abort the merge and reset to previous state"
            echo -e "  2. Open conflicts in your default editor to resolve manually"
            echo -e "  3. Accept all incoming changes (theirs)"
            echo -e "  4. Keep all current changes (yours)"
            read -p "Choose an option (1-4): " CONFLICT_OPTION

            case $CONFLICT_OPTION in
                1)
                    echo -e "${YELLOW}Aborting merge...${NC}"
                    git merge --abort
                    echo -e "${GREEN}Merge aborted. Repository reset to previous state.${NC}"
                    return 1
                    ;;
                2)
                    echo -e "${YELLOW}Opening conflicts in editor...${NC}"
                    EDITOR=${EDITOR:-vi}
                    CONFLICTED_FILES=$(git diff --name-only --diff-filter=U)
                    if [ -z "$CONFLICTED_FILES" ]; then
                        echo -e "${RED}No conflict files found!${NC}"
                        return 1
                    fi

                    for FILE in $CONFLICTED_FILES; do
                        echo -e "${YELLOW}Opening $FILE...${NC}"
                        $EDITOR "$FILE"
                    done

                    echo -e "${YELLOW}After resolving conflicts, mark them as resolved with 'git add <filename>'${NC}"
                    echo -e "${YELLOW}Then continue the update with 'sudo ./install.sh --continue'${NC}"
                    return 1
                    ;;
                3)
                    echo -e "${YELLOW}Accepting all incoming changes...${NC}"
                    CONFLICTED_FILES=$(git diff --name-only --diff-filter=U)
                    if [ -z "$CONFLICTED_FILES" ]; then
                        echo -e "${RED}No conflict files found!${NC}"
                        return 1
                    fi

                    for FILE in $CONFLICTED_FILES; do
                        git checkout --theirs -- "$FILE"
                        git add "$FILE"
                    done

                    git commit -m "Resolved conflicts by accepting incoming changes"
                    ;;
                4)
                    echo -e "${YELLOW}Keeping all current changes...${NC}"
                    CONFLICTED_FILES=$(git diff --name-only --diff-filter=U)
                    if [ -z "$CONFLICTED_FILES" ]; then
                        echo -e "${RED}No conflict files found!${NC}"
                        return 1
                    fi

                    for FILE in $CONFLICTED_FILES; do
                        git checkout --ours -- "$FILE"
                        git add "$FILE"
                    done

                    git commit -m "Resolved conflicts by keeping current changes"
                    ;;
                *)
                    echo -e "${RED}Invalid option. Aborting update.${NC}"
                    git merge --abort
                    return 1
                    ;;
            esac
        else
            echo -e "${RED}Error pulling from GitHub:${NC}"
            echo -e "$PULL_RESULT"
            return 1
        fi
    fi

    # If we had stashed changes, try to reapply them
    if [ "$GIT_OPTION" = "1" ]; then
        echo -e "${YELLOW}Reapplying stashed changes...${NC}"
        git stash pop
        if [ $? -ne 0 ]; then
            echo -e "${RED}Warning: Failed to reapply stashed changes.${NC}"
            echo -e "${YELLOW}Your stashed changes are still in the stash list.${NC}"
            echo -e "${YELLOW}Use 'git stash list' to see them and 'git stash apply' to try reapplying them later.${NC}"
        else
            echo -e "${GREEN}Stashed changes reapplied successfully.${NC}"
        fi
    fi

    echo -e "${GREEN}Code update completed successfully.${NC}"
    return 0
}

# Continue from previous git update
handle_update_continue() {
    echo -e "${YELLOW}Continuing previous Git update...${NC}"

    # Check if there are still unresolved conflicts
    if git diff --name-only --diff-filter=U | grep -q .; then
        echo -e "${RED}You still have unresolved conflicts.${NC}"
        echo -e "${YELLOW}Please resolve all conflicts and mark them with 'git add <filename>' before continuing.${NC}"
        return 1
    fi

    # Check if there's an ongoing merge
    if [ -f .git/MERGE_HEAD ]; then
        echo -e "${YELLOW}Completing merge...${NC}"
        git commit -m "Resolved merge conflicts"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to complete the merge.${NC}"
            return 1
        fi
        echo -e "${GREEN}Merge completed successfully.${NC}"
    else
        echo -e "${YELLOW}No ongoing merge detected.${NC}"
    fi

    echo -e "${GREEN}Update can now proceed.${NC}"
    return 0
}

# Handle Git update mode
if [ "$GIT_UPDATE_MODE" = true ]; then
    # Determine which docker compose command to use
    if command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    else
        echo -e "${RED}Neither docker-compose nor docker compose is available.${NC}"
        echo -e "${RED}Please run the installer without any flags first to set up Docker Compose.${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Updating from GitHub and rebuilding services...${NC}"
    if handle_git_update; then
        echo -e "${YELLOW}Rebuilding and restarting services...${NC}"
        $DOCKER_COMPOSE down
        $DOCKER_COMPOSE build --no-cache
        $DOCKER_COMPOSE up -d

        # Show service status
        echo -e "\n${YELLOW}Current service status:${NC}"
        $DOCKER_COMPOSE ps

        echo -e "\n${GREEN}Git update completed successfully!${NC}"
    fi
    exit 0
fi

# Handle continue mode
if [ "$GIT_CONTINUE" = true ]; then
    # Determine which docker compose command to use
    if command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    else
        echo -e "${RED}Neither docker-compose nor docker compose is available.${NC}"
        echo -e "${RED}Please run the installer without any flags first to set up Docker Compose.${NC}"
        exit 1
    fi

    if handle_update_continue; then
        echo -e "${YELLOW}Rebuilding and restarting services...${NC}"
        $DOCKER_COMPOSE down
        $DOCKER_COMPOSE build --no-cache
        $DOCKER_COMPOSE up -d

        # Show service status
        echo -e "\n${YELLOW}Current service status:${NC}"
        $DOCKER_COMPOSE ps

        echo -e "\n${GREEN}Git update completed successfully!${NC}"
    fi
    exit 0
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
        chmod +x ./manage.sh
        chmod +x ./redis_test.py
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
    update)
        echo -e "${YELLOW}Pulling latest code from GitHub, handling conflicts, and rebuilding...${NC}"
        $DOCKER_COMPOSE down
        git pull
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
        echo -e "${YELLOW}Usage:${NC} ./manage.sh {start|stop|restart|rebuild|update|status|logs|clean}"
        exit 1
esac
EOF

cat > vpn.sh << 'EOFVPN'
#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define OpenVPN config directory and primary config file
OPENVPN_DIR="/etc/openvpn"
SERVER_CONF="${OPENVPN_DIR}/server.conf"

# Check if OpenVPN directory exists
if [ -d "$OPENVPN_DIR" ]; then
    echo -e "${GREEN}OpenVPN directory found. Proceeding with configuration...${NC}"

    # Check if server.conf exists
    if [ -f "$SERVER_CONF" ]; then
        echo -e "${YELLOW}Checking current configuration...${NC}"

        # Check if routes are already configured
        if grep -q "push \"route 172.16.0.0 255.240.0.0\"" "$SERVER_CONF"; then
            echo -e "${YELLOW}Docker network route already configured.${NC}"
        else
            echo -e "${GREEN}Adding Docker network route...${NC}"
            echo "# Allow VPN clients to reach Docker network" >> "$SERVER_CONF"
            echo "push \"route 172.16.0.0 255.240.0.0\"  # Docker's default subnet range" >> "$SERVER_CONF"
        fi

        # Check if client-to-client is already configured
        if grep -q "client-to-client" "$SERVER_CONF"; then
            echo -e "${YELLOW}Client-to-client communication already enabled.${NC}"
        else
            echo -e "${GREEN}Enabling client-to-client communication...${NC}"
            echo "# Allow bidirectional communication" >> "$SERVER_CONF"
            echo "client-to-client" >> "$SERVER_CONF"
        fi

        echo -e "${GREEN}Configuration complete. Restarting OpenVPN service...${NC}"
        systemctl restart openvpn@server || systemctl restart openvpn

        echo -e "${GREEN}Done! OpenVPN has been configured to allow Docker communication.${NC}"
    else
        echo -e "${RED}Error: OpenVPN server configuration file not found at $SERVER_CONF${NC}"
        echo -e "${YELLOW}Please check your OpenVPN installation or specify the correct path.${NC}"
        exit 1
    fi
else
    echo -e "${RED}Error: OpenVPN directory not found at $OPENVPN_DIR${NC}"
    echo -e "${YELLOW}Please install OpenVPN first or check the installation path.${NC}"
    exit 1
fi
esac
EOFVPN

chmod +x manage.sh
chmod +x vpn.sh
chmod +x vpn_setup.sh
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
echo -e "\n${YELLOW}For quick updates:${NC}"
echo -e "  ${GREEN}sudo ./install.sh --update${NC}      # Update code without reinstalling dependencies"
echo -e "  ${GREEN}sudo ./install.sh --git-update${NC}  # Pull latest code from GitHub with conflict resolution"
echo -e "  ${GREEN}sudo ./install.sh --continue${NC}    # Continue update after resolving Git conflicts"
echo -e "\n${YELLOW}Troubleshooting:${NC}"
echo -e "  ${GREEN}./redis_test.py${NC}       # Test Redis connectivity"
echo -e "  ${GREEN}docker ps${NC}             # Check container status"

# Start services using manage.sh
echo -e "\n${YELLOW}Starting services with manage.sh...${NC}"
chmod +x ./manage.sh
chmod +x ./domain.sh
chmod +x ./redis_test.py
./vpn.sh
./manage.sh start



# Show service status
echo -e "\n${YELLOW}Current service status:${NC}"
./manage.sh status
#!/bin/bash

# telemt-menu.sh - MTProto Proxy Management Interface (Telemt) via Docker Compose
# Repository: https://github.com/AlexZonov/telemt-menu
# Version: 1.0.0

# ============================================================================
# CONSTANTS AND VARIABLES
# ============================================================================

VERSION="1.0.0"
SUPPORTED_TELEMT_VERSION="3.3.35"
SCRIPT_NAME="telemt-menu"
CONFIG_DIR="./config"
CONFIG_FILE="${CONFIG_DIR}/config.toml"
COMPOSE_FILE="./docker-compose.yml"
BACKUP_DIR="./backups"
MAX_BACKUPS=10

# API Settings
API_BASE_URL="http://127.0.0.1:9091"
API_AUTH_HEADER=""
API_TIMEOUT=10

# Output Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Emoji for display
EMOJI_INFO="ℹ️"
EMOJI_SUCCESS="✅"
EMOJI_ERROR="❌"
EMOJI_WARNING="⚠️"
EMOJI_SERVER="🖥️"
EMOJI_USER="👤"
EMOJI_KEY="🔑"
EMOJI_PORT="🔌"
EMOJI_DOMAIN="🌐"
EMOJI_DOCKER="🐳"
EMOJI_BACKUP="💾"
EMOJI_LOGS="📋"
EMOJI_UPDATE="🔄"
EMOJI_START="▶️"
EMOJI_STOP="⏹️"
EMOJI_RESTART="🔄"
EMOJI_STATUS="📊"
EMOJI_MENU="📋"
EMOJI_CHECK="✔️"
EMOJI_FIRE="🔥"

# ============================================================================
# COLOR OUTPUT FUNCTIONS
# ============================================================================

print_info() {
    echo -e "${BLUE}${EMOJI_INFO} $1${NC}"
}

print_success() {
    echo -e "${GREEN}${EMOJI_SUCCESS} $1${NC}"
}

print_error() {
    echo -e "${RED}${EMOJI_ERROR} $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}${EMOJI_WARNING} $1${NC}"
}

print_header() {
    echo -e "\n${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}\n"
}

print_step() {
    echo -e "${MAGENTA}→ $1${NC}"
}

# ============================================================================
# SYSTEM CHECKS
# ============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Script must be run as root!"
        exit 1
    fi
}

check_docker() {
    local docker_installed=false
    local compose_installed=false
    local docker_running=false

    # Check if docker is available
    if command -v docker &> /dev/null; then
        docker_installed=true
    fi

    # Check if docker-compose is available
    if command -v docker-compose &> /dev/null; then
        compose_installed=true
    fi

    # Check if Docker daemon is running (only if docker is installed)
    if [ "$docker_installed" = true ] && docker info &> /dev/null; then
        docker_running=true
    fi

    # If everything is OK, return
    if [ "$docker_installed" = true ] && [ "$compose_installed" = true ] && [ "$docker_running" = true ]; then
        return 0
    fi

    # Something is missing, show error and exit
    print_error "Docker and/or Docker Compose not found or Docker daemon not running!"
    echo ""

    if [ "$docker_installed" = false ]; then
        echo -e "  ${RED}✗${NC} Docker: not installed"
    else
        echo -e "  ${GREEN}✓${NC} Docker: installed"
    fi

    if [ "$compose_installed" = false ]; then
        echo -e "  ${RED}✗${NC} Docker Compose: not installed"
    else
        echo -e "  ${GREEN}✓${NC} Docker Compose: installed"
    fi

    if [ "$docker_installed" = true ] && [ "$docker_running" = false ]; then
        echo -e "  ${RED}✗${NC} Docker daemon: not running"
    elif [ "$docker_installed" = true ]; then
        echo -e "  ${GREEN}✓${NC} Docker daemon: running"
    fi

    echo ""
    print_error "Please install Docker and Docker Compose before running this script."
    print_info "Installation guide: https://docs.docker.com/get-docker/"
    exit 1
}

check_dependencies() {
    local missing_deps=()
    local missing_optional=()

    # Check curl (required)
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi

    # Check jq (required for API operations)
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    # Check wget (optional for script updates)
    if ! command -v wget &> /dev/null; then
        missing_optional+=("wget")
    fi

    # Check openssl (required for secret generation)
    if ! command -v openssl &> /dev/null; then
        missing_deps+=("openssl")
    fi

    # If there are missing required dependencies
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        echo ""
        print_info "Install dependencies manually:"
        echo -e "  ${YELLOW}sudo apt install -y ${missing_deps[*]}${NC}"
        exit 1
    fi

    # Show warning for missing optional dependencies
    if [ ${#missing_optional[@]} -gt 0 ]; then
        print_warning "Optional dependencies not found: ${missing_optional[*]}"
        print_info "Install manually for full functionality:"
        echo -e "  ${YELLOW}sudo apt install -y ${missing_optional[*]}${NC}"
    fi
}

check_system() {
    print_info "Checking system requirements..."
    check_root
    check_docker
    check_dependencies
    print_success "All system requirements met!"
}

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

generate_secret() {
    # Generate 32-character hex secret (16 bytes)
    openssl rand -hex 16 2>/dev/null || python3 -c 'import os; print(os.urandom(16).hex())' 2>/dev/null || xxd -l 16 -p /dev/urandom 2>/dev/null | tr -d '\n'
}

is_port_in_use() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | awk -v p=":${port}$" '$4 ~ p {exit 0} END {exit 1}'
        return
    fi
    if command -v netstat >/dev/null 2>&1; then
        netstat -lnt 2>/dev/null | awk -v p=":${port} " '$4 ~ p {exit 0} END {exit 1}'
        return
    fi
    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:${port} -sTCP:LISTEN >/dev/null 2>&1 && return 0
    fi
    return 1
}

validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

validate_domain() {
    local domain="$1"
    if [[ "$domain" =~ ^([A-Za-z0-9](-*[A-Za-z0-9])*\.)+(xn--[a-z0-9]{2,}|[A-Za-z]{2,})$ ]]; then
        return 0
    fi
    return 1
}

validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if [ "$octet" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

get_external_ip() {
    local ip

    # Try multiple services to get external IP
    local services=(
        "https://api.ipify.org"
        "https://ifconfig.me"
        "https://ipecho.net/plain"
        "https://checkip.amazonaws.com"
    )

    for service in "${services[@]}"; do
        ip=$(curl -s --max-time 5 "$service" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$ip" ] && validate_ip "$ip"; then
            echo "$ip"
            return 0
        fi
    done

    return 1
}

create_config_dir() {
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        print_info "Config directory created: $CONFIG_DIR"
    fi
}

create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        print_info "Backup directory created: $BACKUP_DIR"
    fi
}

create_backup() {
    create_backup_dir

    if [ ! -f "$CONFIG_FILE" ]; then
        print_warning "Configuration file not found. Skipping backup creation."
        return
    fi

    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="${BACKUP_DIR}/config_backup_${timestamp}.toml"

    cp "$CONFIG_FILE" "$backup_file"

    if [ $? -eq 0 ]; then
        print_success "Backup created: $(basename $backup_file)"

        # Remove old backups, keep only MAX_BACKUPS most recent
        local backup_count=$(ls -1 ${BACKUP_DIR}/config_backup_*.toml 2>/dev/null | wc -l)
        if [ "$backup_count" -gt "$MAX_BACKUPS" ]; then
            local to_delete=$((backup_count - MAX_BACKUPS))
            ls -1t ${BACKUP_DIR}/config_backup_*.toml | tail -n "$to_delete" | xargs rm -f
            print_info "Removed $to_delete old backups"
        fi
    else
        print_error "Failed to create backup!"
    fi
}


create_docker_compose() {
    local port="${1:-8443}"
    local current_user="$(whoami)"

    cat > "$COMPOSE_FILE" << EOF
version: '3.8'

services:
  telemt:
    user: "${current_user}"
    image: ghcr.io/telemt/telemt:latest
    restart: unless-stopped
    container_name: telemt
    ports:
      - "${PORT:-8443}:${PORT:-8443}"
      - "127.0.0.1:9090:9090"
      - "127.0.0.1:9091:9091"
    working_dir: /run/telemt
    command: ["/config/config.toml"]
    volumes:
      - ./config:/config:rw
    environment:
      - RUST_LOG=info
    read_only: false
    tmpfs:
      - /run/telemt:rw,mode=1777,size=32m
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    security_opt:
      - no-new-privileges:true
EOF

    print_success "docker-compose.yml file created"
}

create_initial_config() {
    local port="$1"
    local domain="$2"
    local secret="$3"
    local public_host="$4"

    cat > "$CONFIG_FILE" << EOF
# === General Settings ===
[general]
use_middle_proxy = false

[general.links]
public_host = "${public_host}"

[general.modes]
classic = false
secure = false
tls = true

[server]
port = ${port}

[server.api]
listen = "0.0.0.0:9091"
whitelist = []
auth_header = ""
enabled = true
read_only = false

# === Anti-Censorship & Masking ===
[censorship]
tls_domain = "${domain}"

[access.users]
user1 = "${secret}"
EOF

    print_success "Configuration file created"
}

update_config_port() {
    local new_port="$1"

    # Check API availability
    if ! check_api_available; then
        print_error "API unavailable! Make sure the container is running."
        return 1
    fi

    # Get current port via API (from health or stats)
    # To change port, config must be updated and container restarted
    create_backup

    # Update port in docker-compose.yml
    if [ -f "$COMPOSE_FILE" ]; then
        # Replace PORT environment variable in docker-compose.yml
        # Format: ${PORT:-old_port} -> ${PORT:-new_port}
        sed -i "s/\${PORT:-[0-9]*}/\${PORT:-${new_port}}/g" "$COMPOSE_FILE"
        print_success "Port in docker-compose.yml changed to: $new_port"
    else
        print_error "docker-compose.yml file not found!"
        return 1
    fi

    # Update port in config.toml
    if [ -f "$CONFIG_FILE" ]; then
        sed -i "s/^port\s*=\s*.*/port = ${new_port}/" "$CONFIG_FILE"
        print_success "Port in config.toml changed to: $new_port"
    fi

    print_success "Port changed to: $new_port"
    print_info "Container restart required for changes to take effect."
}

update_config_domain() {
    local new_domain="$1"

    # Check API availability
    if ! check_api_available; then
        print_error "API unavailable! Make sure the container is running."
        return 1
    fi

    create_backup

    # Update domain in config.toml
    if [ -f "$CONFIG_FILE" ]; then
        sed -i "s/^tls_domain\s*=\s*\".*\"/tls_domain = \"${new_domain}\"/" "$CONFIG_FILE"
        print_success "Masking domain changed to: $new_domain"
    else
        print_error "Configuration file not found!"
        return 1
    fi

    print_success "Masking domain changed to: $new_domain"
    print_info "Container restart required for changes to take effect."
}

get_user_count() {
    # Get count via API
    local count
    count=$(get_user_count_api 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$count" ]; then
        echo "$count"
    else
        return 1
    fi
}

# ============================================================================
# API FUNCTIONS
# ============================================================================

# Execute API request with error handling
api_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local url="${API_BASE_URL}${endpoint}"

    local curl_args=(-s --max-time "$API_TIMEOUT")

    # Add authorization header if configured
    if [ -n "$API_AUTH_HEADER" ]; then
        curl_args+=(-H "Authorization: $API_AUTH_HEADER")
    fi

    # Add Content-Type header for mutating requests
    if [ -n "$data" ]; then
        curl_args+=(-H "Content-Type: application/json" -d "$data")
    fi

    # Execute request
    local response
    local http_code
    response=$(curl "${curl_args[@]}" -X "$method" "$url" -w "\n%{http_code}" 2>/dev/null)
    local exit_code=$?

    # Extract HTTP code (last line)
    http_code=$(echo "$response" | tail -n1)
    # Remove line without HTTP code
    response=$(echo "$response" | sed '$d')

    if [ $exit_code -ne 0 ]; then
        return 1
    fi

    # Check HTTP code
    if [[ "$http_code" =~ ^[23][0-9][0-9]$ ]]; then
        echo "$response"
        return 0
    else
        return 1
    fi
}

# Check API availability
check_api_available() {
    # First quick check via TCP connection
    if ! timeout 2 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/9091" 2>/dev/null; then
        return 1
    fi

    # Then check via HTTP request
    local response
    response=$(curl -s --max-time 5 http://127.0.0.1:9091/v1/health 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$response" ]; then
        # Check that API is actually enabled
        local status=$(echo "$response" | jq -r '.data.status // empty' 2>/dev/null)
        if [ "$status" = "ok" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Get user count via API
get_user_count_api() {
    if ! check_api_available; then
        return 1
    fi

    local response
    response=$(api_request GET "/v1/stats/summary")

    if [ $? -eq 0 ] && [ -n "$response" ]; then
        echo "$response" | jq -r '.data.configured_users // 0' 2>/dev/null
        return 0
    else
        return 1
    fi
}

# Get user list via API
get_users_list_api() {
    if ! check_api_available; then
        return 1
    fi

    local response
    response=$(api_request GET "/v1/users")

    if [ $? -eq 0 ] && [ -n "$response" ]; then
        # Check response success
        local ok=$(echo "$response" | jq -r '.ok // false' 2>/dev/null)
        if [ "$ok" = "true" ]; then
            # Return only data array
            echo "$response" | jq -c '.data // []' 2>/dev/null
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Add user via API
add_user_api() {
    local username="$1"
    local secret="$2"

    if ! check_api_available; then
        return 1
    fi

    # Build JSON with required secret
    local request_body
    request_body=$(jq -n \
        --arg username "$username" \
        --arg secret "$secret" \
        '{"username": $username, "secret": $secret}')

    local response
    response=$(api_request POST "/v1/users" "$request_body")

    if [ $? -eq 0 ] && [ -n "$response" ]; then
        local ok=$(echo "$response" | jq -r '.ok // false' 2>/dev/null)
        if [ "$ok" = "true" ]; then
            # Return full response to extract links
            echo "$response"
            return 0
        else
            local error_msg=$(echo "$response" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
            print_error "API error: $error_msg"
            return 1
        fi
    else
        return 1
    fi
}

# Remove user via API
remove_user_api() {
    local username="$1"

    if ! check_api_available; then
        return 1
    fi

    local response
    response=$(api_request DELETE "/v1/users/${username}")

    if [ $? -eq 0 ] && [ -n "$response" ]; then
        local ok=$(echo "$response" | jq -r '.ok // false' 2>/dev/null)
        if [ "$ok" = "true" ]; then
            return 0
        else
            local error_msg=$(echo "$response" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
            print_error "API error: $error_msg"
            return 1
        fi
    else
        return 1
    fi
}

# Check if user exists via API
user_exists_api() {
    local username="$1"

    if ! check_api_available; then
        return 1
    fi

    local response
    response=$(api_request GET "/v1/users/${username}")

    if [ $? -eq 0 ] && [ -n "$response" ]; then
        local ok=$(echo "$response" | jq -r '.ok // false' 2>/dev/null)
        if [ "$ok" = "true" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Get user info via API
get_user_info_api() {
    local username="$1"

    if ! check_api_available; then
        return 1
    fi

    local response
    response=$(api_request GET "/v1/users/${username}")

    if [ $? -eq 0 ] && [ -n "$response" ]; then
        echo "$response"
        return 0
    else
        return 1
    fi
}

# Display user connection links
# Takes user JSON (from API response) and outputs nicely formatted links
print_user_links() {
    local user_json="$1"

    # Extract links of all types
    local classic_links=$(echo "$user_json" | jq -r '.links.classic[]?' 2>/dev/null)
    local secure_links=$(echo "$user_json" | jq -r '.links.secure[]?' 2>/dev/null)
    local tls_links=$(echo "$user_json" | jq -r '.links.tls[]?' 2>/dev/null)

    # If no links at all
    if [ -z "$classic_links" ] && [ -z "$secure_links" ] && [ -z "$tls_links" ]; then
        echo -e "  ${GRAY}No connection links available${NC}"
        return
    fi

    # Classic links
    if [ -n "$classic_links" ]; then
        echo -e "  ${YELLOW}Classic:${NC}"
        echo "$classic_links" | while read -r link; do
            echo "    $link"
        done
    fi

    # Secure links
    if [ -n "$secure_links" ]; then
        echo -e "  ${YELLOW}Secure (DD):${NC}"
        echo "$secure_links" | while read -r link; do
            echo "    $link"
        done
    fi

    # TLS links
    if [ -n "$tls_links" ]; then
        echo -e "  ${YELLOW}TLS (EE-TLS):${NC}"
        echo "$tls_links" | while read -r link; do
            echo "    $link"
        done
    fi
}

# ============================================================================
# CONTAINER MANAGEMENT FUNCTIONS
# ============================================================================

docker_compose_up() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "docker-compose.yml file not found!"
        return 1
    fi

    print_info "Starting container..."
    docker-compose up -d

    if [ $? -eq 0 ]; then
        print_success "Container started successfully!"
        sleep 2
        show_container_status
    else
        print_error "Failed to start container!"
        return 1
    fi
}

docker_compose_down() {
    print_info "Stopping container..."
    docker-compose down

    if [ $? -eq 0 ]; then
        print_success "Container stopped successfully!"
    else
        print_error "Failed to stop container!"
        return 1
    fi
}

docker_compose_restart() {
    print_info "Restarting container..."

    # First full stop
    docker-compose down
    if [ $? -ne 0 ]; then
        print_error "Failed to stop container!"
        return 1
    fi

    # Then full start
    docker-compose up -d
    if [ $? -eq 0 ]; then
        print_success "Container restarted successfully!"
        sleep 2
        show_container_status
    else
        print_error "Failed to start container!"
        return 1
    fi
}

docker_compose_logs() {
    print_info "Showing container logs (press Ctrl+C to exit)..."
    docker-compose logs -f telemt
}

docker_compose_pull() {
    print_info "Updating image to latest version..."
    docker-compose pull telemt

    if [ $? -eq 0 ]; then
        print_success "Image updated successfully!"
        print_info "Restart container to apply updates."
    else
        print_error "Failed to update image!"
        return 1
    fi
}

show_container_status() {
    print_header "${EMOJI_STATUS} Container Status"

    local status=$(docker-compose ps --format json 2>/dev/null | jq -r '.[0].Health // "N/A"' 2>/dev/null || echo "N/A")

    if docker-compose ps | grep -q "telemt"; then
        print_success "Container is running!"
        echo ""
        print_info "Details:"
        docker-compose ps
        echo ""
    else
        print_warning "Container is not running"
    fi
}

get_proxy_links() {
    print_info "Getting connection links..."

    # Wait a bit for API to start
    sleep 3

    # Execute API request from host, not from container
    local response=$(curl -s http://127.0.0.1:9091/v1/users 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$response" ]; then
        echo "$response" | jq . 2>/dev/null || echo "$response"
    else
        print_error "Failed to get links. Make sure container is running."
        return 1
    fi
}

# ============================================================================
# USER INTERFACE
# ============================================================================

confirm() {
    local message="$1"
    local default="${2:-y}"

    if [ -n "$2" ]; then
        read -rp "$message [Default: $default]: " choice
    else
        read -rp "$message [y/n]: " choice
    fi

    if [ -z "$choice" ]; then
        choice="$default"
    fi

    if [[ "$choice" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Wait for user input before returning to menu
wait_for_enter() {
    local message="${1:-Press Enter to continue...}"
    read -rp "$message"
}

input_port() {
    local port
    while true; do
        read -rp "Enter proxy port (1-65535): " port

        if ! validate_port "$port"; then
            print_error "Invalid port format! Enter a number from 1 to 65535."
            continue
        fi

        if is_port_in_use "$port"; then
            print_error "Port $port is already in use! Choose another."
            continue
        fi

        echo "$port"
        return 0
    done
}

input_domain() {
    local domain
    while true; do
        read -rp "Enter masking domain (e.g., example.com): " domain

        if ! validate_domain "$domain"; then
            print_error "Invalid domain format! Example: example.com"
            continue
        fi

        echo "$domain"
        return 0
    done
}

show_menu() {
    clear
    print_header "${EMOJI_FIRE} Telemt Menu - MTProto Proxy Management ${EMOJI_FIRE}"

    echo -e "${BOLD}Script Version: $VERSION${NC}"
    echo -e "${BOLD}Supported Telemt Version: $SUPPORTED_TELEMT_VERSION${NC}"
    echo -e "${BOLD}Repository: https://github.com/AlexZonov/telemt-menu${NC}\n"

    # Show current status
    local container_running=false
    if docker-compose ps 2>/dev/null | grep -q "telemt"; then
        container_running=true
        print_success "Container: running"

        # Get user count via API
        local user_count
        user_count=$(get_user_count 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$user_count" ]; then
            echo -e "${CYAN}Users: $user_count${NC}"
        fi
    else
        print_warning "Container: stopped"
    fi

    echo ""
    echo -e "${BOLD}${EMOJI_MENU} Main Menu:${NC}"
    echo -e "${GREEN}1.${NC} Install"
    echo -e "${GREEN}2.${NC} Add User"
    echo -e "${GREEN}3.${NC} Remove User"
    echo -e "${GREEN}4.${NC} Change Port"
    echo -e "${GREEN}5.${NC} Change Masking Domain"
    echo ""
    echo -e "${BLUE}6.${NC} Start Container"
    echo -e "${BLUE}7.${NC} Stop Container"
    echo -e "${BLUE}8.${NC} Restart Container"
    echo -e "${BLUE}9.${NC} Container Status"
    echo ""
    echo -e "${MAGENTA}10.${NC} Update Image"
    echo -e "${MAGENTA}11.${NC} View Logs"
    echo ""
    echo -e "${YELLOW}12.${NC} View Users"
    echo -e "${YELLOW}13.${NC} Backup Management"
    echo -e "${YELLOW}14.${NC} Update Script"
    echo ""
    echo -e "${RED}0.${NC} Exit"
    echo ""
    echo -e "${CYAN}────────────────────────────────────${NC}"
    echo ""
}

show_backup_menu() {
    clear
    print_header "${EMOJI_BACKUP} Backup Management"

    echo -e "${BOLD}Available backups (maximum $MAX_BACKUPS):${NC}\n"

    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A $BACKUP_DIR 2>/dev/null)" ]; then
        ls -lah ${BACKUP_DIR}/config_backup_*.toml 2>/dev/null | tail -n +2 | awk '{print $9, "(" $5 ")"}' | while read -r file size; do
            echo -e "${CYAN}• $(basename $file)${NC} → $size"
        done
    else
        print_warning "No backups found"
    fi

    echo ""
    echo -e "${CYAN}────────────────────────────────────${NC}\n"
    echo -e "${GREEN}1.${NC} Restore from latest backup"
    echo -e "${RED}2.${NC} Delete all backups"
    echo -e "${YELLOW}0.${NC} Back"
    echo ""
}

# ============================================================================
# MAIN MENU FUNCTIONS
# ============================================================================

menu_install() {
    print_header "${EMOJI_SERVER} MTProto Proxy Installation"

    print_info "This installation will:"
    echo "  1. Create config directory"
    echo "  2. Prompt for an available port"
    echo "  3. Prompt for masking domain"
    echo "  4. Generate secret for first user"
    echo "  5. Create configuration files"
    echo "  6. Start container"
    echo ""

    confirm "Continue installation?" "y"
    if [ $? -ne 0 ]; then
        print_info "Installation cancelled"
        return
    fi

    # Check if already installed
    if [ -f "$CONFIG_FILE" ]; then
        print_warning "Configuration already exists!"
        confirm "Recreate configuration? (All data will be lost)" "n"
        if [ $? -ne 0 ]; then
            print_info "Cancelled"
            return
        fi
    fi

    print_step "Creating directories..."
    create_config_dir
    create_backup_dir

    print_step "Checking port..."
    local port=$(input_port)
    print_success "Port $port is available and will be used"

    print_step "Setting up masking domain..."
    local domain=$(input_domain)
    print_success "Masking domain: $domain"

    print_step "Setting up public address..."
    local public_host

    echo ""
    print_info "Public address is used to generate connection links."
    confirm "Do you want to specify public address manually?" "n"
    if [ $? -eq 0 ]; then
        while true; do
            read -rp "Enter IP or domain: " public_host
            if [ -z "$public_host" ]; then
                print_error "Address cannot be empty!"
                continue
            fi
            if validate_ip "$public_host" || validate_domain "$public_host"; then
                print_success "Public address: $public_host"
                break
            else
                print_error "Invalid format! Enter a valid IP or domain."
            fi
        done
    else
        print_step "Auto-detecting external IP..."
        public_host=$(get_external_ip)
        if [ -n "$public_host" ]; then
            print_success "External IP detected: $public_host"
        else
            print_warning "Failed to detect external IP. Using: example.com"
            public_host="example.com"
        fi
    fi

    print_step "Generating secret..."
    local secret=$(generate_secret)
    if [ -z "$secret" ]; then
        print_error "Failed to generate secret!"
        return 1
    fi
    print_success "Secret generated: $secret"

    print_step "Creating configuration files..."
    create_docker_compose "$port"
    create_initial_config "$port" "$domain" "$secret" "$public_host"

    print_step "Starting container..."
    docker_compose_up

    if [ $? -eq 0 ]; then
        print_success "Installation complete!"
        echo ""
        print_info "To get connection links, select option 12 in the main menu."
    else
        print_error "Installation completed with errors!"
    fi
}

menu_add_user() {
    print_header "${EMOJI_USER} Add User"

    local username
    read -rp "Enter username: " username

    if [ -z "$username" ]; then
        print_error "Username cannot be empty!"
        return
    fi

    # Check if user exists via API
    if check_api_available 2>/dev/null; then
        if user_exists_api "$username" 2>/dev/null; then
            print_error "User '$username' already exists!"
            read -rp "Press Enter to continue..."
            return
        fi
    else
        print_error "API unavailable! Make sure the container is running."
        read -rp "Press Enter to continue..."
        return
    fi

    print_step "Generating secret..."
    local secret=$(generate_secret)
    if [ -z "$secret" ]; then
        print_error "Failed to generate secret!"
        return
    fi

    print_success "Secret for user '$username': $secret"

    # Add user via API
    print_step "Adding user via API..."
    local response
    response=$(add_user_api "$username" "$secret")

    if [ $? -eq 0 ]; then
        print_success "User '$username' successfully added via API!"

        # Extract user data from response
        local user_data
        user_data=$(echo "$response" | jq -r '.data.user // empty' 2>/dev/null)

        if [ -n "$user_data" ]; then
            echo ""
            echo -e "${BOLD}${BLUE}🔗 Connection Links:${NC}"

            # Use common function to display links
            print_user_links "$user_data"

            echo ""
            print_info "Copy the link and open in Telegram to connect"
        else
            print_info "To get connection links, select option 12 in the main menu"
        fi
    else
        print_error "Failed to add user via API!"
    fi
}

menu_remove_user() {
    print_header "${EMOJI_USER} Remove User"

    # Get list via API
    local users_response
    users_response=$(get_users_list_api 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$users_response" ]; then
        local users_count=$(echo "$users_response" | jq -r 'length' 2>/dev/null)

        if [ "$users_count" -eq 0 ]; then
            print_warning "No users found!"
            read -rp "Press Enter to continue..."
            return
        fi

        echo -e "${BOLD}Current users:${NC}\n"
        echo "$users_response" | jq -r '.[] | "• \(.username)"' 2>/dev/null
        echo ""
    else
        print_error "API unavailable! Make sure the container is running."
        read -rp "Press Enter to continue..."
        return
    fi

    read -rp "Enter username to remove: " username

    if [ -z "$username" ]; then
        print_error "Username cannot be empty!"
        return
    fi

    # Check existence via API
    if ! check_api_available 2>/dev/null; then
        print_error "API unavailable!"
        return
    fi

    if ! user_exists_api "$username" 2>/dev/null; then
        print_error "User '$username' not found!"
        return
    fi

    confirm "Remove user '$username'?" "y"
    if [ $? -eq 0 ]; then
        # Remove via API
        print_step "Removing user via API..."
        if remove_user_api "$username" 2>/dev/null; then
            print_success "User '$username' successfully removed via API!"
        else
            print_error "Failed to remove user via API!"
        fi
    else
        print_info "Removal cancelled"
    fi
}

menu_change_port() {
    print_header "${EMOJI_PORT} Change Port"

    # Check API availability
    if ! check_api_available 2>/dev/null; then
        print_error "API unavailable! Make sure the container is running."
        read -rp "Press Enter to continue..."
        return
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Configuration file not found! Run installation (option 1)."
        read -rp "Press Enter to continue..."
        return
    fi

    local current_port=$(grep -E "^port\s*=" "$CONFIG_FILE" | head -1 | sed 's/.*=\s*//' | tr -d ' ')
    print_info "Current port: $current_port"

    print_step "Enter new port..."
    local new_port=$(input_port)

    confirm "Change port from $current_port to $new_port?" "y"
    if [ $? -eq 0 ]; then
        update_config_port "$new_port"
        if [ $? -eq 0 ]; then
            confirm "Restart container now?" "y"
            if [ $? -eq 0 ]; then
                docker_compose_restart
            fi
        fi
    else
        print_info "Change cancelled"
    fi
}

menu_change_domain() {
    print_header "${EMOJI_DOMAIN} Change Masking Domain"

    # Check API availability
    if ! check_api_available 2>/dev/null; then
        print_error "API unavailable! Make sure the container is running."
        read -rp "Press Enter to continue..."
        return
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Configuration file not found! Run installation (option 1)."
        read -rp "Press Enter to continue..."
        return
    fi

    local current_domain=$(grep -E "^tls_domain\s*=" "$CONFIG_FILE" | head -1 | sed 's/.*=\s*"//' | sed 's/".*//')
    print_info "Current domain: $current_domain"

    print_warning "WARNING: Changing the masking domain will invalidate all existing user connection links."
    print_warning "All existing users will lose access and you will need to recreate them."

    local new_domain=$(input_domain)

    confirm "Are you sure you want to change domain from '$current_domain' to '$new_domain'? Type 'y' to confirm" "n"
    if [ $? -eq 0 ]; then
        update_config_domain "$new_domain"
        if [ $? -eq 0 ]; then
            confirm "Restart container now?" "y"
            if [ $? -eq 0 ]; then
                docker_compose_restart
            fi
        fi
    else
        print_info "Change cancelled"
    fi
}

menu_view_users() {
    print_header "${EMOJI_USER} View Users"

    # Get list via API
    local users_response
    users_response=$(get_users_list_api 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$users_response" ]; then
        # Parse API response
        local users_count=$(echo "$users_response" | jq -r 'length' 2>/dev/null)

        if [ "$users_count" -gt 0 ]; then
            echo -e "${BOLD}User List:${NC}\n"

            # Display each user with their links
            echo "$users_response" | jq -r '.[] | @base64' 2>/dev/null | while read -r user_b64; do
                # Decode user JSON
                local user_json=$(echo "$user_b64" | base64 -d 2>/dev/null)

                local username=$(echo "$user_json" | jq -r '.username' 2>/dev/null)
                echo -e "${BOLD}• $username${NC}"

                # Use common function to display links
                print_user_links "$user_json"

                echo ""
            done

            print_info "Total users: $users_count"
        else
            print_warning "No users found!"
        fi
    else
        print_error "API unavailable! Make sure the container is running."
    fi
}

menu_view_logs() {
    print_header "${EMOJI_LOGS} View Logs"

    if docker-compose ps 2>/dev/null | grep -q "telemt"; then
        docker_compose_logs
    else
        print_warning "Container is not running!"
    fi
}

menu_backup_management() {
    while true; do
        show_backup_menu

        read -rp "Select action [0-2]: " choice

        case "$choice" in
            0)
                break
                ;;
            1)
                if [ -d "$BACKUP_DIR" ] && [ "$(ls -A $BACKUP_DIR 2>/dev/null)" ]; then
                    local latest_backup=$(ls -1t ${BACKUP_DIR}/config_backup_*.toml | head -1)
                    if [ -n "$latest_backup" ]; then
                        confirm "Restore from $(basename $latest_backup)?" "y"
                        if [ $? -eq 0 ]; then
                            cp "$latest_backup" "$CONFIG_FILE"
                            print_success "Configuration restored!"
                            print_info "Restart container to apply changes."
                        fi
                    else
                        print_warning "No backups found"
                    fi
                else
                    print_warning "No backups found"
                fi
                ;;
            2)
                confirm "Delete all backups?" "n"
                if [ $? -eq 0 ]; then
                    rm -f ${BACKUP_DIR}/config_backup_*.toml
                    print_success "All backups deleted"
                fi
                ;;
            *)
                print_error "Invalid selection!"
                ;;
        esac
    done
}

menu_update_script() {
    print_header "${EMOJI_UPDATE} Update Script"

    print_info "This function will update telemt-menu.sh to the latest version from GitHub."
    print_warning "It is recommended to create a backup before updating!"

    confirm "Continue update?" "y"
    if [ $? -ne 0 ]; then
        print_info "Update cancelled"
        return
    fi

    # Create backup of current script
    local backup_script="telemt-menu.sh.backup.$(date +%Y%m%d_%H%M%S)"
    cp telemt-menu.sh "$backup_script" 2>/dev/null
    print_success "Script backup created: $backup_script"

    # Download new version
    print_step "Downloading latest version..."
    if wget -O telemt-menu.sh.new https://raw.githubusercontent.com/AlexZonov/telemt-menu/main/telemt-menu.sh 2>/dev/null; then
        # Check that file is not empty
        if [ -s telemt-menu.sh.new ]; then
            mv telemt-menu.sh.new telemt-menu.sh
            chmod +x telemt-menu.sh
            print_success "Script updated successfully!"
            print_info "Restart script to apply updates."
            echo ""
            read -rp "Run updated script? [y/n]: " restart
            if [[ "$restart" =~ ^[Yy]$ ]]; then
                exec sudo ./telemt-menu.sh
            fi
        else
            print_error "Downloaded file is empty! Restoring backup..."
            rm -f telemt-menu.sh.new
            cp "$backup_script" telemt-menu.sh
        fi
    else
        print_error "Failed to download latest version!"
        print_info "Check your internet connection."
        rm -f telemt-menu.sh.new
    fi
}

# ============================================================================
# MAIN LOOP
# ============================================================================

main() {
    check_system

    while true; do
        show_menu

        read -rp "Select action [0-14]: " choice

        case "$choice" in
            0)
                print_info "Exiting program. Goodbye!"
                exit 0
                ;;
            1)
                menu_install
                wait_for_enter
                ;;
            2)
                menu_add_user
                wait_for_enter
                ;;
            3)
                menu_remove_user
                wait_for_enter
                ;;
            4)
                menu_change_port
                wait_for_enter
                ;;
            5)
                menu_change_domain
                wait_for_enter
                ;;
            6)
                docker_compose_up
                wait_for_enter
                ;;
            7)
                docker_compose_down
                wait_for_enter
                ;;
            8)
                docker_compose_restart
                wait_for_enter
                ;;
            9)
                show_container_status
                wait_for_enter
                ;;
            10)
                docker_compose_pull
                wait_for_enter
                ;;
            11)
                menu_view_logs
                wait_for_enter
                ;;
            12)
                menu_view_users
                wait_for_enter
                ;;
            13)
                menu_backup_management
                ;;
            14)
                menu_update_script
                wait_for_enter
                ;;
            *)
                print_error "Invalid selection! Try again."
                sleep 2
                ;;
        esac
    done
}

# Run main function
main
#!/bin/bash

# Marzneshin Auto Install Script
# This script automates the installation and configuration of Marzneshin panel
# as well as SSL certificate management

# Function to update SSL certificates
update_ssl_certificates() {
    log_step "SSL Certificate Update"
    
    # First check if Certbot is installed
    if ! command -v certbot &> /dev/null; then
        log_error "Certbot is not installed. Installing it now..."
        install_certbot
    fi
    
    # Check if cloudflare.ini exists
    if [ ! -f "/etc/letsencrypt/cloudflare.ini" ]; then
        log_error "Cloudflare API credentials file not found"
        install_certbot
    fi
    
    # Generate new certificates
    generate_ssl
    
    # Check if Marzneshin is installed
    if command -v marzneshin &> /dev/null; then
        log_info "Restarting Marzneshin to apply new certificates..."
        marzneshin restart
        
        if [ $? -eq 0 ]; then
            log_success "Marzneshin restarted successfully"
        else
            log_error "Failed to restart Marzneshin"
        fi
    else
        log_warning "Marzneshin command not found. No restart performed."
    fi
    
    log_success "SSL certificates have been successfully updated!"
    echo
    echo -e "${CYAN}Certificates were copied to:${RESET}"
    for path in "${CERT_PATHS[@]}"; do
        echo -e "  - ${BOLD}$path/$CERT_NAME${RESET}"
        echo -e "  - ${BOLD}$path/$KEY_NAME${RESET}"
    done
}


# Color codes for pretty output
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
RESET="\033[0m"
BOLD="\033[1m"

# Function to display a styled menu
display_menu() {
    clear
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║                 ${MAGENTA}MARZNESHIN MANAGEMENT TOOL${CYAN}                 ║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo
    echo -e "  ${BOLD}${YELLOW}1)${RESET} Install & Configure Marzneshin"
    echo -e "  ${BOLD}${YELLOW}2)${RESET} Update SSL Certificates"
    echo -e "  ${BOLD}${YELLOW}0)${RESET} Exit"
    echo
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${RESET}"
    echo
}

# Function to print colorful logs
log_info() {
    echo -e "${BLUE}[INFO]${RESET} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${RESET} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${RESET} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}

log_step() {
    echo -e "\n${BOLD}${MAGENTA}===== $1 =====${RESET}\n"
}

# Function to check if script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run this script as root or with sudo."
        exit 1
    fi
}

# Function to detect OS and architecture
detect_os() {
    log_step "Detecting system information"
    
    # Detect OS type
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
        OS_VERSION=$VERSION_ID
        log_info "Detected OS: $OS_NAME $OS_VERSION"
    else
        log_error "Unable to detect OS. This script supports Ubuntu and Debian."
        exit 1
    fi

    # Detect architecture
    ARCH=$(uname -m)
    log_info "Detected architecture: $ARCH"
    
    # Check if OS is supported
    if [[ "$OS_NAME" != "ubuntu" && "$OS_NAME" != "debian" ]]; then
        log_warning "This script is primarily tested on Ubuntu and Debian. Results may vary on $OS_NAME."
    fi
}

# Function to update and upgrade system
update_system() {
    log_step "Updating and upgrading system packages"
    
    if [[ "$OS_NAME" == "ubuntu" || "$OS_NAME" == "debian" ]]; then
        log_info "Running apt update..."
        apt update -y
        if [ $? -eq 0 ]; then
            log_success "System update completed"
        else
            log_error "System update failed"
            exit 1
        fi
        
        log_info "Running apt upgrade..."
        apt upgrade -y
        if [ $? -eq 0 ]; then
            log_success "System upgrade completed"
        else
            log_error "System upgrade failed"
            exit 1
        fi
    else
        log_warning "Unsupported OS. Skipping update and upgrade."
    fi
}

# Function to install Docker
install_docker() {
    log_step "Installing Docker"
    
    if command -v docker &> /dev/null; then
        log_info "Docker is already installed"
    else
        log_info "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        if [ $? -eq 0 ]; then
            log_success "Docker installed successfully"
        else
            log_error "Docker installation failed"
            exit 1
        fi
    fi
    
    # Make sure Docker service is running
    log_info "Ensuring Docker service is running..."
    systemctl enable docker
    systemctl start docker
    log_success "Docker service is active"
}

# Function to install Marzneshin
install_marzneshin() {
    log_step "Installing Marzneshin panel"
    
    log_info "Running Marzneshin installation script..."
    log_info "This may take some time. The installation will be complete when you see the Marzneshin service running."
    log_info "Press Ctrl+C when you see 'Uvicorn running on http://0.0.0.0:8000' message"
    
    # Run the installation command
    bash -c "$(curl -sL https://github.com/marzneshin/Marzneshin/raw/master/script.sh)" @ install --database mariadb
    
    # Check if Marzneshin is installed by checking if the command exists
    if command -v marzneshin &> /dev/null; then
        log_success "Marzneshin installed successfully"
    else
        log_error "Marzneshin installation may have failed. Please check the logs above."
        exit 1
    fi
}

# Function to install Certbot and Cloudflare plugin
install_certbot() {
    log_step "Installing Certbot and Cloudflare plugin"
    
    log_info "Installing Certbot and Cloudflare DNS plugin..."
    apt install -y python3-certbot-dns-cloudflare
    
    if [ $? -eq 0 ]; then
        log_success "Certbot and Cloudflare plugin installed successfully"
    else
        log_error "Certbot installation failed"
        exit 1
    fi
    
    # Create directory for Cloudflare credentials
    mkdir -p /etc/letsencrypt
    
    log_info "Creating Cloudflare API credentials file..."
    touch /etc/letsencrypt/cloudflare.ini
    chmod 600 /etc/letsencrypt/cloudflare.ini
    
    # Get API token from user
    echo -e "${YELLOW}Please provide your Cloudflare API token${RESET}"
    read -p "Cloudflare API Token: " CF_TOKEN
    
    # Write API token to file
    echo "dns_cloudflare_api_token = $CF_TOKEN" > /etc/letsencrypt/cloudflare.ini
    log_success "Cloudflare API token saved"
}

# Function to handle SSL certificate generation
generate_ssl() {
    log_step "SSL Certificate Generation"
    
    # Arrays to store domains and their subdomain preferences
    declare -a DOMAINS
    declare -a SUBDOMAIN_PREFS
    declare -a CERTBOT_PARAMS
    
    # Get first domain from user
    read -p "Enter your first domain (e.g., example.com): " first_domain
    DOMAINS+=("$first_domain")
    
    # Ask about subdomains for the first domain
    echo -e "${YELLOW}Do you want to include all subdomains for ${BOLD}$first_domain${RESET}${YELLOW}? (y/n):${RESET}"
    read include_subdomains
    
    if [[ "$include_subdomains" == "y" || "$include_subdomains" == "Y" ]]; then
        SUBDOMAIN_PREFS+=("all")
        CERTBOT_PARAMS+=("-d $first_domain -d *.$first_domain")
    else
        SUBDOMAIN_PREFS+=("none")
        CERTBOT_PARAMS+=("-d $first_domain")
    fi
    
    # Get additional domains
    domain_counter=2
    while true; do
        echo -e "${YELLOW}Enter domain #$domain_counter (press Enter or type 'done' to finish):${RESET}"
        read domain
        
        if [[ -z "$domain" || "$domain" == "done" ]]; then
            break
        fi
        
        DOMAINS+=("$domain")
        
        echo -e "${YELLOW}Do you want to include all subdomains for ${BOLD}$domain${RESET}${YELLOW}? (y/n):${RESET}"
        read include_subdomains
        
        if [[ "$include_subdomains" == "y" || "$include_subdomains" == "Y" ]]; then
            SUBDOMAIN_PREFS+=("all")
            CERTBOT_PARAMS+=("-d $domain -d *.$domain")
        else
            SUBDOMAIN_PREFS+=("none")
            CERTBOT_PARAMS+=("-d $domain")
        fi
        
        domain_counter=$((domain_counter + 1))
    done
    
    # Display domain summary
    log_info "Certificate will be generated for the following domains:"
    for i in "${!DOMAINS[@]}"; do
        if [ "${SUBDOMAIN_PREFS[$i]}" == "all" ]; then
            echo "  - ${DOMAINS[$i]} (including all subdomains)"
        else
            echo "  - ${DOMAINS[$i]}"
        fi
    done
    
    # Generate and execute certbot command
    CERTBOT_CMD="certbot"
    for param in "${CERTBOT_PARAMS[@]}"; do
        CERTBOT_CMD="$CERTBOT_CMD $param"
    done
    CERTBOT_CMD="$CERTBOT_CMD --dns-cloudflare --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini certonly"
    
    log_info "Running Certbot with command: $CERTBOT_CMD"
    eval $CERTBOT_CMD
    
    if [ $? -eq 0 ]; then
        log_success "SSL certificate generated successfully"
    else
        log_error "SSL certificate generation failed"
        exit 1
    fi
    
    # Certificate file names
    echo -e "${YELLOW}Default certificate filenames are:${RESET}"
    echo -e "  - Certificate file: ${BOLD}cert.pem${RESET}"
    echo -e "  - Key file: ${BOLD}key.pem${RESET}"
    echo
    echo -e "${YELLOW}Would you like to use these default certificate filenames? (y/n):${RESET}"
    read use_default_filenames
    
    if [[ "$use_default_filenames" == "y" || "$use_default_filenames" == "Y" ]]; then
        CERT_NAME="cert.pem"
        KEY_NAME="key.pem"
    else
        read -p "Enter name for certificate file (with .pem extension): " CERT_NAME
        read -p "Enter name for key file (with .pem extension): " KEY_NAME
        
        # Add .pem extension if not provided
        if [[ ! "$CERT_NAME" == *.pem ]]; then
            CERT_NAME="$CERT_NAME.pem"
            log_info "Added .pem extension to certificate filename: $CERT_NAME"
        fi
        
        if [[ ! "$KEY_NAME" == *.pem ]]; then
            KEY_NAME="$KEY_NAME.pem"
            log_info "Added .pem extension to key filename: $KEY_NAME"
        fi
    fi
    
    # Certificate paths
    echo -e "${YELLOW}Default certificate paths are:${RESET}"
    echo -e "  - ${BOLD}/var/lib/marzneshin/certs${RESET}"
    echo -e "  - ${BOLD}/var/lib/marznode/certs${RESET}"
    echo
    echo -e "${YELLOW}Would you like to use these default certificate paths? (y/n):${RESET}"
    read use_default_paths
    
    # Create arrays for certificate paths
    declare -a CERT_PATHS
    
    if [[ "$use_default_paths" == "y" || "$use_default_paths" == "Y" ]]; then
        CERT_PATHS+=("/var/lib/marzneshin/certs")
        CERT_PATHS+=("/var/lib/marznode/certs")
    else
        while true; do
            echo -e "${YELLOW}Enter path to store certificates (press Enter or type 'done' to finish):${RESET}"
            read cert_path
            
            if [[ -z "$cert_path" || "$cert_path" == "done" ]]; then
                break
            fi
            
            # Remove trailing slash if present
            cert_path="${cert_path%/}"
            CERT_PATHS+=("$cert_path")
        done
        
        # If no paths were entered, use default paths
        if [ ${#CERT_PATHS[@]} -eq 0 ]; then
            log_warning "No paths provided. Using default paths."
            CERT_PATHS+=("/var/lib/marzneshin/certs")
            CERT_PATHS+=("/var/lib/marznode/certs")
        fi
    fi
    
    # Get primary domain certificate path
    PRIMARY_DOMAIN=${DOMAINS[0]}
    CERT_SRC_PATH="/etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem"
    KEY_SRC_PATH="/etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem"
    
    # Create directories and copy certificates
    for path in "${CERT_PATHS[@]}"; do
        # Create directory if it doesn't exist
        mkdir -p "$path"
        
        # Check if certificate files already exist and remove them
        if [ -f "$path/$CERT_NAME" ]; then
            log_info "Removing existing certificate file at $path/$CERT_NAME"
            rm -f "$path/$CERT_NAME"
        fi
        
        if [ -f "$path/$KEY_NAME" ]; then
            log_info "Removing existing key file at $path/$KEY_NAME"
            rm -f "$path/$KEY_NAME"
        fi
        
        # Copy new certificate files
        cp "$CERT_SRC_PATH" "$path/$CERT_NAME"
        cp "$KEY_SRC_PATH" "$path/$KEY_NAME"
        chmod 644 "$path/$CERT_NAME"
        chmod 644 "$path/$KEY_NAME"
        log_success "Certificates copied to $path"
    done
    
    # Store the path that has marzneshin in it for later use
    MARZNESHIN_CERT_PATH=""
    for path in "${CERT_PATHS[@]}"; do
        if [[ "$path" == *"/var/lib/marzneshin"* ]]; then
            MARZNESHIN_CERT_PATH="$path"
            break
        fi
    done
}

# Function to configure Marzneshin
configure_marzneshin() {
    log_step "Configuring Marzneshin"
    
    # Get new port from user
    read -p "Enter new port for Marzneshin (default: 8000): " NEW_PORT
    NEW_PORT=${NEW_PORT:-8000}
    
    # Get new dashboard path from user
    read -p "Enter new dashboard path (default: dashboard): " NEW_PATH
    NEW_PATH=${NEW_PATH:-dashboard}
    NEW_PATH="${NEW_PATH#/}" # Remove leading slash if present
    
    # Update .env file
    ENV_FILE="/etc/opt/marzneshin/.env"
    
    # Make a backup of the original .env file
    cp "$ENV_FILE" "$ENV_FILE.bak"
    log_info "Backup of original .env file created at $ENV_FILE.bak"
    
    # Update port in .env file
    sed -i "s/UVICORN_PORT = .*/UVICORN_PORT = $NEW_PORT/" "$ENV_FILE"
    log_success "Port updated to $NEW_PORT"
    
    # Uncomment and update dashboard path in .env file
    if grep -q "^# DASHBOARD_PATH" "$ENV_FILE"; then
        sed -i "s|^# DASHBOARD_PATH.*|DASHBOARD_PATH = \"/$NEW_PATH/\"|" "$ENV_FILE"
    else
        sed -i "s|^DASHBOARD_PATH.*|DASHBOARD_PATH = \"/$NEW_PATH/\"|" "$ENV_FILE"
    fi
    log_success "Dashboard path updated to /$NEW_PATH/"
    
    # Configure SSL if a valid Marzneshin certificate path exists
    if [ -n "$MARZNESHIN_CERT_PATH" ]; then
        # Uncomment and update SSL certificate paths in .env file
        if grep -q "^# UVICORN_SSL_CERTFILE" "$ENV_FILE"; then
            sed -i "s|^# UVICORN_SSL_CERTFILE.*|UVICORN_SSL_CERTFILE = \"$MARZNESHIN_CERT_PATH/$CERT_NAME\"|" "$ENV_FILE"
        else
            sed -i "s|^UVICORN_SSL_CERTFILE.*|UVICORN_SSL_CERTFILE = \"$MARZNESHIN_CERT_PATH/$CERT_NAME\"|" "$ENV_FILE"
        fi
        
        if grep -q "^# UVICORN_SSL_KEYFILE" "$ENV_FILE"; then
            sed -i "s|^# UVICORN_SSL_KEYFILE.*|UVICORN_SSL_KEYFILE = \"$MARZNESHIN_CERT_PATH/$KEY_NAME\"|" "$ENV_FILE"
        else
            sed -i "s|^UVICORN_SSL_KEYFILE.*|UVICORN_SSL_KEYFILE = \"$MARZNESHIN_CERT_PATH/$KEY_NAME\"|" "$ENV_FILE"
        fi
        log_success "SSL configuration updated"
    else
        log_warning "No valid Marzneshin certificate path found. SSL not configured."
    fi
    
    # Restart Marzneshin to apply changes
    log_info "Restarting Marzneshin..."
    marzneshin restart
    
    if [ $? -eq 0 ]; then
        log_success "Marzneshin restarted successfully"
    else
        log_error "Failed to restart Marzneshin"
    fi
}

# Function to display final information
display_final_info() {
    log_step "Installation Complete"
    
    echo -e "${GREEN}${BOLD}Marzneshin has been successfully installed and configured!${RESET}"
    echo
    echo -e "${YELLOW}Panel Information:${RESET}"
    echo -e "  Port: ${BOLD}$NEW_PORT${RESET}"
    echo -e "  Dashboard Path: ${BOLD}/$NEW_PATH/${RESET}"
    
    if [ -n "$MARZNESHIN_CERT_PATH" ]; then
        echo -e "  SSL: ${GREEN}Enabled${RESET}"
    else
        echo -e "  SSL: ${RED}Not configured${RESET}"
    fi
    
    echo
    echo -e "${YELLOW}To create an admin user, run:${RESET}"
    echo -e "  ${BOLD}marzneshin cli admin create --sudo${RESET}"
    echo
    echo -e "${YELLOW}To access your panel:${RESET}"
    
    if [ -n "$MARZNESHIN_CERT_PATH" ]; then
        echo -e "  ${BOLD}https://${DOMAINS[0]}:$NEW_PORT/$NEW_PATH/${RESET}"
    else
        echo -e "  ${BOLD}http://${DOMAINS[0]}:$NEW_PORT/$NEW_PATH/${RESET}"
    fi
    
    echo
    echo -e "${BLUE}Thank you for using the Marzneshin Auto Install Script!${RESET}"
}

# Main execution
main() {
    check_root
    
    while true; do
        display_menu
        read -p "Enter your choice (0-2): " choice
        
        case $choice in
            1)
                echo -e "${BOLD}${GREEN}===== Installing & Configuring Marzneshin =====${RESET}\n"
                detect_os
                update_system
                install_docker
                install_marzneshin
                install_certbot
                generate_ssl
                configure_marzneshin
                display_final_info
                echo
                read -p "Press Enter to return to the main menu..."
                ;;
            2)
                echo -e "${BOLD}${GREEN}===== Updating SSL Certificates =====${RESET}\n"
                update_ssl_certificates
                echo
                read -p "Press Enter to return to the main menu..."
                ;;
            0)
                echo -e "${BOLD}${GREEN}Thank you for using the Marzneshin Management Tool!${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${RESET}"
                sleep 2
                ;;
        esac
    done
}

# Run the main function
main

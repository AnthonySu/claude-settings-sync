#!/bin/bash
# setup.sh - Initialize claude-settings-sync

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}${BOLD}         Claude Settings Sync - Initial Setup               ${NC}${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check dependencies
if ! check_dependencies; then
    exit 1
fi

# Check if already configured
if config_exists; then
    existing_gist=$(get_config_value "gist_id")
    if [ -n "$existing_gist" ]; then
        log_warn "Already configured with Gist: $existing_gist"
        echo ""
        read -p "Reconfigure? (y/N): " reconfigure
        if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
            log_info "Setup cancelled. Use /sync:status to check current config."
            exit 0
        fi
    fi
fi

# Get GitHub token
echo ""
log_info "You need a GitHub Personal Access Token with 'gist' scope."
echo "Create one at: https://github.com/settings/tokens/new"
echo ""
read -sp "Enter your GitHub token: " token
echo ""

if [ -z "$token" ]; then
    log_error "Token cannot be empty"
    exit 1
fi

# Validate token
log_info "Validating token..."
username=$(validate_token "$token")
if [ $? -ne 0 ] || [ -z "$username" ]; then
    log_error "Invalid token or API error"
    exit 1
fi
log_success "Authenticated as: $username"

# Check for existing gist
log_info "Checking for existing sync gist..."
existing_gist_id=$(find_existing_gist "$token")

if [ -n "$existing_gist_id" ]; then
    log_success "Found existing sync gist: $existing_gist_id"
    echo ""
    echo "Options:"
    echo "  1) Use existing gist (pull settings from another device)"
    echo "  2) Create new gist (start fresh)"
    echo ""
    read -p "Choose (1/2): " choice

    case "$choice" in
        1)
            gist_id="$existing_gist_id"
            log_info "Using existing gist"
            ;;
        2)
            log_info "Creating new gist..."
            gist_id=$(create_gist "$token")
            if [ -z "$gist_id" ]; then
                log_error "Failed to create gist"
                exit 1
            fi
            log_success "Created new gist: $gist_id"
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
else
    log_info "No existing sync gist found. Creating new one..."
    gist_id=$(create_gist "$token")
    if [ -z "$gist_id" ]; then
        log_error "Failed to create gist"
        exit 1
    fi
    log_success "Created new gist: $gist_id"
fi

# Save configuration
log_info "Saving configuration..."
save_config "$token" "$gist_id"
log_success "Configuration saved to $CONFIG_FILE"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}${BOLD}                    Setup Complete!                         ${NC}${GREEN}║${NC}"
echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}  GitHub User: ${BOLD}$username${NC}"
echo -e "${GREEN}║${NC}  Gist ID: ${BOLD}$gist_id${NC}"
echo -e "${GREEN}║${NC}  Gist URL: ${CYAN}https://gist.github.com/$gist_id${NC}"
echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}  Next steps:"
echo -e "${GREEN}║${NC}  • ${BOLD}/sync:push${NC}  - Upload your current settings"
echo -e "${GREEN}║${NC}  • ${BOLD}/sync:pull${NC}  - Download settings from gist"
echo -e "${GREEN}║${NC}  • ${BOLD}/sync:status${NC} - Check sync status"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

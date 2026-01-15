#!/bin/bash
# update.sh - Check for and apply plugin updates
# Supports both git-based and tarball-based installations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/utils.sh"

# Constants
REPO_OWNER="AnthonySu"
REPO_NAME="claude-settings-sync"
GITHUB_API="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME"
GITHUB_RAW="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main"
TARBALL_URL="https://github.com/$REPO_OWNER/$REPO_NAME/archive/refs/heads/main.tar.gz"

# Parse arguments
FORCE=false
CHECK_ONLY=false
for arg in "$@"; do
    case $arg in
        --force) FORCE=true ;;
        --check) CHECK_ONLY=true ;;
    esac
done

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}${BOLD}             Claude Settings Sync - Update                   ${NC}${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Get local version
get_local_version() {
    if [ -f "$PLUGIN_DIR/VERSION" ]; then
        cat "$PLUGIN_DIR/VERSION" | tr -d '[:space:]'
    else
        echo "unknown"
    fi
}

# Get remote version from GitHub (try raw URL first, then API as fallback)
get_remote_version() {
    local version

    # Try raw.githubusercontent.com first (faster, but has CDN cache)
    version=$(curl -s --connect-timeout 5 "$GITHUB_RAW/VERSION" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$version" ] && [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$version"
        return
    fi

    # Fallback to GitHub API (always up-to-date, but rate-limited)
    version=$(curl -s --connect-timeout 5 "$GITHUB_API/contents/VERSION" 2>/dev/null | jq -r '.content // empty' | base64 -d 2>/dev/null | tr -d '[:space:]')
    if [ -n "$version" ] && [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$version"
        return
    fi

    echo ""
}

# Compare semantic versions: returns "newer", "same", "older", or "error"
compare_versions() {
    local local_ver="$1"
    local remote_ver="$2"

    if [ -z "$local_ver" ] || [ -z "$remote_ver" ] || [ "$local_ver" = "unknown" ]; then
        echo "error"
        return
    fi

    # Split versions into components
    local local_major local_minor local_patch
    local remote_major remote_minor remote_patch

    IFS='.' read -r local_major local_minor local_patch <<< "$local_ver"
    IFS='.' read -r remote_major remote_minor remote_patch <<< "$remote_ver"

    # Compare major
    if [ "$remote_major" -gt "$local_major" ] 2>/dev/null; then
        echo "newer"
        return
    elif [ "$remote_major" -lt "$local_major" ] 2>/dev/null; then
        echo "older"
        return
    fi

    # Compare minor
    if [ "$remote_minor" -gt "$local_minor" ] 2>/dev/null; then
        echo "newer"
        return
    elif [ "$remote_minor" -lt "$local_minor" ] 2>/dev/null; then
        echo "older"
        return
    fi

    # Compare patch
    if [ "$remote_patch" -gt "$local_patch" ] 2>/dev/null; then
        echo "newer"
        return
    elif [ "$remote_patch" -lt "$local_patch" ] 2>/dev/null; then
        echo "older"
        return
    fi

    echo "same"
}

# Check if git installation
is_git_install() {
    [ -d "$PLUGIN_DIR/.git" ]
}

# Get changelog from GitHub
get_changelog() {
    local current_ver="$1"
    # Fetch recent commits or release notes
    curl -s --connect-timeout 5 "$GITHUB_API/commits?per_page=5" 2>/dev/null | \
        jq -r '.[].commit.message' 2>/dev/null | head -10
}

# Update via git
update_via_git() {
    log_info "Updating via git pull..."
    cd "$PLUGIN_DIR"

    # Stash any local changes
    if ! git diff --quiet 2>/dev/null; then
        log_warn "Stashing local changes..."
        git stash
    fi

    # Fetch and pull
    if git fetch origin main 2>/dev/null && git pull origin main 2>/dev/null; then
        log_success "Git pull successful"
        return 0
    else
        log_error "Git pull failed"
        return 1
    fi
}

# Update via tarball
update_via_tarball() {
    log_info "Updating via tarball..."

    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    # Download new version
    if ! curl -sL "$TARBALL_URL" | tar -xz -C "$temp_dir"; then
        log_error "Failed to download update"
        return 1
    fi

    local new_dir="$temp_dir/$REPO_NAME-main"
    if [ ! -d "$new_dir" ]; then
        log_error "Downloaded archive has unexpected structure"
        return 1
    fi

    # Backup current config (sync config, not synced settings)
    local config_backup=""
    if [ -f "$CONFIG_FILE" ]; then
        config_backup=$(cat "$CONFIG_FILE")
    fi

    # Remove old files (except .git if exists)
    find "$PLUGIN_DIR" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} \;

    # Copy new files
    cp -r "$new_dir"/* "$PLUGIN_DIR/"

    # Restore config
    if [ -n "$config_backup" ]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
        echo "$config_backup" > "$CONFIG_FILE"
    fi

    # Make scripts executable
    chmod +x "$PLUGIN_DIR"/*.sh "$PLUGIN_DIR"/scripts/*.sh 2>/dev/null

    log_success "Tarball update successful"
    return 0
}

# Main logic
local_version=$(get_local_version)
log_info "Local version: $local_version"

log_info "Checking for updates..."
remote_version=$(get_remote_version)

if [ -z "$remote_version" ]; then
    log_error "Could not fetch remote version"
    log_info "Check your internet connection or try again later."
    exit 1
fi

log_info "Remote version: $remote_version"
echo ""

# Compare versions
comparison=$(compare_versions "$local_version" "$remote_version")

case "$comparison" in
    "newer")
        echo -e "┌─ Update Available ──────────────────────────────────────────┐"
        echo -e "│ ${GREEN}New version available: $remote_version${NC}"
        echo -e "│ Current version: $local_version"
        echo -e "└──────────────────────────────────────────────────────────────┘"
        echo ""

        if [ "$CHECK_ONLY" = true ]; then
            log_info "Run /claude-settings-sync:update to install the update."
            exit 0
        fi

        # Show recent changes
        log_info "Recent changes:"
        echo "┌──────────────────────────────────────────────────────────────┐"
        get_changelog "$local_version" | while read -r line; do
            [ -n "$line" ] && echo "│ • $line"
        done
        echo "└──────────────────────────────────────────────────────────────┘"
        echo ""

        # Confirm update
        if [ "$FORCE" != true ]; then
            if [ -t 0 ]; then
                read -p "Install update? (y/N): " confirm
                if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                    log_info "Update cancelled."
                    exit 0
                fi
            else
                log_info "Non-interactive mode. Use --force to update without confirmation."
                exit 0
            fi
        fi

        # Perform update
        echo ""
        if is_git_install; then
            update_via_git
        else
            update_via_tarball
        fi

        update_result=$?

        if [ $update_result -eq 0 ]; then
            echo ""
            log_success "Update complete! Now at version $remote_version"
            log_info "Restart Claude Code for changes to take effect."
        else
            log_error "Update failed. Your current installation is intact."
            exit 1
        fi
        ;;

    "same")
        echo -e "┌─ Up to Date ────────────────────────────────────────────────┐"
        echo -e "│ ${GREEN}You're running the latest version: $local_version${NC}"
        echo -e "└──────────────────────────────────────────────────────────────┘"
        echo ""

        if [ "$FORCE" = true ]; then
            log_info "Force reinstall requested..."
            if is_git_install; then
                update_via_git
            else
                update_via_tarball
            fi
        fi
        ;;

    "older")
        echo -e "┌─ Version Info ──────────────────────────────────────────────┐"
        echo -e "│ ${YELLOW}You're running a newer version than remote${NC}"
        echo -e "│ Local: $local_version"
        echo -e "│ Remote: $remote_version"
        echo -e "│ (You may be on a development branch)"
        echo -e "└──────────────────────────────────────────────────────────────┘"
        ;;

    *)
        log_warn "Could not compare versions"
        log_info "Local: $local_version, Remote: $remote_version"

        if [ "$FORCE" = true ]; then
            log_info "Force update requested..."
            if is_git_install; then
                update_via_git
            else
                update_via_tarball
            fi
        fi
        ;;
esac

echo ""

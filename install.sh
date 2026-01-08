#!/bin/bash
# install.sh - Automated installer for claude-settings-sync plugin
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/AnthonySu/claude-settings-sync/main/install.sh | bash
#   OR
#   ./install.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Paths
CLAUDE_DIR="$HOME/.claude"
PLUGINS_DIR="$CLAUDE_DIR/plugins"
MARKETPLACES_DIR="$PLUGINS_DIR/marketplaces"
INSTALL_DIR="$MARKETPLACES_DIR/claude-settings-sync"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
KNOWN_MARKETPLACES_FILE="$PLUGINS_DIR/known_marketplaces.json"
INSTALLED_PLUGINS_FILE="$PLUGINS_DIR/installed_plugins.json"

REPO_URL="https://github.com/AnthonySu/claude-settings-sync.git"
PLUGIN_NAME="claude-settings-sync"
PLUGIN_VERSION="1.1.0"

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}${BOLD}        Claude Settings Sync - Installer                    ${NC}${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v git &> /dev/null; then
    log_error "git is required but not installed."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed."
    echo "Install with: brew install jq (macOS) or apt install jq (Linux)"
    exit 1
fi

if [ ! -d "$CLAUDE_DIR" ]; then
    log_error "Claude Code directory not found at $CLAUDE_DIR"
    echo "Please install and run Claude Code first."
    exit 1
fi

log_success "Prerequisites OK"

# Create directories if needed
log_info "Setting up directories..."
mkdir -p "$MARKETPLACES_DIR"
mkdir -p "$PLUGINS_DIR"

# Clone or update repository
if [ -d "$INSTALL_DIR" ]; then
    log_info "Existing installation found, updating..."
    cd "$INSTALL_DIR"
    git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || log_warn "Could not update, using existing version"
else
    log_info "Cloning repository..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

# Make scripts executable
log_info "Setting script permissions..."
chmod +x "$INSTALL_DIR/scripts/"*.sh

# Get plugin version from plugin.json
if [ -f "$INSTALL_DIR/.claude-plugin/plugin.json" ]; then
    PLUGIN_VERSION=$(jq -r '.version // "1.0.0"' "$INSTALL_DIR/.claude-plugin/plugin.json")
fi

# Update settings.json
log_info "Updating settings.json..."

if [ ! -f "$SETTINGS_FILE" ]; then
    # Create minimal settings.json
    echo '{}' > "$SETTINGS_FILE"
fi

# Read current settings
SETTINGS=$(cat "$SETTINGS_FILE")

# Add marketplace to extraKnownMarketplaces
SETTINGS=$(echo "$SETTINGS" | jq --arg name "$PLUGIN_NAME" --arg repo "AnthonySu/$PLUGIN_NAME" '
    .extraKnownMarketplaces //= {} |
    .extraKnownMarketplaces[$name] = {
        "source": {
            "source": "github",
            "repo": $repo
        }
    }
')

# Enable the plugin
SETTINGS=$(echo "$SETTINGS" | jq --arg plugin "${PLUGIN_NAME}@${PLUGIN_NAME}" '
    .enabledPlugins //= {} |
    .enabledPlugins[$plugin] = true
')

# Write back settings
echo "$SETTINGS" | jq '.' > "$SETTINGS_FILE"
log_success "Updated settings.json"

# Update known_marketplaces.json
log_info "Updating known_marketplaces.json..."

if [ ! -f "$KNOWN_MARKETPLACES_FILE" ]; then
    echo '{}' > "$KNOWN_MARKETPLACES_FILE"
fi

KNOWN=$(cat "$KNOWN_MARKETPLACES_FILE")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

KNOWN=$(echo "$KNOWN" | jq --arg name "$PLUGIN_NAME" --arg repo "AnthonySu/$PLUGIN_NAME" --arg path "$INSTALL_DIR" --arg ts "$TIMESTAMP" '
    .[$name] = {
        "source": {
            "source": "github",
            "repo": $repo
        },
        "installLocation": $path,
        "lastUpdated": $ts
    }
')

echo "$KNOWN" | jq '.' > "$KNOWN_MARKETPLACES_FILE"
log_success "Updated known_marketplaces.json"

# Update installed_plugins.json
log_info "Updating installed_plugins.json..."

if [ ! -f "$INSTALLED_PLUGINS_FILE" ]; then
    echo '{"version": 2, "plugins": {}}' > "$INSTALLED_PLUGINS_FILE"
fi

INSTALLED=$(cat "$INSTALLED_PLUGINS_FILE")

INSTALLED=$(echo "$INSTALLED" | jq --arg plugin "${PLUGIN_NAME}@${PLUGIN_NAME}" --arg path "$INSTALL_DIR" --arg version "$PLUGIN_VERSION" --arg ts "$TIMESTAMP" --arg home "$HOME" '
    .version = 2 |
    .plugins[$plugin] = [{
        "scope": "project",
        "installPath": $path,
        "version": $version,
        "installedAt": $ts,
        "lastUpdated": $ts,
        "isLocal": false,
        "projectPath": $home
    }]
')

echo "$INSTALLED" | jq '.' > "$INSTALLED_PLUGINS_FILE"
log_success "Updated installed_plugins.json"

# Done!
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}${BOLD}              Installation Complete!                        ${NC}${GREEN}║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo "  1. Restart Claude Code (or start a new session)"
echo "  2. Run /claude-settings-sync:setup to configure your GitHub token"
echo ""
echo "Commands available after setup:"
echo "  /claude-settings-sync        - Show sync status"
echo "  /claude-settings-sync:push   - Upload settings to Gist"
echo "  /claude-settings-sync:pull   - Download settings from Gist"
echo ""

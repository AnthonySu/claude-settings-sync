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

REPO_OWNER="AnthonySu"
PLUGIN_NAME="claude-settings-sync"
TARBALL_URL="https://github.com/$REPO_OWNER/$PLUGIN_NAME/archive/refs/heads/main.tar.gz"
PLUGIN_VERSION="2.2.0"

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}${BOLD}        Claude Settings Sync - Installer v$PLUGIN_VERSION            ${NC}${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
log_info "Checking prerequisites..."

missing=()
command -v curl &> /dev/null || missing+=("curl")
command -v jq &> /dev/null || missing+=("jq")
command -v xz &> /dev/null || missing+=("xz")
command -v tar &> /dev/null || missing+=("tar")

if [ ${#missing[@]} -gt 0 ]; then
    log_error "Missing: ${missing[*]}"
    echo "Install with: brew install ${missing[*]} (macOS) or apt install ${missing[*]} (Linux)"
    exit 1
fi

if [ ! -d "$CLAUDE_DIR" ]; then
    log_error "Claude Code not found at $CLAUDE_DIR"
    echo "Please install and run Claude Code first."
    exit 1
fi

log_success "Prerequisites OK"

# Create directories
mkdir -p "$MARKETPLACES_DIR"

# Download and install
if [ -d "$INSTALL_DIR/.git" ]; then
    # Existing git install - use git pull
    log_info "Updating via git..."
    cd "$INSTALL_DIR"
    git pull origin main 2>/dev/null || log_warn "Could not update"
elif [ -d "$INSTALL_DIR" ]; then
    # Existing tarball install - re-download
    log_info "Reinstalling..."
    rm -rf "$INSTALL_DIR"
    curl -sL "$TARBALL_URL" | tar -xz -C "$MARKETPLACES_DIR"
    mv "$MARKETPLACES_DIR/$PLUGIN_NAME-main" "$INSTALL_DIR"
else
    # Fresh install
    log_info "Downloading..."
    curl -sL "$TARBALL_URL" | tar -xz -C "$MARKETPLACES_DIR"
    mv "$MARKETPLACES_DIR/$PLUGIN_NAME-main" "$INSTALL_DIR"
fi

log_success "Downloaded to $INSTALL_DIR"

# Make scripts executable
chmod +x "$INSTALL_DIR"/*.sh "$INSTALL_DIR"/scripts/*.sh 2>/dev/null
log_success "Scripts ready"

# Register plugin in settings.json
log_info "Registering plugin..."
[ ! -f "$SETTINGS_FILE" ] && echo '{}' > "$SETTINGS_FILE"

jq --arg name "$PLUGIN_NAME" --arg repo "$REPO_OWNER/$PLUGIN_NAME" '
    .extraKnownMarketplaces //= {} |
    .extraKnownMarketplaces[$name] = {"source": {"source": "github", "repo": $repo}} |
    .enabledPlugins //= {} |
    .enabledPlugins[$name + "@" + $name] = true
' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

log_success "Plugin registered"

# Done!
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Next: Restart Claude Code, then run:"
echo ""
echo "  /claude-settings-sync:setup   - Configure GitHub token (first time)"
echo "  /claude-settings-sync:pull    - Pull settings from another device"
echo ""

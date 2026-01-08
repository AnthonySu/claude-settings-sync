#!/bin/bash
# uninstall.sh - Uninstaller for claude-settings-sync
#
# Usage:
#   ~/.claude/plugins/marketplaces/claude-settings-sync/uninstall.sh
#   OR
#   curl -fsSL https://raw.githubusercontent.com/AnthonySu/claude-settings-sync/main/uninstall.sh | bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Paths
CLAUDE_DIR="$HOME/.claude"
PLUGINS_DIR="$CLAUDE_DIR/plugins"
MARKETPLACES_DIR="$PLUGINS_DIR/marketplaces"
PLUGIN_NAME="claude-settings-sync"
INSTALL_DIR="$MARKETPLACES_DIR/$PLUGIN_NAME"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
KNOWN_MARKETPLACES_FILE="$PLUGINS_DIR/known_marketplaces.json"
INSTALLED_PLUGINS_FILE="$PLUGINS_DIR/installed_plugins.json"
SYNC_CONFIG_DIR="$CLAUDE_DIR/plugins-config"
SYNC_BACKUPS_DIR="$CLAUDE_DIR/sync-backups"

PLUGIN_KEY="${PLUGIN_NAME}@${PLUGIN_NAME}"

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║${NC}${BOLD}        Claude Settings Sync - Uninstaller                  ${NC}${RED}║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if jq is available
if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed."
    echo "Install with: brew install jq (macOS) or apt install jq (Linux)"
    exit 1
fi

# Confirm uninstall
echo -e "${YELLOW}This will remove:${NC}"
echo "  - claude-settings-sync plugin directory"
echo "  - Plugin entries from Claude Code settings"
echo "  - Sync configuration (token, gist ID)"
echo "  - Local backups"
echo ""
read -p "Are you sure you want to uninstall? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

# Remove from settings.json
log_info "Cleaning up settings.json..."
if [ -f "$SETTINGS_FILE" ]; then
    SETTINGS=$(cat "$SETTINGS_FILE")

    # Remove from extraKnownMarketplaces
    SETTINGS=$(echo "$SETTINGS" | jq --arg name "$PLUGIN_NAME" '
        if .extraKnownMarketplaces then
            .extraKnownMarketplaces |= del(.[$name])
        else . end |
        if .extraKnownMarketplaces == {} then del(.extraKnownMarketplaces) else . end
    ')

    # Remove from enabledPlugins
    SETTINGS=$(echo "$SETTINGS" | jq --arg plugin "$PLUGIN_KEY" '
        if .enabledPlugins then
            .enabledPlugins |= del(.[$plugin])
        else . end |
        if .enabledPlugins == {} then del(.enabledPlugins) else . end
    ')

    echo "$SETTINGS" | jq '.' > "$SETTINGS_FILE"
    log_success "Cleaned settings.json"
else
    log_warn "settings.json not found, skipping"
fi

# Remove from known_marketplaces.json
log_info "Cleaning up known_marketplaces.json..."
if [ -f "$KNOWN_MARKETPLACES_FILE" ]; then
    KNOWN=$(cat "$KNOWN_MARKETPLACES_FILE")
    KNOWN=$(echo "$KNOWN" | jq --arg name "$PLUGIN_NAME" 'del(.[$name])')
    echo "$KNOWN" | jq '.' > "$KNOWN_MARKETPLACES_FILE"
    log_success "Cleaned known_marketplaces.json"
else
    log_warn "known_marketplaces.json not found, skipping"
fi

# Remove from installed_plugins.json
log_info "Cleaning up installed_plugins.json..."
if [ -f "$INSTALLED_PLUGINS_FILE" ]; then
    INSTALLED=$(cat "$INSTALLED_PLUGINS_FILE")
    INSTALLED=$(echo "$INSTALLED" | jq --arg plugin "$PLUGIN_KEY" '
        if .plugins then
            .plugins |= del(.[$plugin])
        else . end
    ')
    echo "$INSTALLED" | jq '.' > "$INSTALLED_PLUGINS_FILE"
    log_success "Cleaned installed_plugins.json"
else
    log_warn "installed_plugins.json not found, skipping"
fi

# Remove sync config
log_info "Removing sync configuration..."
if [ -f "$SYNC_CONFIG_DIR/sync-config.json" ]; then
    rm -f "$SYNC_CONFIG_DIR/sync-config.json"
    log_success "Removed sync-config.json"
else
    log_warn "No sync config found, skipping"
fi

# Remove backups
log_info "Removing local backups..."
if [ -d "$SYNC_BACKUPS_DIR" ]; then
    rm -rf "$SYNC_BACKUPS_DIR"
    log_success "Removed sync-backups directory"
else
    log_warn "No backups found, skipping"
fi

# Remove plugin directory
log_info "Removing plugin directory..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    log_success "Removed $INSTALL_DIR"
else
    log_warn "Plugin directory not found, skipping"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}${BOLD}             Uninstall Complete!                            ${NC}${GREEN}║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Please restart Claude Code to complete the removal."
echo ""
echo -e "${CYAN}Note:${NC} Your GitHub Gist with synced settings was NOT deleted."
echo "To delete it, visit: https://gist.github.com"
echo ""

#!/bin/bash
# pull.sh - Pull settings from GitHub Gist (single compressed bundle)
# Version 2.0 - Handles new bundle format with fallback for large files via raw_url

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Parse arguments
FORCE=false
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --force) FORCE=true ;;
        --dry-run) DRY_RUN=true ;;
    esac
done

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}${BOLD}              Claude Settings Sync - Pull                   ${NC}${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check configuration
if ! config_exists; then
    log_error "Not configured. Run /claude-settings-sync:setup first."
    exit 1
fi

gist_id=$(get_config_value "gist_id")
if [ -z "$gist_id" ]; then
    log_error "Gist ID not found. Run /claude-settings-sync:setup first."
    exit 1
fi

# Check dependencies
if ! check_dependencies; then
    exit 1
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Fetch gist metadata
log_info "Fetching settings from Gist..."
gist_data=$(get_gist)

# Save gist data to temp file
echo "$gist_data" > "$TEMP_DIR/gist_metadata.json"

if ! jq -e '.files' "$TEMP_DIR/gist_metadata.json" > /dev/null 2>&1; then
    log_error "Failed to fetch gist"
    jq -r '.message // .' "$TEMP_DIR/gist_metadata.json" 2>/dev/null || cat "$TEMP_DIR/gist_metadata.json"
    exit 1
fi

# Check for bundle format (v2.0)
has_bundle=$(jq -e '.files["settings-bundle.tar.gz.b64"]' "$TEMP_DIR/gist_metadata.json" > /dev/null 2>&1 && echo "true" || echo "false")

if [ "$has_bundle" != "true" ]; then
    log_error "No settings bundle found in Gist."
    log_info "This Gist may be using an older format. Please push again to update."
    exit 1
fi

# Read manifest
manifest_content=$(jq -r '.files["manifest.json"].content // "{}"' "$TEMP_DIR/gist_metadata.json")
remote_version=$(echo "$manifest_content" | jq -r '.version // "unknown"')
remote_device=$(echo "$manifest_content" | jq -r '.device // "unknown"')
remote_time=$(echo "$manifest_content" | jq -r '.timestamp // "unknown"')
remote_items=$(echo "$manifest_content" | jq -r '.items // []')
bundle_size=$(echo "$manifest_content" | jq -r '.bundle_size_bytes // 0')
bundle_size_kb=$((bundle_size / 1024))

echo ""
log_info "Remote bundle info:"
echo "  Version: $remote_version"
echo "  Device: $remote_device"
echo "  Timestamp: $remote_time"
echo "  Bundle size: ${bundle_size_kb}KB"
echo "  Items: $(echo "$remote_items" | jq -r 'join(", ")')"
echo ""

# Dry run check
if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would pull and extract bundle to ~/.claude/"
    log_info "Items: $(echo "$remote_items" | jq -r 'join(", ")')"
    exit 0
fi

# Confirmation
if [ "$FORCE" != true ]; then
    log_warn "This will overwrite your local settings!"
    read -p "Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Pull cancelled."
        exit 0
    fi
fi

# Create backup before pull
log_info "Creating local backup..."
backup_path=$(create_backup "pre-pull")
log_success "Backup saved to: $backup_path"
cleanup_old_backups

# Get bundle content (handle truncated files via raw_url)
log_info "Downloading bundle..."

truncated=$(jq -r '.files["settings-bundle.tar.gz.b64"].truncated // false' "$TEMP_DIR/gist_metadata.json")

if [ "$truncated" = "true" ]; then
    # File is truncated, fetch from raw_url
    raw_url=$(jq -r '.files["settings-bundle.tar.gz.b64"].raw_url' "$TEMP_DIR/gist_metadata.json")
    log_info "Bundle truncated in API response, fetching full content..."
    curl -s "$raw_url" > "$TEMP_DIR/bundle.txt"
else
    # File is not truncated, extract from metadata
    jq -r '.files["settings-bundle.tar.gz.b64"].content // empty' "$TEMP_DIR/gist_metadata.json" > "$TEMP_DIR/bundle.txt"
fi

# Verify bundle was downloaded
if [ ! -s "$TEMP_DIR/bundle.txt" ]; then
    log_error "Failed to download bundle"
    exit 1
fi

downloaded_size=$(wc -c < "$TEMP_DIR/bundle.txt" | tr -d ' ')
log_success "Downloaded ${downloaded_size} bytes"

# Extract bundle
log_info "Extracting bundle..."

# Ensure target directories exist
mkdir -p "$CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR/skills"
mkdir -p "$CLAUDE_DIR/agents"
mkdir -p "$CLAUDE_DIR/commands"

# Extract using the utility function
if cat "$TEMP_DIR/bundle.txt" | extract_settings_bundle; then
    log_success "Bundle extracted successfully"
else
    log_error "Failed to extract bundle"
    exit 1
fi

# Show skills install guidance if manifest exists
if [ -f "$CLAUDE_DIR/skills-manifest.json" ]; then
    show_skills_install_guidance "$CLAUDE_DIR/skills-manifest.json"
fi

# Update last sync time
set_config_value "last_sync" "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
set_config_value "last_pull_from" "\"$remote_device\""

echo ""
log_success "Pull complete!"
echo ""
echo "  Source device: $remote_device"
echo "  Source time: $remote_time"
echo "  Items restored: $(echo "$remote_items" | jq -r 'join(", ")')"
echo "  Backup location: $backup_path"
echo ""
log_info "Restart Claude Code for changes to take effect."
echo ""

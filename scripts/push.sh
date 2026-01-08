#!/bin/bash
# push.sh - Push local settings to GitHub Gist
# Uses temp files to avoid "Argument list too long" errors

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
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              Claude Settings Sync - Push                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check configuration
if ! config_exists; then
    log_error "Not configured. Run /sync:setup first."
    exit 1
fi

gist_id=$(get_config_value "gist_id")
if [ -z "$gist_id" ]; then
    log_error "Gist ID not found. Run /sync:setup first."
    exit 1
fi

# Check dependencies
if ! check_dependencies; then
    exit 1
fi

# Create temp directory for building payload
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Initialize files payload
echo '{}' > "$TEMP_DIR/files_payload.json"

# Helper function to add file to payload using temp files
add_file_to_payload() {
    local filename="$1"
    local content_file="$2"

    # Escape content to JSON string and save to temp file
    jq -Rs . < "$content_file" > "$TEMP_DIR/content.json"

    # Merge into payload using file-based operations
    jq --arg name "$filename" --slurpfile content "$TEMP_DIR/content.json" \
        '.[$name] = {"content": $content[0]}' \
        "$TEMP_DIR/files_payload.json" > "$TEMP_DIR/files_payload_new.json"

    mv "$TEMP_DIR/files_payload_new.json" "$TEMP_DIR/files_payload.json"
}

# Collect files to sync
log_info "Collecting settings..."

# settings.json
if [ -f "$CLAUDE_DIR/settings.json" ]; then
    add_file_to_payload "settings.json" "$CLAUDE_DIR/settings.json"
    log_success "  settings.json"
fi

# CLAUDE.md
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    add_file_to_payload "CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
    log_success "  CLAUDE.md"
fi

# Skills directory
if [ -d "$CLAUDE_DIR/skills" ] && [ "$(ls -A "$CLAUDE_DIR/skills" 2>/dev/null)" ]; then
    pack_directory "$CLAUDE_DIR/skills" > "$TEMP_DIR/skills.tar.gz.b64"
    add_file_to_payload "skills.tar.gz.b64" "$TEMP_DIR/skills.tar.gz.b64"
    log_success "  skills/ ($(ls "$CLAUDE_DIR/skills" | wc -l | tr -d ' ') items)"
fi

# Agents directory
if [ -d "$CLAUDE_DIR/agents" ] && [ "$(ls -A "$CLAUDE_DIR/agents" 2>/dev/null)" ]; then
    pack_directory "$CLAUDE_DIR/agents" > "$TEMP_DIR/agents.tar.gz.b64"
    add_file_to_payload "agents.tar.gz.b64" "$TEMP_DIR/agents.tar.gz.b64"
    log_success "  agents/ ($(ls "$CLAUDE_DIR/agents" | wc -l | tr -d ' ') items)"
fi

# Commands directory
if [ -d "$CLAUDE_DIR/commands" ] && [ "$(ls -A "$CLAUDE_DIR/commands" 2>/dev/null)" ]; then
    pack_directory "$CLAUDE_DIR/commands" > "$TEMP_DIR/commands.tar.gz.b64"
    add_file_to_payload "commands.tar.gz.b64" "$TEMP_DIR/commands.tar.gz.b64"
    log_success "  commands/ ($(ls "$CLAUDE_DIR/commands" | wc -l | tr -d ' ') items)"
fi

# Create manifest
get_local_manifest > "$TEMP_DIR/manifest.json"
add_file_to_payload "manifest.json" "$TEMP_DIR/manifest.json"

# Check if anything to push
file_count=$(jq 'keys | length' "$TEMP_DIR/files_payload.json")
if [ "$file_count" -le 1 ]; then
    log_warn "No settings found to push."
    exit 0
fi

echo ""
log_info "Ready to push $file_count files to Gist: $gist_id"

# Dry run check
if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would push the following files:"
    jq -r 'keys[]' "$TEMP_DIR/files_payload.json"
    exit 0
fi

# Confirmation
if [ "$FORCE" != true ]; then
    read -p "Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Push cancelled."
        exit 0
    fi
fi

# Create backup before push
log_info "Creating local backup..."
backup_path=$(create_backup "pre-push")
log_success "Backup saved to: $backup_path"
cleanup_old_backups

# Build final payload
jq -n --slurpfile files "$TEMP_DIR/files_payload.json" '{"files": $files[0]}' > "$TEMP_DIR/payload.json"

# Push to Gist
log_info "Pushing to GitHub Gist..."
result=$(update_gist_from_file "$TEMP_DIR/payload.json")

if echo "$result" | jq -e '.id' > /dev/null 2>&1; then
    # Update last sync time
    set_config_value "last_sync" "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
    set_config_value "last_sync_device" "\"$(hostname)\""

    echo ""
    log_success "Push complete!"
    echo ""
    echo "  Gist URL: https://gist.github.com/$gist_id"
    echo "  Files pushed: $file_count"
    echo "  Timestamp: $(date)"
    echo ""
else
    log_error "Push failed"
    echo "$result" | jq -r '.message // .'
    exit 1
fi

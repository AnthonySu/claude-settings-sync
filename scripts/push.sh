#!/bin/bash
# push.sh - Push local settings to GitHub Gist

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

# Collect files to sync
log_info "Collecting settings..."

files_payload="{}"

# settings.json
if [ -f "$CLAUDE_DIR/settings.json" ]; then
    content=$(cat "$CLAUDE_DIR/settings.json" | jq -Rs .)
    files_payload=$(echo "$files_payload" | jq --argjson content "$content" '.["settings.json"] = {"content": $content}')
    log_success "  settings.json"
fi

# CLAUDE.md
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    content=$(cat "$CLAUDE_DIR/CLAUDE.md" | jq -Rs .)
    files_payload=$(echo "$files_payload" | jq --argjson content "$content" '.["CLAUDE.md"] = {"content": $content}')
    log_success "  CLAUDE.md"
fi

# Skills directory
if [ -d "$CLAUDE_DIR/skills" ] && [ "$(ls -A "$CLAUDE_DIR/skills" 2>/dev/null)" ]; then
    content=$(pack_directory "$CLAUDE_DIR/skills" | jq -Rs .)
    files_payload=$(echo "$files_payload" | jq --argjson content "$content" '.["skills.tar.gz.b64"] = {"content": $content}')
    log_success "  skills/ ($(ls "$CLAUDE_DIR/skills" | wc -l | tr -d ' ') items)"
fi

# Agents directory
if [ -d "$CLAUDE_DIR/agents" ] && [ "$(ls -A "$CLAUDE_DIR/agents" 2>/dev/null)" ]; then
    content=$(pack_directory "$CLAUDE_DIR/agents" | jq -Rs .)
    files_payload=$(echo "$files_payload" | jq --argjson content "$content" '.["agents.tar.gz.b64"] = {"content": $content}')
    log_success "  agents/ ($(ls "$CLAUDE_DIR/agents" | wc -l | tr -d ' ') items)"
fi

# Commands directory
if [ -d "$CLAUDE_DIR/commands" ] && [ "$(ls -A "$CLAUDE_DIR/commands" 2>/dev/null)" ]; then
    content=$(pack_directory "$CLAUDE_DIR/commands" | jq -Rs .)
    files_payload=$(echo "$files_payload" | jq --argjson content "$content" '.["commands.tar.gz.b64"] = {"content": $content}')
    log_success "  commands/ ($(ls "$CLAUDE_DIR/commands" | wc -l | tr -d ' ') items)"
fi

# Create manifest
manifest=$(get_local_manifest)
manifest_content=$(echo "$manifest" | jq -Rs .)
files_payload=$(echo "$files_payload" | jq --argjson content "$manifest_content" '.["manifest.json"] = {"content": $content}')

# Check if anything to push
file_count=$(echo "$files_payload" | jq 'keys | length')
if [ "$file_count" -le 1 ]; then
    log_warn "No settings found to push."
    exit 0
fi

echo ""
log_info "Ready to push $file_count files to Gist: $gist_id"

# Dry run check
if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would push the following files:"
    echo "$files_payload" | jq -r 'keys[]'
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
payload=$(jq -n --argjson files "$files_payload" '{"files": $files}')

# Push to Gist
log_info "Pushing to GitHub Gist..."
result=$(update_gist "$payload")

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

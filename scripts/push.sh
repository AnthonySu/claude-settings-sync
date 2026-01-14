#!/bin/bash
# push.sh - Push local settings to GitHub Gist as a single compressed bundle
# Version 2.0 - Uses single tarball for better compression and larger file support

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
echo -e "${CYAN}║${NC}${BOLD}              Claude Settings Sync - Push                   ${NC}${CYAN}║${NC}"
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

# Show what will be synced
log_info "Items to sync:"
item_count=0
for item in "${BUNDLE_ITEMS[@]}"; do
    src="$CLAUDE_DIR/$item"
    if [ -e "$src" ]; then
        if [ -d "$src" ]; then
            if [ "$(ls -A "$src" 2>/dev/null)" ]; then
                count=$(ls -1 "$src" 2>/dev/null | wc -l | tr -d ' ')
                size=$(du -sh "$src" 2>/dev/null | cut -f1)
                log_success "  $item/ ($count items, $size)"
                ((item_count++))
            fi
        else
            size=$(du -h "$src" 2>/dev/null | cut -f1)
            log_success "  $item ($size)"
            ((item_count++))
        fi
    else
        echo -e "  ${YELLOW}$item (not found)${NC}"
    fi
done

# Show skills info (synced as manifest only)
skill_count=0
if [ -d "$CLAUDE_DIR/skills" ] && [ "$(ls -A "$CLAUDE_DIR/skills" 2>/dev/null)" ]; then
    skill_count=$(ls -1d "$CLAUDE_DIR/skills"/*/ 2>/dev/null | wc -l | tr -d ' ')
    skills_size=$(du -sh "$CLAUDE_DIR/skills" 2>/dev/null | cut -f1)
    log_success "  skills/ ($skill_count skills, manifest only - full: $skills_size)"
    ((item_count++))
fi

if [ "$item_count" -eq 0 ]; then
    log_warn "No settings found to push."
    exit 0
fi

# Estimate bundle size
raw_size=$(get_bundle_size_estimate)
echo ""
log_info "Estimated raw size: ${raw_size}KB"
log_info "Creating compressed bundle (xz -9)..."

# Create the bundle
bundle_content=$(create_settings_bundle)
bundle_size=$(echo "$bundle_content" | wc -c | tr -d ' ')
bundle_size_kb=$((bundle_size / 1024))

log_success "Compressed bundle size: ${bundle_size_kb}KB (base64 encoded)"

# Dry run check
if [ "$DRY_RUN" = true ]; then
    echo ""
    log_info "[DRY RUN] Would push bundle to Gist: $gist_id"
    log_info "Bundle contains: ${BUNDLE_ITEMS[*]}"
    exit 0
fi

echo ""
log_info "Ready to push to Gist: $gist_id"

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

# Build payload with bundle as single file
log_info "Uploading to GitHub Gist..."

# Save bundle to temp file to avoid argument length issues
echo "$bundle_content" > "$TEMP_DIR/bundle.txt"

# Fetch existing gist to get sync history
log_info "Fetching existing sync history..."
existing_gist=$(get_gist 2>/dev/null || echo "{}")
existing_history=$(get_sync_history_from_gist "$existing_gist")
if [ -z "$existing_history" ] || [ "$existing_history" = "null" ]; then
    existing_history="[]"
fi

# Create new history entry
push_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
new_entry=$(create_history_entry "$(hostname)" "$push_timestamp" "$bundle_size_kb" "$skill_count")
updated_history=$(append_to_sync_history "$existing_history" "$new_entry" 10)

# Create manifest for the gist (separate from bundle metadata)
cat > "$TEMP_DIR/manifest.json" << EOF
{
    "version": "2.1.0",
    "format": "bundle",
    "device": "$(hostname)",
    "timestamp": "$push_timestamp",
    "items": $(printf '%s\n' "${BUNDLE_ITEMS[@]}" | jq -R . | jq -s .),
    "bundle_size_bytes": $bundle_size,
    "skill_count": $skill_count
}
EOF

# Save sync history
echo "$updated_history" | jq '.' > "$TEMP_DIR/sync-history.json"

# Build the gist payload using file-based operations (avoids argument length limits)
# First create the JSON structure with manifest and history
jq -n --arg manifest "$(cat "$TEMP_DIR/manifest.json")" \
      --arg history "$(cat "$TEMP_DIR/sync-history.json")" \
    '{"files": {"manifest.json": {"content": $manifest}, "sync-history.json": {"content": $history}}}' > "$TEMP_DIR/payload.json"

# Add bundle content using slurpfile to avoid argument limits
jq --slurpfile bundle <(jq -Rs . < "$TEMP_DIR/bundle.txt") \
    '.files["settings-bundle.tar.gz.b64"] = {"content": $bundle[0]}' \
    "$TEMP_DIR/payload.json" > "$TEMP_DIR/payload_final.json"
mv "$TEMP_DIR/payload_final.json" "$TEMP_DIR/payload.json"

# Push to Gist
result=$(update_gist_from_file "$TEMP_DIR/payload.json")

if echo "$result" | jq -e '.id' > /dev/null 2>&1; then
    # Update last sync time
    set_config_value "last_sync" "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
    set_config_value "last_sync_device" "\"$(hostname)\""

    echo ""
    log_success "Push complete!"
    echo ""
    echo "  Gist URL: https://gist.github.com/$gist_id"
    echo "  Items synced: $item_count"
    echo "  Bundle size: ${bundle_size_kb}KB"
    echo "  Timestamp: $(date)"
    echo ""
else
    log_error "Push failed"
    echo "$result" | jq -r '.message // .' 2>/dev/null || echo "$result"
    exit 1
fi

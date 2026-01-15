#!/bin/bash
# pull.sh - Pull settings from GitHub Gist (single compressed bundle)
# Version 2.0 - Handles new bundle format with fallback for large files via raw_url

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Parse arguments
FORCE=false
DRY_RUN=false
SHOW_DIFF=false
ONLY_ITEMS=()
for arg in "$@"; do
    case $arg in
        --force) FORCE=true ;;
        --dry-run) DRY_RUN=true ;;
        --diff) SHOW_DIFF=true ;;
        --only=*) IFS=',' read -ra ONLY_ITEMS <<< "${arg#*=}" ;;
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

# Validate --only items if specified
if [ ${#ONLY_ITEMS[@]} -gt 0 ]; then
    if ! validate_only_items "${ONLY_ITEMS[@]}"; then
        exit 1
    fi
    log_info "Selective pull: ${ONLY_ITEMS[*]}"
    echo ""
fi

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

# Conflict detection
log_info "Checking for conflicts..."
local_modified=$(get_local_modified_time)
last_sync=$(get_config_value "last_sync")

if [ -n "$local_modified" ] && [ -n "$last_sync" ]; then
    sync_status=$(compare_sync_times "$local_modified" "$last_sync")
    if [ "$sync_status" = "local_newer" ]; then
        echo ""
        log_warn "Local settings modified since last sync!"
        echo "  Local modified: $local_modified"
        echo "  Last sync: $last_sync"
        echo ""
        log_warn "You have local changes that will be overwritten."
        if [ "$FORCE" != true ] && [ "$SHOW_DIFF" != true ]; then
            read -p "Pull anyway? Use --diff to preview changes. (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                log_info "Pull cancelled. Consider pushing first to save local changes."
                exit 0
            fi
        fi
    else
        log_success "No conflicts detected"
    fi
fi

# Diff preview mode
if [ "$SHOW_DIFF" = true ]; then
    echo ""
    log_info "Previewing changes (--diff mode)..."
    echo ""

    # Download and extract to temp for comparison
    truncated=$(jq -r '.files["settings-bundle.tar.gz.b64"].truncated // false' "$TEMP_DIR/gist_metadata.json")
    if [ "$truncated" = "true" ]; then
        raw_url=$(jq -r '.files["settings-bundle.tar.gz.b64"].raw_url' "$TEMP_DIR/gist_metadata.json")
        curl -s "$raw_url" > "$TEMP_DIR/bundle.txt"
    else
        jq -r '.files["settings-bundle.tar.gz.b64"].content // empty' "$TEMP_DIR/gist_metadata.json" > "$TEMP_DIR/bundle.txt"
    fi

    # Extract to temp
    mkdir -p "$TEMP_DIR/remote"
    cat "$TEMP_DIR/bundle.txt" | base64 -d | xz -d | tar -xf - -C "$TEMP_DIR/remote" 2>/dev/null

    echo "┌─ File Comparison ───────────────────────────────────────────┐"
    for item in "${BUNDLE_ITEMS[@]}"; do
        local_path="$CLAUDE_DIR/$item"
        remote_path="$TEMP_DIR/remote/claude-settings/$item"

        if [ -f "$local_path" ] && [ -f "$remote_path" ]; then
            if diff -q "$local_path" "$remote_path" > /dev/null 2>&1; then
                echo -e "│ ${GREEN}=${NC} $item (unchanged)"
            else
                echo -e "│ ${YELLOW}~${NC} $item (modified)"
                # Show line count diff
                local_lines=$(wc -l < "$local_path" | tr -d ' ')
                remote_lines=$(wc -l < "$remote_path" | tr -d ' ')
                echo "│     Local: $local_lines lines, Remote: $remote_lines lines"
            fi
        elif [ -f "$remote_path" ]; then
            echo -e "│ ${GREEN}+${NC} $item (new from remote)"
        elif [ -f "$local_path" ]; then
            echo -e "│ ${RED}-${NC} $item (exists locally, not in remote)"
        fi

        # Handle directories
        if [ -d "$local_path" ] && [ -d "$remote_path" ]; then
            local_count=$(find "$local_path" -type f 2>/dev/null | wc -l | tr -d ' ')
            remote_count=$(find "$remote_path" -type f 2>/dev/null | wc -l | tr -d ' ')
            if [ "$local_count" -eq "$remote_count" ]; then
                echo -e "│ ${GREEN}=${NC} $item/ ($local_count files)"
            else
                echo -e "│ ${YELLOW}~${NC} $item/ (local: $local_count, remote: $remote_count files)"
            fi
        elif [ -d "$remote_path" ]; then
            remote_count=$(find "$remote_path" -type f 2>/dev/null | wc -l | tr -d ' ')
            echo -e "│ ${GREEN}+${NC} $item/ (new: $remote_count files)"
        fi
    done
    echo "└──────────────────────────────────────────────────────────────┘"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN + DIFF] No changes made."
        exit 0
    fi

    read -p "Apply these changes? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Pull cancelled."
        exit 0
    fi
fi

# Dry run check (without diff)
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

# Extract using the utility function (with optional filter)
if [ ${#ONLY_ITEMS[@]} -gt 0 ]; then
    log_info "Extracting only: ${ONLY_ITEMS[*]}"
    if cat "$TEMP_DIR/bundle.txt" | extract_settings_bundle "${ONLY_ITEMS[@]}"; then
        log_success "Selected items extracted successfully"
    else
        log_error "Failed to extract bundle"
        exit 1
    fi
else
    if cat "$TEMP_DIR/bundle.txt" | extract_settings_bundle; then
        log_success "Bundle extracted successfully"
    else
        log_error "Failed to extract bundle"
        exit 1
    fi
fi

# Show skills install guidance if manifest exists and skills was pulled
show_skills_guidance=true
if [ ${#ONLY_ITEMS[@]} -gt 0 ]; then
    show_skills_guidance=false
    for item in "${ONLY_ITEMS[@]}"; do
        if [ "$item" = "skills" ]; then
            show_skills_guidance=true
            break
        fi
    done
fi

if [ "$show_skills_guidance" = true ] && [ -f "$CLAUDE_DIR/skills-manifest.json" ]; then
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

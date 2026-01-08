#!/bin/bash
# pull.sh - Pull settings from GitHub Gist
# Handles truncated files by fetching from raw_url

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

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Fetch gist metadata
log_info "Fetching settings from Gist..."
gist_data=$(get_gist)

# Save gist data to temp file to avoid parsing issues with large content
echo "$gist_data" > "$TEMP_DIR/gist_metadata.json"

if ! jq -e '.files' "$TEMP_DIR/gist_metadata.json" > /dev/null 2>&1; then
    log_error "Failed to fetch gist"
    jq -r '.message // .' "$TEMP_DIR/gist_metadata.json" 2>/dev/null || cat "$TEMP_DIR/gist_metadata.json"
    exit 1
fi

# Check what's available
log_info "Available in Gist:"
available_files=$(jq -r '.files | keys[]' "$TEMP_DIR/gist_metadata.json")
for f in $available_files; do
    if [[ "$f" != "manifest.json" ]]; then
        echo "  - $f"
    fi
done

# Check manifest
remote_manifest=$(jq -r '.files["manifest.json"].content // "{}"' "$TEMP_DIR/gist_metadata.json")
remote_device=$(echo "$remote_manifest" | jq -r '.device // "unknown"')
remote_time=$(echo "$remote_manifest" | jq -r '.timestamp // "unknown"')

echo ""
log_info "Last pushed from: $remote_device"
log_info "Last push time: $remote_time"
echo ""

# Dry run check
if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would pull the following files:"
    for f in $available_files; do
        case "$f" in
            "settings.json") echo "  settings.json -> ~/.claude/settings.json" ;;
            "CLAUDE.md") echo "  CLAUDE.md -> ~/.claude/CLAUDE.md" ;;
            "skills.tar.gz.b64") echo "  skills.tar.gz.b64 -> ~/.claude/skills/" ;;
            "agents.tar.gz.b64") echo "  agents.tar.gz.b64 -> ~/.claude/agents/" ;;
            "commands.tar.gz.b64") echo "  commands.tar.gz.b64 -> ~/.claude/commands/" ;;
        esac
    done
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

# Ensure directories exist
mkdir -p "$CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR/skills"
mkdir -p "$CLAUDE_DIR/agents"
mkdir -p "$CLAUDE_DIR/commands"

# Helper function to get file content (handles truncated files)
get_file_content() {
    local filename="$1"
    local output_file="$2"

    local truncated=$(jq -r ".files[\"$filename\"].truncated // false" "$TEMP_DIR/gist_metadata.json")

    if [ "$truncated" = "true" ]; then
        # File is truncated, fetch from raw_url
        local raw_url=$(jq -r ".files[\"$filename\"].raw_url" "$TEMP_DIR/gist_metadata.json")
        curl -s "$raw_url" > "$output_file"
    else
        # File is not truncated, extract from metadata
        jq -r ".files[\"$filename\"].content // empty" "$TEMP_DIR/gist_metadata.json" > "$output_file"
    fi
}

# Pull files
pulled_count=0

# settings.json
if jq -e '.files["settings.json"]' "$TEMP_DIR/gist_metadata.json" > /dev/null 2>&1; then
    get_file_content "settings.json" "$TEMP_DIR/settings.json"
    if [ -s "$TEMP_DIR/settings.json" ]; then
        # Try to parse as JSON, if fails just copy as-is
        if jq -e '.' "$TEMP_DIR/settings.json" > /dev/null 2>&1; then
            cp "$TEMP_DIR/settings.json" "$CLAUDE_DIR/settings.json"
        else
            cp "$TEMP_DIR/settings.json" "$CLAUDE_DIR/settings.json"
        fi
        log_success "Pulled settings.json"
        ((pulled_count++))
    fi
fi

# CLAUDE.md
if jq -e '.files["CLAUDE.md"]' "$TEMP_DIR/gist_metadata.json" > /dev/null 2>&1; then
    get_file_content "CLAUDE.md" "$TEMP_DIR/CLAUDE.md"
    if [ -s "$TEMP_DIR/CLAUDE.md" ]; then
        cp "$TEMP_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
        log_success "Pulled CLAUDE.md"
        ((pulled_count++))
    fi
fi

# Skills directory
if jq -e '.files["skills.tar.gz.b64"]' "$TEMP_DIR/gist_metadata.json" > /dev/null 2>&1; then
    get_file_content "skills.tar.gz.b64" "$TEMP_DIR/skills.tar.gz.b64"
    if [ -s "$TEMP_DIR/skills.tar.gz.b64" ]; then
        # Clear existing skills
        rm -rf "$CLAUDE_DIR/skills"
        mkdir -p "$CLAUDE_DIR/skills"
        # Decode and extract
        if base64 -d < "$TEMP_DIR/skills.tar.gz.b64" | tar -xzf - -C "$CLAUDE_DIR" 2>/dev/null; then
            log_success "Pulled skills/"
            ((pulled_count++))
        else
            log_warn "Failed to unpack skills/"
        fi
    fi
fi

# Agents directory
if jq -e '.files["agents.tar.gz.b64"]' "$TEMP_DIR/gist_metadata.json" > /dev/null 2>&1; then
    get_file_content "agents.tar.gz.b64" "$TEMP_DIR/agents.tar.gz.b64"
    if [ -s "$TEMP_DIR/agents.tar.gz.b64" ]; then
        rm -rf "$CLAUDE_DIR/agents"
        mkdir -p "$CLAUDE_DIR/agents"
        if base64 -d < "$TEMP_DIR/agents.tar.gz.b64" | tar -xzf - -C "$CLAUDE_DIR" 2>/dev/null; then
            log_success "Pulled agents/"
            ((pulled_count++))
        else
            log_warn "Failed to unpack agents/"
        fi
    fi
fi

# Commands directory
if jq -e '.files["commands.tar.gz.b64"]' "$TEMP_DIR/gist_metadata.json" > /dev/null 2>&1; then
    get_file_content "commands.tar.gz.b64" "$TEMP_DIR/commands.tar.gz.b64"
    if [ -s "$TEMP_DIR/commands.tar.gz.b64" ]; then
        rm -rf "$CLAUDE_DIR/commands"
        mkdir -p "$CLAUDE_DIR/commands"
        if base64 -d < "$TEMP_DIR/commands.tar.gz.b64" | tar -xzf - -C "$CLAUDE_DIR" 2>/dev/null; then
            log_success "Pulled commands/"
            ((pulled_count++))
        else
            log_warn "Failed to unpack commands/"
        fi
    fi
fi

# Update last sync time
set_config_value "last_sync" "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
set_config_value "last_pull_from" "\"$remote_device\""

echo ""
log_success "Pull complete!"
echo ""
echo "  Files pulled: $pulled_count"
echo "  Source device: $remote_device"
echo "  Backup location: $backup_path"
echo ""
log_info "Restart Claude Code for changes to take effect."
echo ""

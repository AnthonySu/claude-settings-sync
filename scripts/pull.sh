#!/bin/bash
# pull.sh - Pull settings from GitHub Gist

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
echo "║              Claude Settings Sync - Pull                   ║"
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

# Fetch gist
log_info "Fetching settings from Gist..."
gist_data=$(get_gist)

if ! echo "$gist_data" | jq -e '.files' > /dev/null 2>&1; then
    log_error "Failed to fetch gist"
    echo "$gist_data" | jq -r '.message // .'
    exit 1
fi

# Check what's available
log_info "Available in Gist:"
available_files=$(echo "$gist_data" | jq -r '.files | keys[]')
for f in $available_files; do
    if [[ "$f" != "manifest.json" ]]; then
        echo "  - $f"
    fi
done

# Check manifest
remote_manifest=$(echo "$gist_data" | jq -r '.files["manifest.json"].content // "{}"')
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

# Pull files
pulled_count=0

# settings.json
settings_content=$(echo "$gist_data" | jq -r '.files["settings.json"].content // empty')
if [ -n "$settings_content" ]; then
    # The content is JSON-escaped, need to unescape
    echo "$settings_content" | jq -r '.' > "$CLAUDE_DIR/settings.json" 2>/dev/null || \
    echo "$settings_content" > "$CLAUDE_DIR/settings.json"
    log_success "Pulled settings.json"
    ((pulled_count++))
fi

# CLAUDE.md
claude_md_content=$(echo "$gist_data" | jq -r '.files["CLAUDE.md"].content // empty')
if [ -n "$claude_md_content" ]; then
    echo "$claude_md_content" > "$CLAUDE_DIR/CLAUDE.md"
    log_success "Pulled CLAUDE.md"
    ((pulled_count++))
fi

# Skills directory
skills_content=$(echo "$gist_data" | jq -r '.files["skills.tar.gz.b64"].content // empty')
if [ -n "$skills_content" ]; then
    # Clear existing skills
    rm -rf "$CLAUDE_DIR/skills"
    mkdir -p "$CLAUDE_DIR/skills"
    if unpack_directory "$skills_content" "$CLAUDE_DIR/skills"; then
        log_success "Pulled skills/"
        ((pulled_count++))
    else
        log_warn "Failed to unpack skills/"
    fi
fi

# Agents directory
agents_content=$(echo "$gist_data" | jq -r '.files["agents.tar.gz.b64"].content // empty')
if [ -n "$agents_content" ]; then
    rm -rf "$CLAUDE_DIR/agents"
    mkdir -p "$CLAUDE_DIR/agents"
    if unpack_directory "$agents_content" "$CLAUDE_DIR/agents"; then
        log_success "Pulled agents/"
        ((pulled_count++))
    else
        log_warn "Failed to unpack agents/"
    fi
fi

# Commands directory
commands_content=$(echo "$gist_data" | jq -r '.files["commands.tar.gz.b64"].content // empty')
if [ -n "$commands_content" ]; then
    rm -rf "$CLAUDE_DIR/commands"
    mkdir -p "$CLAUDE_DIR/commands"
    if unpack_directory "$commands_content" "$CLAUDE_DIR/commands"; then
        log_success "Pulled commands/"
        ((pulled_count++))
    else
        log_warn "Failed to unpack commands/"
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

#!/bin/bash
# restore.sh - Restore settings from a local backup
# Quick way to recover from a bad pull or other issues

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Parse arguments
BACKUP_NAME=""
LIST_ONLY=false
SHOW_HELP=false
for arg in "$@"; do
    case $arg in
        --list) LIST_ONLY=true ;;
        --help|-h) SHOW_HELP=true ;;
        --backup=*) BACKUP_NAME="${arg#*=}" ;;
        backup_*) BACKUP_NAME="$arg" ;;
    esac
done

# Validate backup name (prevent path traversal)
if [ -n "$BACKUP_NAME" ]; then
    # Reject path traversal attempts
    if [[ "$BACKUP_NAME" == *".."* ]]; then
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}${BOLD}            Claude Settings Sync - Restore                  ${NC}${CYAN}║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        log_error "Invalid backup name: path traversal not allowed"
        exit 1
    fi
    # Reject absolute paths
    if [[ "$BACKUP_NAME" == /* ]]; then
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}${BOLD}            Claude Settings Sync - Restore                  ${NC}${CYAN}║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        log_error "Invalid backup name: absolute paths not allowed"
        exit 1
    fi
    # Reject names with slashes (subdirectories)
    if [[ "$BACKUP_NAME" == *"/"* ]]; then
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}${BOLD}            Claude Settings Sync - Restore                  ${NC}${CYAN}║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        log_error "Invalid backup name: must be a simple directory name"
        exit 1
    fi
fi

# Show help
if [ "$SHOW_HELP" = true ]; then
    echo "Usage: restore.sh [OPTIONS] [BACKUP_NAME]"
    echo ""
    echo "Restore Claude Code settings from a local backup."
    echo ""
    echo "Options:"
    echo "  --list    List all available backups"
    echo "  --help    Show this help message"
    echo ""
    echo "If no BACKUP_NAME is specified, shows interactive selection."
    echo ""
    exit 0
fi

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}${BOLD}            Claude Settings Sync - Restore                  ${NC}${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    if [ "$LIST_ONLY" = true ]; then
        log_info "No backups found (backup directory does not exist)"
        log_info "Backups are created automatically before push and pull operations."
        exit 0
    else
        log_error "No backup directory found at $BACKUP_DIR"
        log_info "Backups are created automatically before push and pull operations."
        exit 1
    fi
fi

# List available backups
backups=($(ls -1d "$BACKUP_DIR"/backup_* 2>/dev/null | sort -r))

if [ ${#backups[@]} -eq 0 ]; then
    if [ "$LIST_ONLY" = true ]; then
        log_info "No backups found"
        log_info "Backups are created automatically before push and pull operations."
        exit 0
    else
        log_error "No backups found"
        exit 1
    fi
fi

# List mode
if [ "$LIST_ONLY" = true ]; then
    log_info "Available backups:"
    echo ""
    for i in "${!backups[@]}"; do
        backup="${backups[$i]}"
        name=$(basename "$backup")

        # Read metadata if exists
        if [ -f "$backup/metadata.json" ]; then
            timestamp=$(jq -r '.timestamp // "unknown"' "$backup/metadata.json")
            device=$(jq -r '.device // "unknown"' "$backup/metadata.json")
            reason=$(jq -r '.reason // "manual"' "$backup/metadata.json")
        else
            timestamp="unknown"
            device="unknown"
            reason="unknown"
        fi

        # Count files in backup
        file_count=$(find "$backup" -type f -name "*.json" -o -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
        dir_count=$(find "$backup" -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')

        echo "  [$((i+1))] $name"
        echo "      Created: $timestamp"
        echo "      Device: $device"
        echo "      Reason: $reason"
        echo ""
    done
    exit 0
fi

# Interactive selection if no backup specified
if [ -z "$BACKUP_NAME" ]; then
    log_info "Available backups (most recent first):"
    echo ""

    # Show last 5 backups
    show_count=5
    if [ ${#backups[@]} -lt $show_count ]; then
        show_count=${#backups[@]}
    fi

    for i in $(seq 0 $((show_count - 1))); do
        backup="${backups[$i]}"
        name=$(basename "$backup")

        if [ -f "$backup/metadata.json" ]; then
            timestamp=$(jq -r '.timestamp // "unknown"' "$backup/metadata.json")
            reason=$(jq -r '.reason // "manual"' "$backup/metadata.json")
        else
            timestamp="unknown"
            reason="unknown"
        fi

        echo "  [$((i+1))] $name ($reason)"
    done

    if [ ${#backups[@]} -gt 5 ]; then
        echo "  ... and $((${#backups[@]} - 5)) more (use --list to see all)"
    fi

    echo ""
    read -p "Select backup to restore (1-$show_count): " selection

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "$show_count" ]; then
        log_error "Invalid selection"
        exit 1
    fi

    BACKUP_NAME=$(basename "${backups[$((selection-1))]}")
fi

# Find the backup
backup_path="$BACKUP_DIR/$BACKUP_NAME"
if [ ! -d "$backup_path" ]; then
    log_error "Backup not found: $BACKUP_NAME"
    exit 1
fi

log_info "Restoring from: $BACKUP_NAME"

# Show what will be restored
echo ""
echo "┌─ Backup Contents ──────────────────────────────────────────┐"
[ -f "$backup_path/settings.json" ] && echo "│ ✓ settings.json"
[ -f "$backup_path/CLAUDE.md" ] && echo "│ ✓ CLAUDE.md"
[ -f "$backup_path/mcp-servers.json" ] && echo "│ ✓ mcp-servers.json"
[ -d "$backup_path/skills" ] && echo "│ ✓ skills/ ($(ls -1 "$backup_path/skills" 2>/dev/null | wc -l | tr -d ' ') items)"
[ -d "$backup_path/agents" ] && echo "│ ✓ agents/ ($(ls -1 "$backup_path/agents" 2>/dev/null | wc -l | tr -d ' ') items)"
[ -d "$backup_path/commands" ] && echo "│ ✓ commands/ ($(ls -1 "$backup_path/commands" 2>/dev/null | wc -l | tr -d ' ') items)"
echo "└──────────────────────────────────────────────────────────────┘"
echo ""

# Confirmation
read -p "Restore these files? This will overwrite current settings. (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_info "Restore cancelled."
    exit 0
fi

# Create a backup of current state before restore
log_info "Creating backup of current state..."
pre_restore_backup=$(create_backup "pre-restore")
log_success "Current state backed up to: $pre_restore_backup"

# Restore files
log_info "Restoring files..."

[ -f "$backup_path/settings.json" ] && cp "$backup_path/settings.json" "$CLAUDE_DIR/"
[ -f "$backup_path/CLAUDE.md" ] && cp "$backup_path/CLAUDE.md" "$CLAUDE_DIR/"
[ -f "$backup_path/mcp-servers.json" ] && cp "$backup_path/mcp-servers.json" "$HOME/.claude.json"

# Restore directories
if [ -d "$backup_path/skills" ]; then
    rm -rf "$CLAUDE_DIR/skills"
    cp -r "$backup_path/skills" "$CLAUDE_DIR/"
fi

if [ -d "$backup_path/agents" ]; then
    rm -rf "$CLAUDE_DIR/agents"
    cp -r "$backup_path/agents" "$CLAUDE_DIR/"
fi

if [ -d "$backup_path/commands" ]; then
    rm -rf "$CLAUDE_DIR/commands"
    cp -r "$backup_path/commands" "$CLAUDE_DIR/"
fi

echo ""
log_success "Restore complete!"
echo ""
echo "  Restored from: $BACKUP_NAME"
echo "  Previous state saved to: $(basename "$pre_restore_backup")"
echo ""
log_info "Restart Claude Code for changes to take effect."
echo ""

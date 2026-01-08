#!/bin/bash
# status.sh - Show sync status and configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}${BOLD}             Claude Settings Sync - Status                  ${NC}${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check configuration
if ! config_exists; then
    log_error "Not configured."
    echo ""
    echo "Run /sync:setup to configure settings sync."
    exit 1
fi

# === Configuration ===
echo "┌─ Configuration ─────────────────────────────────────────────┐"

gist_id=$(get_config_value "gist_id")
last_sync=$(get_config_value "last_sync")
last_device=$(get_config_value "last_sync_device")
device_name=$(get_config_value "device_name")

# Validate token and get username
token=$(get_config_value "github_token")
if [ -n "$token" ]; then
    username=$(validate_token "$token" 2>/dev/null)
    if [ -n "$username" ]; then
        echo "│ GitHub User:    $username"
    else
        echo "│ GitHub User:    (token invalid or expired)"
    fi
fi

echo "│ Gist ID:        ${gist_id:-not set}"
echo "│ Gist URL:       https://gist.github.com/$gist_id"
echo "│ This Device:    ${device_name:-$(hostname)}"
echo "│ Last Sync:      ${last_sync:-never}"
echo "│ Last Sync From: ${last_device:-N/A}"
echo "└──────────────────────────────────────────────────────────────┘"
echo ""

# === Local Files ===
echo "┌─ Local Files ────────────────────────────────────────────────┐"

check_file() {
    local path="$1"
    local name="$2"
    if [ -f "$path" ]; then
        local size=$(ls -lh "$path" 2>/dev/null | awk '{print $5}')
        local modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$path" 2>/dev/null || stat -c "%y" "$path" 2>/dev/null | cut -d. -f1)
        echo "│ ✓ $name ($size, $modified)"
    else
        echo "│ ✗ $name (not found)"
    fi
}

check_dir() {
    local path="$1"
    local name="$2"
    if [ -d "$path" ] && [ "$(ls -A "$path" 2>/dev/null)" ]; then
        local count=$(ls -1 "$path" 2>/dev/null | wc -l | tr -d ' ')
        echo "│ ✓ $name/ ($count items)"
    elif [ -d "$path" ]; then
        echo "│ ○ $name/ (empty)"
    else
        echo "│ ✗ $name/ (not found)"
    fi
}

check_file "$CLAUDE_DIR/settings.json" "settings.json"
check_file "$CLAUDE_DIR/CLAUDE.md" "CLAUDE.md"
check_dir "$CLAUDE_DIR/skills" "skills"
check_dir "$CLAUDE_DIR/agents" "agents"
check_dir "$CLAUDE_DIR/commands" "commands"

echo "└──────────────────────────────────────────────────────────────┘"
echo ""

# === Remote Status ===
echo "┌─ Remote (Gist) ──────────────────────────────────────────────┐"

if [ -n "$gist_id" ]; then
    gist_data=$(get_gist 2>/dev/null)

    if echo "$gist_data" | jq -e '.files' > /dev/null 2>&1; then
        # Get manifest
        manifest=$(echo "$gist_data" | jq -r '.files["manifest.json"].content // "{}"')
        remote_device=$(echo "$manifest" | jq -r '.device // "unknown"')
        remote_time=$(echo "$manifest" | jq -r '.timestamp // "unknown"')

        echo "│ Last pushed by: $remote_device"
        echo "│ Push time:      $remote_time"
        echo "│"

        # List files
        echo "│ Files in Gist:"
        for f in $(echo "$gist_data" | jq -r '.files | keys[]'); do
            if [[ "$f" != "manifest.json" ]]; then
                size=$(echo "$gist_data" | jq -r ".files[\"$f\"].size")
                echo "│   • $f ($size bytes)"
            fi
        done
    else
        echo "│ Error fetching gist: $(echo "$gist_data" | jq -r '.message // "unknown error"')"
    fi
else
    echo "│ No Gist configured"
fi

echo "└──────────────────────────────────────────────────────────────┘"
echo ""

# === Sync Status ===
echo "┌─ Sync Comparison ─────────────────────────────────────────────┐"

if [ -n "$gist_id" ] && echo "$gist_data" | jq -e '.files' > /dev/null 2>&1; then
    # Compare hashes
    local_manifest=$(get_local_manifest)
    remote_manifest=$(echo "$gist_data" | jq -r '.files["manifest.json"].content // "{}"')

    local_settings_hash=$(echo "$local_manifest" | jq -r '.hashes.settings // ""')
    remote_settings_raw=$(echo "$gist_data" | jq -r '.files["settings.json"].content // ""')

    # Simple comparison - check if files exist in both places
    has_diff=false

    # Check settings.json
    if [ -f "$CLAUDE_DIR/settings.json" ]; then
        if echo "$gist_data" | jq -e '.files["settings.json"]' > /dev/null 2>&1; then
            echo "│ settings.json:  Local ✓  Remote ✓"
        else
            echo "│ settings.json:  Local ✓  Remote ✗  (needs push)"
            has_diff=true
        fi
    else
        if echo "$gist_data" | jq -e '.files["settings.json"]' > /dev/null 2>&1; then
            echo "│ settings.json:  Local ✗  Remote ✓  (needs pull)"
            has_diff=true
        fi
    fi

    # Check CLAUDE.md
    if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
        if echo "$gist_data" | jq -e '.files["CLAUDE.md"]' > /dev/null 2>&1; then
            echo "│ CLAUDE.md:      Local ✓  Remote ✓"
        else
            echo "│ CLAUDE.md:      Local ✓  Remote ✗  (needs push)"
            has_diff=true
        fi
    else
        if echo "$gist_data" | jq -e '.files["CLAUDE.md"]' > /dev/null 2>&1; then
            echo "│ CLAUDE.md:      Local ✗  Remote ✓  (needs pull)"
            has_diff=true
        fi
    fi

    # Check directories
    for item in skills agents commands; do
        local_exists=false
        remote_exists=false
        [ -d "$CLAUDE_DIR/$item" ] && [ "$(ls -A "$CLAUDE_DIR/$item" 2>/dev/null)" ] && local_exists=true
        echo "$gist_data" | jq -e ".files[\"$item.tar.gz.b64\"]" > /dev/null 2>&1 && remote_exists=true

        if $local_exists && $remote_exists; then
            printf "│ %-15s Local ✓  Remote ✓\n" "$item/:"
        elif $local_exists; then
            printf "│ %-15s Local ✓  Remote ✗  (needs push)\n" "$item/:"
            has_diff=true
        elif $remote_exists; then
            printf "│ %-15s Local ✗  Remote ✓  (needs pull)\n" "$item/:"
            has_diff=true
        fi
    done

    echo "│"
    if $has_diff; then
        echo "│ Status: OUT OF SYNC"
    else
        echo "│ Status: IN SYNC (content may still differ)"
    fi
else
    echo "│ Cannot compare - remote not accessible"
fi

echo "└──────────────────────────────────────────────────────────────┘"
echo ""

# === Backups ===
echo "┌─ Local Backups ──────────────────────────────────────────────┐"

if [ -d "$BACKUP_DIR" ]; then
    backup_count=$(ls -1d "$BACKUP_DIR"/backup_* 2>/dev/null | wc -l | tr -d ' ')
    if [ "$backup_count" -gt 0 ]; then
        echo "│ Found $backup_count backup(s):"
        ls -1d "$BACKUP_DIR"/backup_* 2>/dev/null | tail -3 | while read backup; do
            name=$(basename "$backup")
            echo "│   • $name"
        done
        if [ "$backup_count" -gt 3 ]; then
            echo "│   ... and $((backup_count - 3)) more"
        fi
    else
        echo "│ No backups found"
    fi
else
    echo "│ Backup directory not created yet"
fi

echo "└──────────────────────────────────────────────────────────────┘"
echo ""

# === Quick Actions ===
echo "Quick actions:"
echo "  /sync:push   - Upload local settings to Gist"
echo "  /sync:pull   - Download settings from Gist"
echo "  /sync:setup  - Reconfigure sync"
echo ""

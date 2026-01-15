#!/bin/bash
# status.sh - Show sync status and configuration
# Version 2.0 - Updated for bundle format

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Get plugin version
get_plugin_version() {
    if [ -f "$PLUGIN_DIR/VERSION" ]; then
        cat "$PLUGIN_DIR/VERSION" | tr -d '[:space:]'
    else
        echo "unknown"
    fi
}

PLUGIN_VERSION=$(get_plugin_version)

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}${BOLD}         Claude Settings Sync - Status (v$PLUGIN_VERSION)           ${NC}${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check configuration
if ! config_exists; then
    log_error "Not configured."
    echo ""
    echo "Run /claude-settings-sync:setup to configure settings sync."
    exit 1
fi

# Check config is valid JSON
if ! config_is_valid; then
    log_error "Configuration file is corrupted or invalid."
    echo ""
    echo "Run /claude-settings-sync:setup to reconfigure."
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
        local size=$(du -sh "$path" 2>/dev/null | cut -f1)
        echo "│ ✓ $name/ ($count items, $size)"
    elif [ -d "$path" ]; then
        echo "│ ○ $name/ (empty)"
    else
        echo "│ ✗ $name/ (not found)"
    fi
}

for item in "${BUNDLE_ITEMS[@]}"; do
    src="$CLAUDE_DIR/$item"
    if [ -d "$src" ]; then
        check_dir "$src" "$item"
    else
        check_file "$src" "$item"
    fi
done

# Show estimated bundle size
raw_size=$(get_bundle_size_estimate)
echo "│"
echo "│ Total raw size: ${raw_size}KB"

echo "└──────────────────────────────────────────────────────────────┘"
echo ""

# === Remote Status ===
echo "┌─ Remote (Gist) ──────────────────────────────────────────────┐"

if [ -n "$gist_id" ]; then
    gist_data=$(get_gist 2>/dev/null)

    if echo "$gist_data" | jq -e '.files' > /dev/null 2>&1; then
        # Check for v2.0 bundle format
        has_bundle=$(echo "$gist_data" | jq -e '.files["settings-bundle.tar.gz.b64"]' > /dev/null 2>&1 && echo "true" || echo "false")

        # Get manifest
        manifest=$(echo "$gist_data" | jq -r '.files["manifest.json"].content // "{}"')
        remote_version=$(echo "$manifest" | jq -r '.version // "1.0"')
        remote_device=$(echo "$manifest" | jq -r '.device // "unknown"')
        remote_time=$(echo "$manifest" | jq -r '.timestamp // "unknown"')

        echo "│ Format version: $remote_version"
        echo "│ Last pushed by: $remote_device"
        echo "│ Push time:      $remote_time"

        if [ "$has_bundle" = "true" ]; then
            # v2.0 bundle format
            bundle_size=$(echo "$manifest" | jq -r '.bundle_size_bytes // 0')
            bundle_size_kb=$((bundle_size / 1024))
            remote_items=$(echo "$manifest" | jq -r '.items // []')

            echo "│ Bundle size:    ${bundle_size_kb}KB"
            echo "│ Items:          $(echo "$remote_items" | jq -r 'join(", ")')"
        else
            # v1.x individual file format
            echo "│"
            echo "│ Files in Gist (v1.x format):"
            for f in $(echo "$gist_data" | jq -r '.files | keys[]'); do
                if [[ "$f" != "manifest.json" ]]; then
                    size=$(echo "$gist_data" | jq -r ".files[\"$f\"].size")
                    echo "│   • $f ($size bytes)"
                fi
            done
            echo "│"
            echo -e "│ ${YELLOW}Note: Old format detected. Push to upgrade to v2.0${NC}"
        fi
    else
        echo "│ Error fetching gist: $(echo "$gist_data" | jq -r '.message // "unknown error"')"
    fi
else
    echo "│ No Gist configured"
fi

echo "└──────────────────────────────────────────────────────────────┘"
echo ""

# === Version History ===
echo "┌─ Version History ───────────────────────────────────────────┐"

if [ -n "$gist_id" ]; then
    # Get sync history from gist (contains device info per push)
    sync_history=$(get_sync_history_from_gist "$gist_data")

    if [ -n "$sync_history" ] && [ "$sync_history" != "[]" ] && [ "$sync_history" != "null" ]; then
        entry_count=$(echo "$sync_history" | jq 'length')
        echo "│ Recent pushes (last $entry_count):"
        echo "│"

        echo "$sync_history" | jq -r '.[] | "\(.timestamp)|\(.device)|\(.bundle_size_kb // 0)|\(.skill_count // 0)"' | while IFS='|' read -r timestamp device bundle_kb skills; do
            # Parse timestamp to readable format
            if [[ "$OSTYPE" == "darwin"* ]]; then
                readable_time=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$timestamp")
            else
                readable_time=$(date -d "$timestamp" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$timestamp")
            fi

            # Truncate device name if too long
            if [ ${#device} -gt 15 ]; then
                device="${device:0:12}..."
            fi

            printf "│   • %-16s  %-15s  %3sKB  %2s skills\n" "$readable_time" "$device" "$bundle_kb" "$skills"
        done
    else
        # Fallback to git commits if no sync history
        echo "│ No sync history found (push to start tracking)"
        echo "│"
        echo "│ Showing gist commits instead:"

        history_data=$(get_gist_history 3 2>/dev/null)
        if echo "$history_data" | jq -e '.[0]' > /dev/null 2>&1; then
            echo "$history_data" | jq -r '.[] | "\(.committed_at)|\(.version)"' | while IFS='|' read -r timestamp version; do
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    readable_time=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$timestamp")
                else
                    readable_time=$(date -d "$timestamp" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$timestamp")
                fi
                short_ver="${version:0:7}"
                echo "│   • $readable_time  [$short_ver]"
            done
        fi
    fi
else
    echo "│ No Gist configured"
fi

echo "└──────────────────────────────────────────────────────────────┘"
echo ""

# === Sync Status ===
echo "┌─ Sync Status ────────────────────────────────────────────────┐"

if [ -n "$gist_id" ] && echo "$gist_data" | jq -e '.files' > /dev/null 2>&1; then
    if [ "$has_bundle" = "true" ]; then
        # v2.0 - can't easily compare without downloading and extracting
        echo "│ Format: v2.0 (compressed bundle)"
        echo "│"
        echo "│ Local vs Remote comparison requires downloading bundle."
        echo "│ Use --dry-run with push/pull to preview changes."
        echo "│"

        # Basic time-based suggestion
        if [ -n "$last_sync" ]; then
            echo "│ Last sync: $last_sync"
            echo "│ Remote push: $remote_time"
        fi
    else
        # v1.x - individual file comparison (legacy)
        echo "│ Format: v1.x (individual files)"
        echo "│ Run push to upgrade to v2.0 bundle format."
    fi
else
    echo "│ Cannot determine sync status - remote not accessible"
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
echo "  /claude-settings-sync:push   - Upload local settings to Gist"
echo "  /claude-settings-sync:pull   - Download settings from Gist"
echo "  /claude-settings-sync:update - Check for plugin updates"
echo "  /claude-settings-sync:setup  - Reconfigure sync"
echo ""

#!/bin/bash
# utils.sh - Shared utilities for claude-settings-sync plugin

set -e

# === Configuration ===
CONFIG_DIR="$HOME/.claude/plugins-config"
CONFIG_FILE="$CONFIG_DIR/sync-config.json"
BACKUP_DIR="$HOME/.claude/sync-backups"
CLAUDE_DIR="$HOME/.claude"

# Gist description used to identify our sync gist
GIST_DESCRIPTION="claude-settings-sync"

# === Color Output ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# === Configuration Management ===

ensure_config_dir() {
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$BACKUP_DIR"
}

config_exists() {
    [ -f "$CONFIG_FILE" ]
}

read_config() {
    if config_exists; then
        cat "$CONFIG_FILE"
    else
        echo "{}"
    fi
}

get_config_value() {
    local key="$1"
    read_config | jq -r ".$key // empty"
}

set_config_value() {
    local key="$1"
    local value="$2"
    ensure_config_dir

    if config_exists; then
        local tmp=$(mktemp)
        jq ".$key = $value" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    else
        echo "{\"$key\": $value}" > "$CONFIG_FILE"
    fi
}

save_config() {
    local token="$1"
    local gist_id="$2"

    ensure_config_dir
    cat > "$CONFIG_FILE" << EOF
{
  "github_token": "$token",
  "gist_id": "$gist_id",
  "sync_items": {
    "settings": true,
    "claude_md": true,
    "skills": true,
    "agents": true,
    "commands": true,
    "mcp_servers": false
  },
  "auto_sync": {
    "pull_on_start": false,
    "push_on_end": false,
    "confirm_before_overwrite": true
  },
  "backup": {
    "keep_local_backups": 5,
    "backup_before_pull": true
  },
  "last_sync": null,
  "device_name": "$(hostname)"
}
EOF
    chmod 600 "$CONFIG_FILE"
}

# === GitHub API ===

github_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local token=$(get_config_value "github_token")

    if [ -z "$token" ]; then
        log_error "GitHub token not configured. Run /sync:setup first."
        return 1
    fi

    local args=(-s -H "Authorization: token $token" -H "Accept: application/vnd.github.v3+json")

    if [ "$method" = "GET" ]; then
        curl "${args[@]}" "https://api.github.com$endpoint"
    elif [ "$method" = "POST" ]; then
        curl "${args[@]}" -X POST -d "$data" "https://api.github.com$endpoint"
    elif [ "$method" = "PATCH" ]; then
        curl "${args[@]}" -X PATCH -d "$data" "https://api.github.com$endpoint"
    elif [ "$method" = "DELETE" ]; then
        curl "${args[@]}" -X DELETE "https://api.github.com$endpoint"
    fi
}

validate_token() {
    local token="$1"
    local result=$(curl -s -H "Authorization: token $token" https://api.github.com/user)

    if echo "$result" | jq -e '.login' > /dev/null 2>&1; then
        echo "$result" | jq -r '.login'
        return 0
    else
        return 1
    fi
}

find_existing_gist() {
    local token="$1"
    local gists=$(curl -s -H "Authorization: token $token" "https://api.github.com/gists")

    # Find gist with our description
    echo "$gists" | jq -r ".[] | select(.description == \"$GIST_DESCRIPTION\") | .id" | head -1
}

create_gist() {
    local token="$1"
    local device=$(hostname)
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Build manifest JSON safely (compact, single line)
    local manifest=$(jq -c -n \
        --arg created "$timestamp" \
        --arg device "$device" \
        --arg version "1.0.0" \
        '{created_at: $created, device_name: $device, version: $version}')

    # Build payload
    local payload=$(jq -c -n \
        --arg desc "$GIST_DESCRIPTION" \
        --arg manifest "$manifest" \
        '{
            description: $desc,
            public: false,
            files: {
                "manifest.json": {content: $manifest}
            }
        }')

    local result=$(curl -s -H "Authorization: token $token" \
        -H "Accept: application/vnd.github.v3+json" \
        -X POST -d "$payload" \
        "https://api.github.com/gists")

    echo "$result" | jq -r '.id'
}

get_gist() {
    local gist_id=$(get_config_value "gist_id")
    if [ -z "$gist_id" ]; then
        log_error "Gist ID not configured"
        return 1
    fi
    github_api "GET" "/gists/$gist_id"
}

update_gist() {
    local gist_id=$(get_config_value "gist_id")
    local payload="$1"

    if [ -z "$gist_id" ]; then
        log_error "Gist ID not configured"
        return 1
    fi

    github_api "PATCH" "/gists/$gist_id" "$payload"
}

# Update gist from a file (avoids "Argument list too long" error)
update_gist_from_file() {
    local payload_file="$1"
    local gist_id=$(get_config_value "gist_id")
    local token=$(get_config_value "github_token")

    if [ -z "$gist_id" ]; then
        log_error "Gist ID not configured"
        return 1
    fi

    if [ -z "$token" ]; then
        log_error "GitHub token not configured"
        return 1
    fi

    curl -s -H "Authorization: token $token" \
        -H "Accept: application/vnd.github.v3+json" \
        -X PATCH \
        -d @"$payload_file" \
        "https://api.github.com/gists/$gist_id"
}

# === File Operations ===

get_file_hash() {
    local file="$1"
    if [ -f "$file" ]; then
        if command -v md5sum &> /dev/null; then
            md5sum "$file" | cut -d' ' -f1
        else
            md5 -q "$file"
        fi
    else
        echo ""
    fi
}

get_dir_hash() {
    local dir="$1"
    if [ -d "$dir" ]; then
        find "$dir" -type f -exec cat {} \; 2>/dev/null | \
            if command -v md5sum &> /dev/null; then
                md5sum | cut -d' ' -f1
            else
                md5 -q
            fi
    else
        echo ""
    fi
}

# Create tarball of directory and base64 encode it
pack_directory() {
    local dir="$1"
    if [ -d "$dir" ] && [ "$(ls -A "$dir" 2>/dev/null)" ]; then
        tar -czf - -C "$(dirname "$dir")" "$(basename "$dir")" 2>/dev/null | base64
    else
        echo ""
    fi
}

# Decode base64 and extract tarball
unpack_directory() {
    local content="$1"
    local target_dir="$2"

    if [ -n "$content" ] && [ "$content" != "null" ]; then
        echo "$content" | base64 -d | tar -xzf - -C "$(dirname "$target_dir")" 2>/dev/null
        return $?
    fi
    return 1
}

# === Backup Operations ===

create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/backup_$timestamp"

    mkdir -p "$backup_path"

    # Backup individual files
    [ -f "$CLAUDE_DIR/settings.json" ] && cp "$CLAUDE_DIR/settings.json" "$backup_path/"
    [ -f "$CLAUDE_DIR/CLAUDE.md" ] && cp "$CLAUDE_DIR/CLAUDE.md" "$backup_path/"
    [ -f "$HOME/.claude.json" ] && cp "$HOME/.claude.json" "$backup_path/mcp-servers.json"

    # Backup directories
    [ -d "$CLAUDE_DIR/skills" ] && cp -r "$CLAUDE_DIR/skills" "$backup_path/"
    [ -d "$CLAUDE_DIR/agents" ] && cp -r "$CLAUDE_DIR/agents" "$backup_path/"
    [ -d "$CLAUDE_DIR/commands" ] && cp -r "$CLAUDE_DIR/commands" "$backup_path/"

    # Save metadata
    cat > "$backup_path/metadata.json" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "device": "$(hostname)",
  "reason": "$1"
}
EOF

    echo "$backup_path"
}

cleanup_old_backups() {
    local keep=$(get_config_value "backup.keep_local_backups")
    [ -z "$keep" ] && keep=5

    # List backups sorted by date (oldest first), remove old ones
    local count=$(ls -1d "$BACKUP_DIR"/backup_* 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -gt "$keep" ]; then
        local to_delete=$((count - keep))
        ls -1d "$BACKUP_DIR"/backup_* 2>/dev/null | head -n "$to_delete" | xargs rm -rf
    fi
}

# === Sync Status ===

get_local_manifest() {
    local manifest="{}"

    # Add file hashes
    manifest=$(echo "$manifest" | jq \
        --arg settings "$(get_file_hash "$CLAUDE_DIR/settings.json")" \
        --arg claude_md "$(get_file_hash "$CLAUDE_DIR/CLAUDE.md")" \
        --arg skills "$(get_dir_hash "$CLAUDE_DIR/skills")" \
        --arg agents "$(get_dir_hash "$CLAUDE_DIR/agents")" \
        --arg commands "$(get_dir_hash "$CLAUDE_DIR/commands")" \
        --arg mcp "$(get_file_hash "$HOME/.claude.json")" \
        --arg device "$(hostname)" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + {
            "hashes": {
                "settings": $settings,
                "claude_md": $claude_md,
                "skills": $skills,
                "agents": $agents,
                "commands": $commands,
                "mcp_servers": $mcp
            },
            "device": $device,
            "timestamp": $timestamp
        }')

    echo "$manifest"
}

# === Main check ===

check_dependencies() {
    local missing=()

    command -v curl &> /dev/null || missing+=("curl")
    command -v jq &> /dev/null || missing+=("jq")
    command -v tar &> /dev/null || missing+=("tar")
    command -v base64 &> /dev/null || missing+=("base64")

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_info "Please install them and try again."
        return 1
    fi
    return 0
}

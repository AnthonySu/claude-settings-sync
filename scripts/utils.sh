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

# Get gist commit history
get_gist_history() {
    local gist_id=$(get_config_value "gist_id")
    local limit="${1:-5}"
    if [ -z "$gist_id" ]; then
        log_error "Gist ID not configured"
        return 1
    fi
    github_api "GET" "/gists/$gist_id/commits?per_page=$limit"
}

# Get sync history from gist (device info per push)
# Fetches raw URL directly to avoid parsing issues with control chars in other files
get_sync_history_from_gist() {
    local gist_data="$1"
    local gist_id=$(get_config_value "gist_id")
    local token=$(get_config_value "github_token")

    # Extract raw_url using grep (avoids jq parsing issues with control chars)
    local raw_url=$(echo "$gist_data" | grep -o '"raw_url": *"[^"]*sync-history\.json[^"]*"' | head -1 | sed 's/.*"raw_url": *"\([^"]*\)".*/\1/')

    if [ -n "$raw_url" ]; then
        # Fetch from raw URL (authenticated for private gists)
        curl -s -H "Authorization: token $token" "$raw_url" 2>/dev/null
    else
        # File doesn't exist yet
        echo "[]"
    fi
}

# Create sync history entry
create_history_entry() {
    local device="$1"
    local timestamp="$2"
    local bundle_size="$3"
    local skill_count="$4"

    jq -n \
        --arg device "$device" \
        --arg timestamp "$timestamp" \
        --arg bundle_size "$bundle_size" \
        --arg skill_count "$skill_count" \
        '{
            device: $device,
            timestamp: $timestamp,
            bundle_size_kb: ($bundle_size | tonumber),
            skill_count: ($skill_count | tonumber)
        }'
}

# Append to sync history (keeps last 10 entries)
append_to_sync_history() {
    local existing_history="$1"
    local new_entry="$2"
    local max_entries="${3:-10}"

    echo "$existing_history" | jq --argjson entry "$new_entry" --argjson max "$max_entries" \
        '[$entry] + . | .[:$max]'
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

# === Bundle Operations ===
# Creates a single compressed archive of all settings

# Items to include in bundle (relative to CLAUDE_DIR)
# Note: "skills" is handled specially via manifest, not full content
BUNDLE_ITEMS=(
    "settings.json"
    "CLAUDE.md"
    "agents"
    "commands"
)

# === Skill Manifest Operations ===
# Instead of syncing full skill content (can be 50MB+), we sync just metadata
# and let users install skills locally from their original sources

# Extract metadata from a single skill directory
extract_skill_metadata() {
    local skill_dir="$1"
    local skill_name=$(basename "$skill_dir")

    local name="$skill_name"
    local description=""
    local source=""
    local owner=""
    local version=""

    # Try to extract from SKILL.md frontmatter
    local skill_md="$skill_dir/SKILL.md"
    if [ -f "$skill_md" ]; then
        # Extract name from frontmatter
        local fm_name=$(sed -n '/^---$/,/^---$/p' "$skill_md" | grep -E '^name:' | sed 's/^name:[[:space:]]*//')
        [ -n "$fm_name" ] && name="$fm_name"

        # Extract description from frontmatter
        local fm_desc=$(sed -n '/^---$/,/^---$/p' "$skill_md" | grep -E '^description:' | sed 's/^description:[[:space:]]*//')
        [ -n "$fm_desc" ] && description="$fm_desc"
    fi

    # Try to extract marketplace info
    local marketplace_json="$skill_dir/.claude-plugin/marketplace.json"
    if [ -f "$marketplace_json" ]; then
        source="marketplace"
        owner=$(jq -r '.owner.name // empty' "$marketplace_json" 2>/dev/null)
        version=$(jq -r '.metadata.version // empty' "$marketplace_json" 2>/dev/null)
    fi

    # Output JSON object
    jq -n \
        --arg name "$name" \
        --arg description "$description" \
        --arg source "$source" \
        --arg owner "$owner" \
        --arg version "$version" \
        --arg dir_name "$skill_name" \
        '{
            name: $name,
            description: $description,
            source: (if $source != "" then $source else "local" end),
            owner: (if $owner != "" then $owner else null end),
            version: (if $version != "" then $version else null end),
            dir_name: $dir_name
        }'
}

# Create skills manifest from all installed skills
create_skills_manifest() {
    local skills_dir="$CLAUDE_DIR/skills"
    local skills_json="[]"

    if [ -d "$skills_dir" ]; then
        for skill_dir in "$skills_dir"/*/; do
            if [ -d "$skill_dir" ]; then
                local meta=$(extract_skill_metadata "$skill_dir")
                skills_json=$(echo "$skills_json" | jq --argjson meta "$meta" '. + [$meta]')
            fi
        done
    fi

    jq -n \
        --argjson skills "$skills_json" \
        --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg device "$(hostname)" \
        '{
            version: "1.0.0",
            generated_at: $generated,
            generated_on: $device,
            total_skills: ($skills | length),
            skills: $skills
        }'
}

# Display skills that need to be installed after pull
show_skills_install_guidance() {
    local manifest_file="$1"

    if [ ! -f "$manifest_file" ]; then
        return 0
    fi

    local total=$(jq -r '.total_skills // 0' "$manifest_file")
    if [ "$total" -eq 0 ]; then
        return 0
    fi

    echo ""
    log_info "Skills from synced configuration ($total skills):"
    echo ""

    local missing_count=0
    local installed_count=0

    # Read skills array
    while IFS= read -r skill; do
        local name=$(echo "$skill" | jq -r '.name')
        local dir_name=$(echo "$skill" | jq -r '.dir_name')
        local description=$(echo "$skill" | jq -r '.description // ""' | head -c 60)
        local source=$(echo "$skill" | jq -r '.source // "local"')
        local owner=$(echo "$skill" | jq -r '.owner // ""')

        # Check if skill is installed locally
        if [ -d "$CLAUDE_DIR/skills/$dir_name" ]; then
            echo -e "  ${GREEN}✓${NC} $name"
            ((installed_count++))
        else
            echo -e "  ${YELLOW}○${NC} $name ${YELLOW}(not installed)${NC}"
            if [ -n "$description" ]; then
                echo "      $description..."
            fi
            if [ "$source" = "marketplace" ] && [ -n "$owner" ]; then
                echo -e "      ${CYAN}Source: $owner (marketplace)${NC}"
            fi
            ((missing_count++))
        fi
    done < <(jq -c '.skills[]' "$manifest_file")

    echo ""
    if [ "$missing_count" -gt 0 ]; then
        log_warn "$missing_count skill(s) not installed locally."
        echo ""
        echo "  To install marketplace skills, use:"
        echo "    claude /install <marketplace-name>"
        echo ""
        echo "  Or copy skills from another machine to: ~/.claude/skills/"
    else
        log_success "All $installed_count skills already installed!"
    fi
}

# Create a single compressed bundle of all settings
# Args: optional filter items (space-separated). If empty, include all.
# Output: base64-encoded xz-compressed tarball to stdout
create_settings_bundle() {
    local filter_items=("$@")
    local temp_dir=$(mktemp -d)
    local bundle_dir="$temp_dir/claude-settings"
    mkdir -p "$bundle_dir"

    # Copy files and directories that exist
    for item in "${BUNDLE_ITEMS[@]}"; do
        # Skip if filter specified and item not in filter
        if [ ${#filter_items[@]} -gt 0 ]; then
            local in_filter=false
            for f in "${filter_items[@]}"; do
                if [ "$item" = "$f" ]; then
                    in_filter=true
                    break
                fi
            done
            if [ "$in_filter" = false ]; then
                continue
            fi
        fi

        local src="$CLAUDE_DIR/$item"
        if [ -e "$src" ]; then
            if [ -d "$src" ]; then
                # Directory: copy recursively if not empty
                if [ "$(ls -A "$src" 2>/dev/null)" ]; then
                    cp -r "$src" "$bundle_dir/"
                fi
            else
                # File: copy directly
                cp "$src" "$bundle_dir/"
            fi
        fi
    done

    # Create skills manifest if skills is in filter (or no filter)
    local include_skills=true
    if [ ${#filter_items[@]} -gt 0 ]; then
        include_skills=false
        for f in "${filter_items[@]}"; do
            if [ "$f" = "skills" ]; then
                include_skills=true
                break
            fi
        done
    fi

    if [ "$include_skills" = true ] && [ -d "$CLAUDE_DIR/skills" ] && [ "$(ls -A "$CLAUDE_DIR/skills" 2>/dev/null)" ]; then
        create_skills_manifest > "$bundle_dir/skills-manifest.json"
    fi

    # Add bundle metadata
    local items_with_manifest=("${BUNDLE_ITEMS[@]}" "skills-manifest.json")
    cat > "$bundle_dir/.bundle-meta.json" << EOF
{
    "version": "2.1.0",
    "compression": "xz",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "device": "$(hostname)",
    "items": $(printf '%s\n' "${items_with_manifest[@]}" | jq -R . | jq -s .),
    "skills_mode": "manifest"
}
EOF

    # Create tarball with xz -9 compression (best ratio), base64 encode
    tar -cf - -C "$temp_dir" "claude-settings" 2>/dev/null | xz -9 | base64

    # Cleanup
    rm -rf "$temp_dir"
}

# Create bundle with selective items, merging with existing remote
# Args: existing_bundle_base64, filter_items...
create_merged_bundle() {
    local existing_bundle="$1"
    shift
    local filter_items=("$@")

    local temp_dir=$(mktemp -d)
    local bundle_dir="$temp_dir/claude-settings"
    mkdir -p "$bundle_dir"

    # Extract existing bundle if provided
    if [ -n "$existing_bundle" ]; then
        echo "$existing_bundle" | base64 -d | xz -d | tar -xf - -C "$temp_dir" 2>/dev/null
    fi

    # Overlay local items (only the filtered ones)
    for item in "${filter_items[@]}"; do
        local src="$CLAUDE_DIR/$item"
        local dst="$bundle_dir/$item"

        if [ -e "$src" ]; then
            if [ -d "$src" ]; then
                rm -rf "$dst"
                if [ "$(ls -A "$src" 2>/dev/null)" ]; then
                    cp -r "$src" "$bundle_dir/"
                fi
            else
                cp "$src" "$bundle_dir/"
            fi
        fi

        # Handle skills specially
        if [ "$item" = "skills" ] && [ -d "$CLAUDE_DIR/skills" ]; then
            create_skills_manifest > "$bundle_dir/skills-manifest.json"
        fi
    done

    # Update bundle metadata
    local items_with_manifest=("${BUNDLE_ITEMS[@]}" "skills-manifest.json")
    cat > "$bundle_dir/.bundle-meta.json" << EOF
{
    "version": "2.1.0",
    "compression": "xz",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "device": "$(hostname)",
    "items": $(printf '%s\n' "${items_with_manifest[@]}" | jq -R . | jq -s .),
    "skills_mode": "manifest",
    "partial_update": $(printf '%s\n' "${filter_items[@]}" | jq -R . | jq -s .)
}
EOF

    # Create tarball
    tar -cf - -C "$temp_dir" "claude-settings" 2>/dev/null | xz -9 | base64

    # Cleanup
    rm -rf "$temp_dir"
}

# Extract settings bundle to CLAUDE_DIR
# Args: optional filter items (space-separated). If empty, extract all.
# Input: base64-encoded xz-compressed tarball from stdin
extract_settings_bundle() {
    local filter_items=("$@")
    local temp_dir=$(mktemp -d)

    # Decode, decompress (xz), extract
    base64 -d | xz -d | tar -xf - -C "$temp_dir" 2>/dev/null

    if [ ! -d "$temp_dir/claude-settings" ]; then
        log_error "Invalid bundle format"
        rm -rf "$temp_dir"
        return 1
    fi

    # Copy extracted items to CLAUDE_DIR
    for item in "${BUNDLE_ITEMS[@]}"; do
        # Skip if filter specified and item not in filter
        if [ ${#filter_items[@]} -gt 0 ]; then
            local in_filter=false
            for f in "${filter_items[@]}"; do
                if [ "$item" = "$f" ]; then
                    in_filter=true
                    break
                fi
            done
            if [ "$in_filter" = false ]; then
                continue
            fi
        fi

        local src="$temp_dir/claude-settings/$item"
        local dst="$CLAUDE_DIR/$item"

        if [ -e "$src" ]; then
            if [ -d "$src" ]; then
                # Directory: remove existing and copy
                rm -rf "$dst"
                cp -r "$src" "$dst"
            else
                # File: copy directly
                cp "$src" "$dst"
            fi
        fi
    done

    # Handle skills manifest (v2.1+ bundles) - only if skills in filter or no filter
    local include_skills=true
    if [ ${#filter_items[@]} -gt 0 ]; then
        include_skills=false
        for f in "${filter_items[@]}"; do
            if [ "$f" = "skills" ]; then
                include_skills=true
                break
            fi
        done
    fi

    if [ "$include_skills" = true ]; then
        local skills_manifest="$temp_dir/claude-settings/skills-manifest.json"
        if [ -f "$skills_manifest" ]; then
            cp "$skills_manifest" "$CLAUDE_DIR/skills-manifest.json"
        fi
    fi

    # Cleanup
    rm -rf "$temp_dir"
    return 0
}

# Get bundle size estimate (before base64)
get_bundle_size_estimate() {
    local total=0
    for item in "${BUNDLE_ITEMS[@]}"; do
        local src="$CLAUDE_DIR/$item"
        if [ -e "$src" ]; then
            if [ -d "$src" ]; then
                local size=$(du -sk "$src" 2>/dev/null | cut -f1)
            else
                local size=$(du -k "$src" 2>/dev/null | cut -f1)
            fi
            total=$((total + size))
        fi
    done
    echo "$total"
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

# === Selective Sync ===

# Valid items for --only flag
VALID_SYNC_ITEMS=("settings.json" "CLAUDE.md" "agents" "commands" "skills")

# Validate --only items
validate_only_items() {
    local items=("$@")
    for item in "${items[@]}"; do
        local found=false
        for valid in "${VALID_SYNC_ITEMS[@]}"; do
            if [ "$item" = "$valid" ]; then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            log_error "Invalid item: $item"
            log_info "Valid items: ${VALID_SYNC_ITEMS[*]}"
            return 1
        fi
    done
    return 0
}

# Check if item should be synced (based on --only filter)
should_sync_item() {
    local item="$1"
    shift
    local only_items=("$@")

    # If no --only specified, sync everything
    if [ ${#only_items[@]} -eq 0 ]; then
        return 0
    fi

    # Check if item is in the filter list
    for only_item in "${only_items[@]}"; do
        if [ "$item" = "$only_item" ]; then
            return 0
        fi
    done
    return 1
}

# === Conflict Detection ===

# Get local settings last modified time (most recent file in bundle items)
get_local_modified_time() {
    local latest=""
    for item in "${BUNDLE_ITEMS[@]}"; do
        local src="$CLAUDE_DIR/$item"
        if [ -e "$src" ]; then
            local mtime
            if [[ "$OSTYPE" == "darwin"* ]]; then
                mtime=$(stat -f "%m" "$src" 2>/dev/null)
            else
                mtime=$(stat -c "%Y" "$src" 2>/dev/null)
            fi
            if [ -n "$mtime" ]; then
                if [ -z "$latest" ] || [ "$mtime" -gt "$latest" ]; then
                    latest="$mtime"
                fi
            fi
        fi
    done
    # Convert to ISO format
    if [ -n "$latest" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            date -r "$latest" -u +%Y-%m-%dT%H:%M:%SZ
        else
            date -d "@$latest" -u +%Y-%m-%dT%H:%M:%SZ
        fi
    fi
}

# Get remote manifest timestamp from gist (fetches manifest.json via raw_url)
get_remote_timestamp() {
    local gist_data="$1"
    local token=$(get_config_value "github_token")

    # Extract manifest.json raw_url using grep (avoids jq parsing issues)
    local raw_url=$(echo "$gist_data" | grep -o '"raw_url": *"[^"]*manifest\.json[^"]*"' | head -1 | sed 's/.*"raw_url": *"\([^"]*\)".*/\1/')

    if [ -n "$raw_url" ]; then
        # Fetch manifest and extract timestamp
        curl -s -H "Authorization: token $token" "$raw_url" 2>/dev/null | jq -r '.timestamp // empty'
    fi
}

# Compare timestamps, return: "local_newer", "remote_newer", "equal", or "unknown"
compare_sync_times() {
    local local_time="$1"
    local remote_time="$2"

    if [ -z "$local_time" ] || [ -z "$remote_time" ]; then
        echo "unknown"
        return
    fi

    # Convert to epoch for comparison
    local local_epoch remote_epoch
    if [[ "$OSTYPE" == "darwin"* ]]; then
        local_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$local_time" "+%s" 2>/dev/null || echo "0")
        remote_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$remote_time" "+%s" 2>/dev/null || echo "0")
    else
        local_epoch=$(date -d "$local_time" "+%s" 2>/dev/null || echo "0")
        remote_epoch=$(date -d "$remote_time" "+%s" 2>/dev/null || echo "0")
    fi

    if [ "$local_epoch" -gt "$remote_epoch" ]; then
        echo "local_newer"
    elif [ "$remote_epoch" -gt "$local_epoch" ]; then
        echo "remote_newer"
    else
        echo "equal"
    fi
}

# === Main check ===

check_dependencies() {
    local missing=()

    command -v curl &> /dev/null || missing+=("curl")
    command -v jq &> /dev/null || missing+=("jq")
    command -v tar &> /dev/null || missing+=("tar")
    command -v base64 &> /dev/null || missing+=("base64")
    command -v xz &> /dev/null || missing+=("xz")

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_info "Please install them and try again."
        return 1
    fi
    return 0
}

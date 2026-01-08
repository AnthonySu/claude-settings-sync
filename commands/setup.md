---
description: Configure GitHub Gist sync for Claude Code settings
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

# Setup Settings Sync

Configure synchronization of Claude Code settings across devices using GitHub Gists.

## Prerequisites

You need a GitHub Personal Access Token with `gist` scope:
1. Go to https://github.com/settings/tokens/new
2. Give it a name like "Claude Settings Sync"
3. Select the `gist` scope (Create gists)
4. Generate and copy the token (starts with `ghp_`)

## Setup Steps

Ask the user for their GitHub token, then:

1. **Validate the token**:
   ```bash
   curl -s -H "Authorization: token <TOKEN>" https://api.github.com/user | jq -r '.login'
   ```

2. **Check for existing sync gist**:
   ```bash
   curl -s -H "Authorization: token <TOKEN>" "https://api.github.com/gists" | jq -r '.[] | select(.description == "claude-settings-sync") | .id' | head -1
   ```

3. **If no gist exists, create one**:
   ```bash
   curl -s -H "Authorization: token <TOKEN>" -X POST -d '{"description":"claude-settings-sync","public":false,"files":{"manifest.json":{"content":"{}"}}}' "https://api.github.com/gists" | jq -r '.id'
   ```

4. **Save config to `~/.claude/plugins-config/sync-config.json`**:
   ```json
   {
     "github_token": "<TOKEN>",
     "gist_id": "<GIST_ID>",
     "sync_items": {"settings": true, "claude_md": true, "skills": true, "agents": true, "commands": true, "mcp_servers": false},
     "auto_sync": {"pull_on_start": false, "push_on_end": false, "confirm_before_overwrite": true},
     "backup": {"keep_local_backups": 5, "backup_before_pull": true},
     "last_sync": null,
     "device_name": "<hostname>"
   }
   ```
   Set file permissions to 600.

5. **Confirm success** and tell user to run `/claude-settings-sync:push` or `/claude-settings-sync:pull` next.

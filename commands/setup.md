---
description: Configure GitHub Gist sync for Claude Code settings
---

# Setup Settings Sync

Configure synchronization of Claude Code settings across devices using GitHub Gists.

## What this does

1. Validates your GitHub Personal Access Token (needs `gist` scope)
2. Searches for existing sync gist or creates a new private one
3. Saves configuration to `~/.claude/plugins-config/sync-config.json`

## Setup Instructions

To set up sync, you need a GitHub Personal Access Token with `gist` scope:

1. Go to https://github.com/settings/tokens/new
2. Give it a name like "Claude Settings Sync"
3. Select the `gist` scope (Create gists)
4. Generate and copy the token

Then run the setup script by executing:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh
```

The script will:
- Ask for your GitHub token
- Verify the token works
- Find or create a sync gist
- Save your configuration

After setup, use `/sync:push` to upload your current settings, or `/sync:pull` to download existing settings from another device.

---
description: Uninstall claude-settings-sync plugin
allowed-tools: Bash, Read, AskUserQuestion
---

# Uninstall Settings Sync

Remove the claude-settings-sync plugin and its configuration.

## What Gets Removed

- Plugin directory (`~/.claude/plugins/marketplaces/claude-settings-sync/`)
- Plugin entries from Claude Code configuration
- Sync configuration (GitHub token, Gist ID)
- Local backup files

## What Gets Kept

- Your GitHub Gist with synced settings (not deleted remotely)
- Your actual Claude Code settings

## Uninstall

Run the uninstall script:

```bash
~/.claude/plugins/marketplaces/claude-settings-sync/uninstall.sh
```

The script will:
1. Ask for confirmation
2. Remove from `settings.json`
3. Remove from `known_marketplaces.json`
4. Remove from `installed_plugins.json`
5. Remove sync config and local backups
6. Delete the plugin directory

After uninstall, tell the user to restart Claude Code.

To reinstall later:
```bash
curl -fsSL https://raw.githubusercontent.com/AnthonySu/claude-settings-sync/main/install.sh | bash
```

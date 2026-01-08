---
description: Show sync status and configuration
allowed-tools: Bash
---

# Sync Status

Display the current sync configuration, status, and any differences between local and remote settings.

## Execute

Run the status script:

```bash
~/.claude/plugins/marketplaces/claude-settings-sync/scripts/status.sh
```

Shows: configuration status, GitHub user, Gist ID, last sync time, local vs remote comparison, and available backups.

## Other Commands

- `/claude-settings-sync:setup` - Configure GitHub token and Gist
- `/claude-settings-sync:push` - Push local settings to Gist
- `/claude-settings-sync:pull` - Pull settings from Gist

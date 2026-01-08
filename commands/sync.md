---
description: Sync Claude Code settings across devices
allowed-tools: Bash
---

# Claude Settings Sync

Sync your Claude Code settings across devices via GitHub Gists.

## Quick Actions

First, check current sync status:

```bash
~/.claude/plugins/claude-settings-sync/scripts/status.sh
```

Then choose an action:

### Push (upload local settings)
```bash
~/.claude/plugins/claude-settings-sync/scripts/push.sh
```

### Pull (download remote settings)
```bash
echo "y" | ~/.claude/plugins/claude-settings-sync/scripts/pull.sh
```

## Available Commands

- `/sync:push` - Push local settings to Gist
- `/sync:pull` - Pull settings from Gist
- `/sync:status` - Show sync status
- `/sync:setup` - Configure sync settings

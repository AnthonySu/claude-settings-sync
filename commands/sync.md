---
description: Sync Claude Code settings across devices
---

# Claude Settings Sync

Sync your Claude Code settings across devices via GitHub Gists.

## Quick Actions

First, check current sync status:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/status.sh
```

Then choose an action:

### Push (upload local settings)
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/push.sh
```

### Pull (download remote settings)
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh
```

## First Time Setup

If not configured yet, run setup first:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh
```

## Available Commands

- `/claude-settings-sync:push` - Push local settings to Gist
- `/claude-settings-sync:pull` - Pull settings from Gist
- `/claude-settings-sync:status` - Show sync status
- `/claude-settings-sync:setup` - Configure sync settings

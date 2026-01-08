---
description: Pull Claude Code settings from GitHub Gist
allowed-tools: Bash
---

# Pull Settings

Download Claude Code settings from the configured GitHub Gist to this device.

## What gets synced

- `settings.json` -> `~/.claude/settings.json`
- `CLAUDE.md` -> `~/.claude/CLAUDE.md`
- `skills/` -> `~/.claude/skills/`
- `agents/` -> `~/.claude/agents/`
- `commands/` -> `~/.claude/commands/`

## Execute

Run the pull script with auto-confirmation:

```bash
echo "y" | ~/.claude/plugins/claude-settings-sync/scripts/pull.sh
```

A local backup is created before pulling. Backups are stored in `~/.claude/sync-backups/`.

After pulling, tell the user to restart Claude Code for changes to take effect.

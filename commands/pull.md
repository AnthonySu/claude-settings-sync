---
description: Pull Claude Code settings from GitHub Gist
---

# Pull Settings

Download Claude Code settings from the configured GitHub Gist to this device.

## What gets synced

By default, these files are pulled:
- `settings.json` -> `~/.claude/settings.json`
- `CLAUDE.md` -> `~/.claude/CLAUDE.md`
- `skills/` -> `~/.claude/skills/`
- `agents/` -> `~/.claude/agents/`
- `commands/` -> `~/.claude/commands/`

## Usage

Run the pull script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/pull.sh
```

Options:
- `--force` - Skip confirmation and overwrite without prompting
- `--dry-run` - Show what would be pulled without actually pulling

## Safety

- A local backup is automatically created before pulling
- You'll be prompted before overwriting existing files (unless --force)
- Backups are stored in `~/.claude/sync-backups/`

---
description: Pull Claude Code settings from GitHub Gist
allowed-tools: Bash, Read, Write
---

# Pull Settings

Download Claude Code settings from the configured GitHub Gist to this device.

## What Gets Pulled

A single compressed bundle containing:

- `settings.json` -> `~/.claude/settings.json`
- `CLAUDE.md` -> `~/.claude/CLAUDE.md`
- `skills/` -> `~/.claude/skills/`
- `agents/` -> `~/.claude/agents/`
- `commands/` -> `~/.claude/commands/`

## Execute

Run the pull script:

```bash
~/.claude/plugins/marketplaces/claude-settings-sync/scripts/pull.sh
```

### Options

- `--force` - Skip confirmation prompt
- `--dry-run` - Show what would be pulled without actually pulling
- `--diff` - Preview file-level changes before pulling
- `--only=items` - Pull only specific items (comma-separated)

### Selective Pull Examples

```bash
# Pull only commands directory
~/.claude/plugins/marketplaces/claude-settings-sync/scripts/pull.sh --only=commands

# Pull settings.json and CLAUDE.md only
~/.claude/plugins/marketplaces/claude-settings-sync/scripts/pull.sh --only=settings.json,CLAUDE.md

# Preview changes before pulling
~/.claude/plugins/marketplaces/claude-settings-sync/scripts/pull.sh --diff
```

Valid items: `settings.json`, `CLAUDE.md`, `agents`, `commands`, `skills`

## Process

1. Fetches gist metadata and bundle info
2. Shows remote bundle details (device, timestamp, size)
3. Creates local backup before pulling
4. Downloads bundle (uses raw_url for large/truncated files)
5. Extracts bundle to `~/.claude/`
6. Updates last sync timestamp

## Notes

- **Backup**: A backup is always created before pulling
- **Overwrite**: This will replace your local settings with remote ones
- **Restart required**: Restart Claude Code after pulling for changes to take effect
- **Large files**: Bundles >1MB are automatically fetched via raw_url

## Other Commands

- `/claude-settings-sync:setup` - Configure GitHub token and Gist
- `/claude-settings-sync:push` - Push local settings to Gist
- `/claude-settings-sync:status` - Show sync status

---
description: Push local Claude Code settings to GitHub Gist
allowed-tools: Bash, Read
---

# Push Settings

Upload local Claude Code settings to the configured GitHub Gist as a compressed bundle.

## What Gets Synced

All items are bundled into a single compressed archive (tar + xz -9 + base64):

- `~/.claude/settings.json` - Claude Code settings
- `~/.claude/CLAUDE.md` - User instructions
- `~/.claude/skills/` - Custom skills directory
- `~/.claude/agents/` - Custom agents directory
- `~/.claude/commands/` - Custom commands directory

## Execute

Run the push script:

```bash
~/.claude/plugins/marketplaces/claude-settings-sync/scripts/push.sh
```

### Options

- `--force` - Skip confirmation prompt
- `--dry-run` - Show what would be pushed without actually pushing

## Process

1. Collects all sync items and shows sizes
2. Creates compressed bundle (xz -9 for maximum compression)
3. Creates local backup before pushing
4. Uploads bundle to GitHub Gist
5. Updates last sync timestamp

## Notes

- MCP server configs (`~/.claude.json`) are NOT synced (may contain API keys)
- `settings.local.json` is NOT synced (contains machine-specific permissions)
- Gist maintains version history on GitHub
- Large bundles (>1MB in API response) are handled via raw_url fetch on pull

## Other Commands

- `/claude-settings-sync:setup` - Configure GitHub token and Gist
- `/claude-settings-sync:pull` - Pull settings from Gist
- `/claude-settings-sync:status` - Show sync status

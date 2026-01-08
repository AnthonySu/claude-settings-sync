---
description: Push local Claude Code settings to GitHub Gist
allowed-tools: Bash
---

# Push Settings

Upload your local Claude Code settings to the configured GitHub Gist.

## What gets synced

- `~/.claude/settings.json` - Claude Code settings
- `~/.claude/CLAUDE.md` - User instructions
- `~/.claude/skills/` - Custom skills
- `~/.claude/agents/` - Custom agents
- `~/.claude/commands/` - Custom commands

## Execute

Run the push script:

```bash
~/.claude/plugins/claude-settings-sync/scripts/push.sh
```

The gist maintains version history (viewable on GitHub). MCP server configs are not synced by default (may contain secrets).

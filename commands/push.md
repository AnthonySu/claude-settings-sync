---
description: Push local Claude Code settings to GitHub Gist
---

# Push Settings

Upload your local Claude Code settings to the configured GitHub Gist.

## What gets synced

By default, these files are synced:
- `~/.claude/settings.json` - Claude Code settings
- `~/.claude/CLAUDE.md` - User instructions
- `~/.claude/skills/` - Custom skills
- `~/.claude/agents/` - Custom agents
- `~/.claude/commands/` - Custom commands

## Usage

Run the push script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/push.sh
```

Options:
- `--force` - Skip confirmation prompt
- `--dry-run` - Show what would be pushed without actually pushing

## Notes

- A local backup is created before pushing
- The gist maintains version history (viewable on GitHub)
- Sensitive files like MCP server configs are not synced by default

# Claude Settings Sync

Sync your Claude Code settings across devices using GitHub Gists.

## Changelog

- **v1.2.0** - Auto-update command, path traversal fix, 44 automated tests
- **v1.1.0** - Conflict detection, `--diff` preview, `--only` selective sync, quick restore
- **v1.0.0** - Initial release with compressed bundles, skill manifest sync, version history

```
Device A (MacBook)                    Device B (iMac)
     │                                     ▲
     │  /claude-settings-sync:push         │  /claude-settings-sync:pull
     ▼                                     │
┌───────────────────────────────────────────────┐
│            GitHub Gist (Private)              │
│  • settings.json      • commands/             │
│  • CLAUDE.md          • skills-manifest.json  │
│  • agents/            • sync-history.json     │
└───────────────────────────────────────────────┘
```

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/AnthonySu/claude-settings-sync/main/install.sh | bash
```

Then restart Claude Code and run `/claude-settings-sync:setup`.

## Setup

### Prerequisites

Create a GitHub Personal Access Token with `gist` scope:
1. Go to https://github.com/settings/tokens/new
2. Name it "Claude Settings Sync"
3. Select only the `gist` scope
4. Generate and copy the token (starts with `ghp_`)

### Configure

Run in Claude:

```
/claude-settings-sync:setup
```

Enter your token when prompted. This creates a private Gist for your settings.

## Usage

| Command | Description |
|---------|-------------|
| `/claude-settings-sync:setup` | Configure GitHub token and Gist |
| `/claude-settings-sync:push` | Upload local settings to Gist |
| `/claude-settings-sync:pull` | Download settings from Gist |
| `/claude-settings-sync:update` | Check for and install plugin updates |
| `/claude-settings-sync:restore` | Restore from local backup |
| `/claude-settings-sync` | Show sync status |
| `/claude-settings-sync:uninstall` | Remove plugin and configuration |

### Options

```bash
# Conflict detection (automatic)
push/pull  # Warns if remote/local is newer

# Preview changes before pull
pull --diff

# Selective sync (comma-separated items)
push --only=commands,CLAUDE.md
pull --only=settings.json

# Valid items: settings.json, CLAUDE.md, agents, commands, skills
```

### Sync to a new device

1. Install the plugin (same as above)
2. Run `/claude-settings-sync:setup` with the **same** GitHub token
3. Run `/claude-settings-sync:pull`
4. Restart Claude Code

## What Gets Synced

| Item | Location | Synced |
|------|----------|--------|
| Settings | `~/.claude/settings.json` | Yes |
| Instructions | `~/.claude/CLAUDE.md` | Yes |
| Commands | `~/.claude/commands/` | Yes |
| Agents | `~/.claude/agents/` | Yes |
| Skills | `~/.claude/skills/` | Manifest only* |
| MCP Servers | `~/.claude.json` | No (secrets) |

*Skills sync as a manifest (name, description, source) rather than full content. On pull, you'll see which skills to install locally. This keeps bundle size small (~9KB vs 50MB+).

## Configuration

Config stored at `~/.claude/plugins-config/sync-config.json`:

```json
{
  "github_token": "ghp_xxx",
  "gist_id": "abc123...",
  "sync_items": {
    "settings": true,
    "claude_md": true,
    "commands": true,
    "skills": true,
    "mcp_servers": false
  },
  "backup": {
    "keep_local_backups": 5,
    "backup_before_pull": true
  }
}
```

## Security

- Token stored locally with `600` permissions (owner read/write only)
- Gist is private (only visible to you)
- MCP configs excluded by default (may contain API keys)
- Backups created before each pull: `~/.claude/sync-backups/`

## Uninstall

Run in Claude:
```
/claude-settings-sync:uninstall
```

Or run the script directly:
```bash
~/.claude/plugins/marketplaces/claude-settings-sync/uninstall.sh
```

This removes:
- Plugin directory and configuration files
- Sync config (token, gist ID)
- Local backups

Your GitHub Gist is **not** deleted (visit https://gist.github.com to remove it manually).

## Requirements

- `curl`, `jq`, `xz` (pre-installed on macOS/Linux)
- GitHub account

## License

MIT

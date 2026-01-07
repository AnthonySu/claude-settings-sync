# Claude Settings Sync

Sync your Claude Code settings across devices using GitHub Gists.

```
Device A (MacBook)              Device B (iMac)
     │                               │
     │  /sync:push                   │  /sync:pull
     ▼                               ▼
┌─────────────────────────────────────────┐
│         GitHub Gist (Private)           │
│  • settings.json                        │
│  • CLAUDE.md                            │
│  • skills/                              │
│  • agents/                              │
│  • commands/                            │
└─────────────────────────────────────────┘
```

## Features

- Sync settings, CLAUDE.md, skills, agents, and commands
- Private GitHub Gist storage (only you can access)
- Automatic version history via Gist revisions
- Local backups before every sync operation
- Optional auto-sync on session start

## Quick Start

### 1. Install the Plugin

```bash
# Option A: Clone from GitHub
git clone https://github.com/AnthonySu/claude-settings-sync.git ~/.claude/plugins/claude-settings-sync

# Option B: Add as plugin directory
claude --plugin-dir /path/to/claude-settings-sync
```

### 2. Create GitHub Token

1. Go to https://github.com/settings/tokens/new
2. Name: `Claude Settings Sync`
3. Expiration: Choose based on preference
4. Scopes: Select **only** `gist` (Create gists)
5. Click "Generate token" and copy it

### 3. Run Setup

```
/sync:setup
```

Enter your GitHub token when prompted. The plugin will:
- Validate your token
- Create a new private Gist (or find existing one)
- Save configuration locally

### 4. Push Your Settings

```
/sync:push
```

Done! Your settings are now in the cloud.

## Commands

| Command | Description |
|---------|-------------|
| `/sync:setup` | Initial configuration (GitHub token + Gist) |
| `/sync:push` | Upload local settings to Gist |
| `/sync:pull` | Download settings from Gist to local |
| `/sync:status` | Show configuration and sync status |

## Setting Up a New Device

On your new device:

```bash
# 1. Clone the plugin
git clone https://github.com/AnthonySu/claude-settings-sync.git ~/.claude/plugins/claude-settings-sync

# 2. Start Claude with the plugin
claude --plugin-dir ~/.claude/plugins/claude-settings-sync

# 3. Run setup with the SAME GitHub token
/sync:setup

# 4. Pull your settings
/sync:pull

# 5. Restart Claude Code for changes to take effect
```

## What Gets Synced

| Item | Location | Synced by Default |
|------|----------|-------------------|
| Settings | `~/.claude/settings.json` | ✅ Yes |
| User Instructions | `~/.claude/CLAUDE.md` | ✅ Yes |
| Skills | `~/.claude/skills/` | ✅ Yes |
| Agents | `~/.claude/agents/` | ✅ Yes |
| Commands | `~/.claude/commands/` | ✅ Yes |
| MCP Servers | `~/.claude.json` | ❌ No (sensitive) |

## Configuration

Config stored at `~/.claude/plugins-config/sync-config.json`:

```json
{
  "github_token": "ghp_xxx",
  "gist_id": "abc123...",
  "sync_items": {
    "settings": true,
    "claude_md": true,
    "skills": true,
    "agents": true,
    "commands": true,
    "mcp_servers": false
  },
  "auto_sync": {
    "pull_on_start": false,
    "push_on_end": false
  },
  "backup": {
    "keep_local_backups": 5
  }
}
```

### Enable Auto-Sync (Optional)

Edit the config to enable automatic sync:

```json
{
  "auto_sync": {
    "pull_on_start": true,  // Auto-pull when Claude starts
    "push_on_end": false    // Not recommended (may overwrite)
  }
}
```

## Permanent Installation

To always load this plugin, add to `~/.claude/settings.json`:

```json
{
  "plugins": [
    "~/.claude/plugins/claude-settings-sync"
  ]
}
```

Or create a marketplace for your plugins.

## Backups

Local backups are automatically created before every push/pull operation:

```
~/.claude/sync-backups/
├── backup_20250107_103045/
│   ├── settings.json
│   ├── CLAUDE.md
│   ├── skills/
│   └── metadata.json
└── backup_20250107_112030/
    └── ...
```

By default, the 5 most recent backups are kept.

## Security Notes

- Your GitHub token is stored locally in `~/.claude/plugins-config/sync-config.json`
- The file has `600` permissions (owner read/write only)
- The Gist is **private** - only visible to you
- MCP server configs are NOT synced by default (may contain API keys)

## Requirements

- `curl` - HTTP requests
- `jq` - JSON processing
- `tar` - Directory archiving
- `base64` - Encoding

All are typically pre-installed on macOS and most Linux distributions.

## Troubleshooting

### "Token invalid or expired"
Generate a new token at https://github.com/settings/tokens

### "Gist not found"
Run `/sync:setup` again to reconfigure

### "Permission denied" on scripts
```bash
chmod +x ~/.claude/plugins/claude-settings-sync/scripts/*.sh
```

### Pull doesn't restore files
Check that the Gist contains files: `/sync:status`

## License

MIT

## Contributing

Issues and PRs welcome at https://github.com/AnthonySu/claude-settings-sync

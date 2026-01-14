# Claude Settings Sync

Sync your Claude Code settings across devices using GitHub Gists.

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

### Option A: One-Line Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/AnthonySu/claude-settings-sync/main/install.sh | bash
```

This automatically:
- Clones the repository to the correct location
- Updates all Claude Code configuration files
- Makes scripts executable

After installation, restart Claude Code and run `/claude-settings-sync:setup`.

### Option B: Ask Claude

Tell Claude:

```
Install the claude-settings-sync plugin from https://github.com/AnthonySu/claude-settings-sync
```

### Option C: Manual

```bash
# Clone to marketplaces directory
git clone https://github.com/AnthonySu/claude-settings-sync.git ~/.claude/plugins/marketplaces/claude-settings-sync

# Run the installer
~/.claude/plugins/marketplaces/claude-settings-sync/install.sh
```

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
| `/claude-settings-sync` | Show sync status |
| `/claude-settings-sync:uninstall` | Remove plugin and configuration |

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

## Changelog

### v2.1.0 (2026-01-14)
- **Skill manifest sync**: Skills now sync as metadata only (name, description, source), reducing bundle from 50MB+ to ~9KB. On pull, shows which skills need local installation.
- **Version history**: Status now displays push history with device name, timestamp, bundle size, and skill count per entry.
- **Sync history tracking**: Each push records device info in `sync-history.json` for cross-device visibility.

### v2.0.0 (2026-01-12)
- **Compressed bundles**: All settings packaged into a single xz-compressed tarball for better efficiency and larger file support.
- **Improved status**: Shows local vs remote comparison and backup info.

### v1.0.0 (2026-01-08)
- Initial release with push/pull/status commands.
- GitHub Gist storage with automatic backup before pull.

## License

MIT

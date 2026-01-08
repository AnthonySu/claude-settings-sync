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

---

## For LLM

> **One-liner for Claude to install this plugin:**
>
> ```
> Clone https://github.com/AnthonySu/claude-settings-sync to ~/.claude/plugins/claude-settings-sync, make scripts executable, then guide me through GitHub token setup and configure it (validate token, find/create gist, save config to ~/.claude/plugins-config/sync-config.json).
> ```

---

## For Human

### Prerequisites

Before installing, you need a **GitHub Personal Access Token** with `gist` scope:

1. Go to https://github.com/settings/tokens/new
2. **Note**: Enter `Claude Settings Sync`
3. **Expiration**: Choose based on preference (recommend 90 days or No expiration)
4. **Scopes**: Check **only** `gist` ✅
5. Click **Generate token**
6. **Copy the token** (starts with `ghp_`) - you won't see it again!

> ⚠️ Keep this token safe. It allows access to your Gists.

---

### Installation

#### Option A: Let Claude Install It

Just tell Claude:

```
Install the claude-settings-sync plugin from https://github.com/AnthonySu/claude-settings-sync
```

#### Option B: Manual Installation

```bash
# 1. Clone the plugin
git clone https://github.com/AnthonySu/claude-settings-sync.git ~/.claude/plugins/claude-settings-sync

# 2. Make scripts executable
chmod +x ~/.claude/plugins/claude-settings-sync/scripts/*.sh

# 3. Start Claude with the plugin
claude --plugin-dir ~/.claude/plugins/claude-settings-sync
```

---

### Setup

After installation, run:

```
/sync:setup
```

You'll be prompted to:
1. Enter your GitHub token (the `ghp_...` token you created)
2. Create a new Gist or connect to existing one

Then push your current settings:

```
/sync:push
```

Done! Your settings are now synced to the cloud.

---

### Setting Up a New Device

```bash
# 1. Clone the plugin
git clone https://github.com/AnthonySu/claude-settings-sync.git ~/.claude/plugins/claude-settings-sync

# 2. Make scripts executable
chmod +x ~/.claude/plugins/claude-settings-sync/scripts/*.sh

# 3. Start Claude with the plugin
claude --plugin-dir ~/.claude/plugins/claude-settings-sync

# 4. In Claude, run setup with the SAME GitHub token
/sync:setup

# 5. Pull your settings
/sync:pull

# 6. Restart Claude for changes to take effect
```

---

### Commands

| Command | Description |
|---------|-------------|
| `/sync:setup` | Configure GitHub token and create/link Gist |
| `/sync:push` | Upload local settings to Gist |
| `/sync:pull` | Download settings from Gist to local |
| `/sync:status` | Show configuration and sync status |

---

### What Gets Synced

| Item | Location | Synced |
|------|----------|--------|
| Settings | `~/.claude/settings.json` | ✅ Yes |
| User Instructions | `~/.claude/CLAUDE.md` | ✅ Yes |
| Skills | `~/.claude/skills/` | ✅ Yes |
| Agents | `~/.claude/agents/` | ✅ Yes |
| Commands | `~/.claude/commands/` | ✅ Yes |
| MCP Servers | `~/.claude.json` | ❌ No (may contain secrets) |

---

### Permanent Installation

To always load this plugin, add to `~/.claude/settings.json`:

```json
{
  "plugins": [
    "~/.claude/plugins/claude-settings-sync"
  ]
}
```

---

### Configuration

Config stored at `~/.claude/plugins-config/sync-config.json`:

```json
{
  "github_token": "ghp_xxx",
  "gist_id": "abc123...",
  "auto_sync": {
    "pull_on_start": false,
    "push_on_end": false
  },
  "backup": {
    "keep_local_backups": 5
  }
}
```

#### Enable Auto-Sync (Optional)

```json
{
  "auto_sync": {
    "pull_on_start": true
  }
}
```

---

### Backups

Local backups are created automatically before every sync:

```
~/.claude/sync-backups/
├── backup_20250107_103045/
└── backup_20250107_112030/
```

---

### Security

- GitHub token stored locally with `600` permissions
- Gist is **private** (only you can see it)
- MCP configs excluded by default (may contain API keys)

---

### Troubleshooting

| Problem | Solution |
|---------|----------|
| "Token invalid" | Generate new token at github.com/settings/tokens |
| "Gist not found" | Run `/sync:setup` again |
| "Permission denied" | Run `chmod +x ~/.claude/plugins/claude-settings-sync/scripts/*.sh` |

---

### Requirements

- `curl`, `jq`, `tar`, `base64` (pre-installed on macOS/Linux)

---

## License

MIT

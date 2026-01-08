---
description: Pull Claude Code settings from GitHub Gist
allowed-tools: Bash, Read, Write
---

# Pull Settings

Download Claude Code settings from the configured GitHub Gist to this device.

## What Gets Pulled

- `settings.json` -> `~/.claude/settings.json`
- `CLAUDE.md` -> `~/.claude/CLAUDE.md`
- `commands_*.md` -> `~/.claude/commands/`
- `skills_*` -> `~/.claude/skills/`

## Steps

1. **Read config** from `~/.claude/plugins-config/sync-config.json` to get token and gist_id

2. **Create backup** before pulling:
   ```bash
   BACKUP_DIR=~/.claude/sync-backups/backup_$(date +%Y%m%d_%H%M%S)
   mkdir -p "$BACKUP_DIR"
   cp ~/.claude/settings.json "$BACKUP_DIR/" 2>/dev/null
   cp ~/.claude/CLAUDE.md "$BACKUP_DIR/" 2>/dev/null
   cp -r ~/.claude/commands "$BACKUP_DIR/" 2>/dev/null
   ```

3. **Fetch gist content**:
   ```bash
   curl -s -H "Authorization: token <TOKEN>" "https://api.github.com/gists/<GIST_ID>" > /tmp/gist_content.json
   ```

4. **Extract and write files**:
   ```bash
   # settings.json
   jq -r '.files["settings.json"].content // empty' /tmp/gist_content.json > ~/.claude/settings.json.new && mv ~/.claude/settings.json.new ~/.claude/settings.json

   # CLAUDE.md
   jq -r '.files["CLAUDE.md"].content // empty' /tmp/gist_content.json > ~/.claude/CLAUDE.md.new && mv ~/.claude/CLAUDE.md.new ~/.claude/CLAUDE.md

   # Commands (files named commands_*.md)
   for key in $(jq -r '.files | keys[]' /tmp/gist_content.json | grep '^commands_'); do
     fname="${key#commands_}"
     jq -r --arg k "$key" '.files[$k].content' /tmp/gist_content.json > ~/.claude/commands/"$fname"
   done
   ```

5. **Update last_sync** in config file

6. **Report success** and remind user to restart Claude Code for changes to take effect

---
description: Push local Claude Code settings to GitHub Gist
allowed-tools: Bash, Read
---

# Push Settings

Upload local Claude Code settings to the configured GitHub Gist.

## What Gets Synced

- `~/.claude/settings.json` - Claude Code settings
- `~/.claude/CLAUDE.md` - User instructions
- `~/.claude/skills/` - Custom skills (top-level only, large packages excluded)
- `~/.claude/commands/` - Custom commands

## Steps

1. **Read config** from `~/.claude/plugins-config/sync-config.json` to get token and gist_id

2. **Build gist payload** with jq:
   ```bash
   cd ~/.claude
   jq -n '{"description": "claude-settings-sync", "files": {}}' > /tmp/gist_payload.json

   # Add settings.json
   jq --arg content "$(cat settings.json)" '.files["settings.json"] = {"content": $content}' /tmp/gist_payload.json > /tmp/gist_tmp.json && mv /tmp/gist_tmp.json /tmp/gist_payload.json

   # Add CLAUDE.md
   jq --arg content "$(cat CLAUDE.md)" '.files["CLAUDE.md"] = {"content": $content}' /tmp/gist_payload.json > /tmp/gist_tmp.json && mv /tmp/gist_tmp.json /tmp/gist_payload.json

   # Add commands
   for f in commands/*.md; do
     [ -f "$f" ] && jq --arg name "commands_$(basename "$f")" --arg content "$(cat "$f")" '.files[$name] = {"content": $content}' /tmp/gist_payload.json > /tmp/gist_tmp.json && mv /tmp/gist_tmp.json /tmp/gist_payload.json
   done

   # Add manifest
   jq --arg content "{\"synced_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"device\": \"$(hostname)\"}" '.files["manifest.json"] = {"content": $content}' /tmp/gist_payload.json > /tmp/gist_tmp.json && mv /tmp/gist_tmp.json /tmp/gist_payload.json
   ```

3. **Push to gist**:
   ```bash
   curl -s -X PATCH -H "Authorization: token <TOKEN>" -H "Accept: application/vnd.github+json" -d @/tmp/gist_payload.json "https://api.github.com/gists/<GIST_ID>" | jq -r '.html_url // .message'
   ```

4. **Update last_sync** in config file

5. **Report success** with gist URL

Note: MCP server configs are not synced (may contain secrets). Gist maintains version history on GitHub.

---
description: Check for and install plugin updates
---

# Claude Settings Sync - Update

Check for plugin updates and install them.

## Execution

Run the update script:

```bash
bash "$HOME/.claude/plugins/marketplaces/claude-settings-sync/scripts/update.sh" "$ARGUMENTS"
```

## Options

- `--check` - Only check for updates, don't install
- `--force` - Update without confirmation (also reinstalls if already up-to-date)

## Examples

- Check for updates: `/claude-settings-sync:update --check`
- Install updates: `/claude-settings-sync:update`
- Force reinstall: `/claude-settings-sync:update --force`

## What Gets Updated

- All plugin scripts (push.sh, pull.sh, status.sh, etc.)
- Command files
- Core utilities

**Note:** Your sync configuration (GitHub token, Gist ID) is preserved during updates.

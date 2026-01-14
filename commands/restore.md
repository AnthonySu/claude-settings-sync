---
name: restore
description: Restore settings from a local backup
---

$ARGUMENTS

Run the restore script to recover from a local backup:

```bash
~/.claude/plugins/marketplaces/claude-settings-sync/scripts/restore.sh $ARGUMENTS
```

## Options

- `--list` - Show all available backups with details
- `backup_YYYYMMDD_HHMMSS` - Restore a specific backup by name

## Examples

- `/claude-settings-sync:restore` - Interactive selection
- `/claude-settings-sync:restore --list` - List all backups
- `/claude-settings-sync:restore backup_20250114_153022` - Restore specific backup

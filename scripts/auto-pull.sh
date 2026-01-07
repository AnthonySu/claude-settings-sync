#!/bin/bash
# auto-pull.sh - Auto-pull settings on session start (if enabled)
# This script runs silently and only pulls if auto_sync.pull_on_start is true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utils quietly
source "$SCRIPT_DIR/utils.sh" 2>/dev/null

# Check if configured
if ! config_exists; then
    exit 0
fi

# Check if auto-pull is enabled
auto_pull=$(get_config_value "auto_sync.pull_on_start")
if [ "$auto_pull" != "true" ]; then
    exit 0
fi

# Run pull silently
"$SCRIPT_DIR/pull.sh" --force > /dev/null 2>&1

exit 0

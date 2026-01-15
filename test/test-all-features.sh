#!/bin/bash
# test-all-features.sh - Comprehensive test of all claude-settings-sync features
# Continues on errors and reports all at the end

set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ERRORS=()
PASS=0
FAIL=0

log_test() { echo -e "${CYAN}[TEST]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ERRORS+=("$1")
    ((FAIL++))
}
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

run_test() {
    local name="$1"
    local cmd="$2"
    local expect_success="${3:-true}"

    echo ""
    log_test "$name"
    echo "  Command: $cmd"

    output=$(eval "$cmd" 2>&1)
    exit_code=$?

    echo "  Exit code: $exit_code"
    if [ -n "$output" ]; then
        echo "  Output (first 10 lines):"
        echo "$output" | head -10 | sed 's/^/    /'
        if [ $(echo "$output" | wc -l) -gt 10 ]; then
            echo "    ... (truncated)"
        fi
    fi

    if [ "$expect_success" = "true" ]; then
        if [ $exit_code -eq 0 ]; then
            log_pass "$name"
            return 0
        else
            log_fail "$name (expected success, got exit code $exit_code)"
            return 1
        fi
    else
        if [ $exit_code -ne 0 ]; then
            log_pass "$name (expected failure)"
            return 0
        else
            log_fail "$name (expected failure, but succeeded)"
            return 1
        fi
    fi
}

check_contains() {
    local name="$1"
    local output="$2"
    local pattern="$3"

    if echo "$output" | grep -q "$pattern"; then
        log_pass "$name - contains '$pattern'"
        return 0
    else
        log_fail "$name - missing '$pattern'"
        return 1
    fi
}

SCRIPTS_DIR="$HOME/.claude/plugins/marketplaces/claude-settings-sync/scripts"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║     Claude Settings Sync - Comprehensive Feature Tests     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Scripts directory: $SCRIPTS_DIR"
echo ""

# ============================================================
# SECTION 1: Installation Verification
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 1: Installation Verification"
echo "════════════════════════════════════════"

log_test "Plugin directory exists"
if [ -d "$HOME/.claude/plugins/marketplaces/claude-settings-sync" ]; then
    log_pass "Plugin directory exists"
else
    log_fail "Plugin directory missing"
fi

log_test "Scripts are executable"
for script in push.sh pull.sh status.sh setup.sh restore.sh; do
    if [ -x "$SCRIPTS_DIR/$script" ]; then
        log_pass "  $script is executable"
    else
        log_fail "  $script is not executable or missing"
    fi
done

log_test "Command files exist"
for cmd in push.md pull.md status.md setup.md restore.md; do
    if [ -f "$HOME/.claude/plugins/marketplaces/claude-settings-sync/commands/$cmd" ]; then
        log_pass "  $cmd exists"
    else
        log_fail "  $cmd missing"
    fi
done

log_test "Plugin registered in settings.json"
if jq -e '.extraKnownMarketplaces["claude-settings-sync"]' ~/.claude/settings.json > /dev/null 2>&1; then
    log_pass "Plugin in extraKnownMarketplaces"
else
    log_fail "Plugin not in extraKnownMarketplaces"
fi

if jq -e '.enabledPlugins["claude-settings-sync@claude-settings-sync"]' ~/.claude/settings.json > /dev/null 2>&1; then
    log_pass "Plugin in enabledPlugins"
else
    log_fail "Plugin not in enabledPlugins"
fi

# ============================================================
# SECTION 2: Status Command
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 2: Status Command"
echo "════════════════════════════════════════"

log_test "Status command runs successfully"
output=$("$SCRIPTS_DIR/status.sh" 2>&1)
exit_code=$?
echo "  Exit code: $exit_code"

if [ $exit_code -eq 0 ]; then
    log_pass "Status command completed"
else
    log_fail "Status command failed with exit code $exit_code"
fi

# ============================================================
# SECTION 3: Setup and Configuration
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 3: Setup and Configuration"
echo "════════════════════════════════════════"

# Check if config was injected
if [ -f "$HOME/.claude/plugins-config/sync-config.json" ]; then
    log_pass "Config file exists (injected)"

    log_test "Config has required fields"
    if jq -e '.github_token' "$HOME/.claude/plugins-config/sync-config.json" > /dev/null 2>&1; then
        log_pass "github_token present"
    else
        log_fail "github_token missing"
    fi

    if jq -e '.gist_id' "$HOME/.claude/plugins-config/sync-config.json" > /dev/null 2>&1; then
        log_pass "gist_id present"
    else
        log_fail "gist_id missing"
    fi
else
    log_info "No config file - skipping API tests (run with config injection for full tests)"
    echo ""
    echo "════════════════════════════════════════"
    echo "  SKIPPING API-dependent tests"
    echo "════════════════════════════════════════"

    # Still test non-API features
    echo ""
    echo "════════════════════════════════════════"
    echo "  Testing Non-API Features"
    echo "════════════════════════════════════════"

    log_test "Restore --list with no backups"
    output=$("$SCRIPTS_DIR/restore.sh" --list 2>&1)
    if echo "$output" | grep -qi "no backups\|empty\|not found"; then
        log_pass "Restore --list handles no backups"
    else
        log_fail "Restore --list unexpected output: $output"
    fi

    # Jump to summary
    goto_summary=true
fi

if [ "$goto_summary" != "true" ]; then

# ============================================================
# SECTION 4: Status with Config
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 4: Status with Config"
echo "════════════════════════════════════════"

log_test "Status with config shows sync info"
output=$("$SCRIPTS_DIR/status.sh" 2>&1)
exit_code=$?
echo "  Exit code: $exit_code"

check_contains "Status output" "$output" "Last sync\|Gist ID\|Device"

# ============================================================
# SECTION 5: Push Features
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 5: Push Features"
echo "════════════════════════════════════════"

# 5a. Push dry run
log_test "Push --dry-run"
output=$("$SCRIPTS_DIR/push.sh" --dry-run 2>&1)
exit_code=$?
echo "  Exit code: $exit_code"
echo "  Output preview:"
echo "$output" | head -15 | sed 's/^/    /'

if [ $exit_code -eq 0 ]; then
    log_pass "Push dry-run completed"
else
    log_fail "Push dry-run failed with exit code $exit_code"
fi

check_contains "Dry-run output" "$output" "DRY RUN\|dry.run\|would"

# 5b. Push --only flag
log_test "Push --only=commands (dry-run)"
output=$("$SCRIPTS_DIR/push.sh" --only=commands --dry-run 2>&1)
exit_code=$?
echo "  Exit code: $exit_code"

if [ $exit_code -eq 0 ]; then
    log_pass "Push --only=commands dry-run completed"
else
    log_fail "Push --only=commands failed with exit code $exit_code"
fi

# 5c. Invalid --only value
log_test "Push --only=invalid (should fail or warn)"
output=$("$SCRIPTS_DIR/push.sh" --only=invalid --dry-run 2>&1)
if echo "$output" | grep -qi "invalid\|unknown\|error"; then
    log_pass "Push --only=invalid rejected"
else
    log_fail "Push --only=invalid should be rejected"
fi

# 5d. Push --only with multiple items
log_test "Push --only=commands,CLAUDE.md (dry-run)"
output=$("$SCRIPTS_DIR/push.sh" --only=commands,CLAUDE.md --dry-run 2>&1)
exit_code=$?
if [ $exit_code -eq 0 ]; then
    log_pass "Push --only with multiple items"
else
    log_fail "Push --only with multiple items failed"
fi

# ============================================================
# SECTION 6: Pull Features
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 6: Pull Features"
echo "════════════════════════════════════════"

# 6a. Pull --diff
log_test "Pull --diff (preview changes)"
output=$("$SCRIPTS_DIR/pull.sh" --diff 2>&1)
exit_code=$?
echo "  Exit code: $exit_code"
echo "  Output preview:"
echo "$output" | head -20 | sed 's/^/    /'

if [ $exit_code -eq 0 ]; then
    log_pass "Pull --diff completed"
else
    log_fail "Pull --diff failed with exit code $exit_code"
fi

# 6b. Pull --only flag
log_test "Pull --only=commands --diff"
output=$("$SCRIPTS_DIR/pull.sh" --only=commands --diff 2>&1)
exit_code=$?
if [ $exit_code -eq 0 ]; then
    log_pass "Pull --only=commands --diff completed"
else
    log_fail "Pull --only=commands --diff failed"
fi

# 6c. Invalid --only value for pull
log_test "Pull --only=invalid (should fail or warn)"
output=$("$SCRIPTS_DIR/pull.sh" --only=invalid --diff 2>&1)
if echo "$output" | grep -qi "invalid\|unknown\|error"; then
    log_pass "Pull --only=invalid rejected"
else
    log_fail "Pull --only=invalid should be rejected"
fi

# ============================================================
# SECTION 7: Conflict Detection
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 7: Conflict Detection"
echo "════════════════════════════════════════"

log_test "Pull conflict detection message"
# Touch a local file to make it newer
touch "$HOME/.claude/settings.json"
sleep 1
output=$("$SCRIPTS_DIR/pull.sh" --diff 2>&1)

if echo "$output" | grep -qi "conflict\|modified\|newer\|warning"; then
    log_pass "Conflict detection warning shown"
else
    log_fail "Conflict detection should warn about local changes"
fi

# ============================================================
# SECTION 8: Restore Features
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 8: Restore Features"
echo "════════════════════════════════════════"

# 8a. Restore --list
log_test "Restore --list (no backups exist yet)"
output=$("$SCRIPTS_DIR/restore.sh" --list 2>&1)
exit_code=$?
echo "  Exit code: $exit_code"
echo "  Output:"
echo "$output" | head -10 | sed 's/^/    /'

# Should return 0 even when no backups exist (informational)
if [ $exit_code -eq 0 ]; then
    log_pass "Restore --list completed"
    if echo "$output" | grep -qi "no backup"; then
        log_pass "Restore --list correctly reports no backups"
    fi
else
    log_fail "Restore --list failed (exit code $exit_code)"
fi

# 8b. Restore --help
log_test "Restore --help"
output=$("$SCRIPTS_DIR/restore.sh" --help 2>&1)
if echo "$output" | grep -qi "usage\|help\|restore"; then
    log_pass "Restore --help shows usage"
else
    log_fail "Restore --help should show usage"
fi

# End of API-dependent tests
fi

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                      TEST SUMMARY                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo -e "  ${GREEN}Passed:${NC} $PASS"
echo -e "  ${RED}Failed:${NC} $FAIL"
echo ""

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo -e "${RED}ERRORS:${NC}"
    for err in "${ERRORS[@]}"; do
        echo -e "  - $err"
    done
    echo ""
fi

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ALL TESTS PASSED!${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    exit 0
else
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  $FAIL TEST(S) FAILED - See errors above${NC}"
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    exit 1
fi

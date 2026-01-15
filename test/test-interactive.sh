#!/bin/bash
# test-interactive.sh - Comprehensive interactive testing like a human would
# Tests all features with real commands and logs all errors

set -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PLUGIN_DIR="/plugin"
CLAUDE_DIR="$HOME/.claude"
CONFIG_DIR="$HOME/.claude/plugins-config"
ERRORS=()
PASS=0
FAIL=0

log_test() { echo -e "\n${CYAN}[TEST]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1: $2"); }
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

run_cmd() {
    local desc="$1"
    shift
    local output
    local exit_code

    log_test "$desc"
    echo "  Command: $*"

    output=$("$@" 2>&1)
    exit_code=$?

    echo "$output" | head -30
    if [ $(echo "$output" | wc -l) -gt 30 ]; then
        echo "  ... (truncated)"
    fi

    echo "  Exit code: $exit_code"
    echo "$output"
    return $exit_code
}

expect_success() {
    local desc="$1"
    shift
    if run_cmd "$desc" "$@"; then
        log_pass "$desc"
    else
        log_fail "$desc" "Expected success but got exit code $?"
    fi
}

expect_fail() {
    local desc="$1"
    shift
    if run_cmd "$desc" "$@"; then
        log_fail "$desc" "Expected failure but got success"
    else
        log_pass "$desc (expected failure)"
    fi
}

expect_output() {
    local desc="$1"
    local pattern="$2"
    shift 2
    local output

    output=$(run_cmd "$desc" "$@")
    if echo "$output" | grep -q "$pattern"; then
        log_pass "$desc"
    else
        log_fail "$desc" "Expected output containing '$pattern'"
    fi
}

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║       Interactive Feature Testing - Like a Human          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================
# Phase 1: Setup and Prerequisites
# ============================================================
echo ""
echo "┌─ Phase 1: Setup and Prerequisites ─────────────────────────┐"

log_test "Check plugin scripts exist"
for script in status.sh push.sh pull.sh setup.sh restore.sh update.sh utils.sh; do
    if [ -f "$PLUGIN_DIR/scripts/$script" ]; then
        log_pass "  $script exists"
    else
        log_fail "  $script missing" "File not found"
    fi
done

log_test "Check VERSION file"
if [ -f "$PLUGIN_DIR/VERSION" ]; then
    version=$(cat "$PLUGIN_DIR/VERSION")
    log_pass "VERSION file exists: $version"
else
    log_fail "VERSION file" "Not found"
fi

# ============================================================
# Phase 2: Status Command (Before Config)
# ============================================================
echo ""
echo "┌─ Phase 2: Status Without Config ───────────────────────────┐"

expect_fail "Status without config should fail gracefully" \
    bash "$PLUGIN_DIR/scripts/status.sh"

# ============================================================
# Phase 3: Setup with Config Injection
# ============================================================
echo ""
echo "┌─ Phase 3: Config Setup ────────────────────────────────────┐"

log_test "Inject test configuration"
mkdir -p "$CONFIG_DIR"
if [ -n "$TEST_CONFIG" ]; then
    echo "$TEST_CONFIG" | base64 -d > "$CONFIG_DIR/sync-config.json"
    log_pass "Config injected from TEST_CONFIG env"
else
    # Create minimal test config (will fail on actual API calls)
    cat > "$CONFIG_DIR/sync-config.json" << 'EOF'
{
    "github_token": "test_token_placeholder",
    "gist_id": "test_gist_placeholder",
    "device_name": "docker-test"
}
EOF
    log_info "Created placeholder config (API calls will fail)"
fi

cat "$CONFIG_DIR/sync-config.json" | jq '.' 2>/dev/null || log_fail "Config JSON invalid" "Parse error"

# ============================================================
# Phase 4: Status Command (With Config)
# ============================================================
echo ""
echo "┌─ Phase 4: Status With Config ──────────────────────────────┐"

expect_success "Status with config shows version" \
    bash "$PLUGIN_DIR/scripts/status.sh"

# ============================================================
# Phase 5: Push Command Tests
# ============================================================
echo ""
echo "┌─ Phase 5: Push Command Tests ──────────────────────────────┐"

expect_success "Push --dry-run shows what would be synced" \
    bash "$PLUGIN_DIR/scripts/push.sh" --dry-run

expect_success "Push --dry-run --only=commands" \
    bash "$PLUGIN_DIR/scripts/push.sh" --dry-run --only=commands

expect_success "Push --dry-run --only=CLAUDE.md,commands" \
    bash "$PLUGIN_DIR/scripts/push.sh" --dry-run --only=CLAUDE.md,commands

expect_fail "Push --only= (empty) should fail" \
    bash "$PLUGIN_DIR/scripts/push.sh" --dry-run --only=

expect_fail "Push --only=invalid should fail" \
    bash "$PLUGIN_DIR/scripts/push.sh" --dry-run --only=invalid_item

# ============================================================
# Phase 6: Pull Command Tests
# ============================================================
echo ""
echo "┌─ Phase 6: Pull Command Tests ──────────────────────────────┐"

expect_success "Pull --dry-run" \
    bash "$PLUGIN_DIR/scripts/pull.sh" --dry-run

expect_success "Pull --diff (preview mode)" \
    bash "$PLUGIN_DIR/scripts/pull.sh" --diff

# ============================================================
# Phase 7: Restore Command Tests
# ============================================================
echo ""
echo "┌─ Phase 7: Restore Command Tests ───────────────────────────┐"

expect_success "Restore --list when no backups" \
    bash "$PLUGIN_DIR/scripts/restore.sh" --list

expect_success "Restore --help" \
    bash "$PLUGIN_DIR/scripts/restore.sh" --help

expect_fail "Restore non-existent backup" \
    bash "$PLUGIN_DIR/scripts/restore.sh" --backup=nonexistent_backup

# ============================================================
# Phase 8: Update Command Tests
# ============================================================
echo ""
echo "┌─ Phase 8: Update Command Tests ────────────────────────────┐"

expect_success "Update --check" \
    bash "$PLUGIN_DIR/scripts/update.sh" --check

# ============================================================
# Phase 9: Corner Cases - Invalid Inputs
# ============================================================
echo ""
echo "┌─ Phase 9: Corner Cases - Invalid Inputs ───────────────────┐"

expect_fail "Push with injection attempt in --only" \
    bash "$PLUGIN_DIR/scripts/push.sh" --dry-run --only='commands;rm -rf /'

expect_fail "Push with pipe in --only" \
    bash "$PLUGIN_DIR/scripts/push.sh" --dry-run --only='commands|cat /etc/passwd'

expect_fail "Push with backtick in --only" \
    bash "$PLUGIN_DIR/scripts/push.sh" --dry-run --only='`whoami`'

# ============================================================
# Phase 10: Corner Cases - Config Edge Cases
# ============================================================
echo ""
echo "┌─ Phase 10: Corner Cases - Config ──────────────────────────┐"

# Helper to strip ANSI codes
strip_ansi() {
    sed 's/\x1b\[[0-9;]*m//g'
}

log_test "Corrupted config handling"
cp "$CONFIG_DIR/sync-config.json" "$CONFIG_DIR/sync-config.json.bak"
echo "not json" > "$CONFIG_DIR/sync-config.json"
output=$(bash "$PLUGIN_DIR/scripts/status.sh" 2>&1 | strip_ansi)
if echo "$output" | grep -q -i -E "invalid|corrupt|error"; then
    log_pass "Corrupted config detected"
else
    log_fail "Corrupted config" "Should show error message"
    echo "  Output was: $output"
fi
mv "$CONFIG_DIR/sync-config.json.bak" "$CONFIG_DIR/sync-config.json"

log_test "Empty config handling"
mkdir -p "$CONFIG_DIR/empty-test"
echo "" > "$CONFIG_DIR/empty-test/sync-config.json"
output=$(CONFIG_DIR="$CONFIG_DIR/empty-test" bash "$PLUGIN_DIR/scripts/status.sh" 2>&1 | strip_ansi)
if echo "$output" | grep -q -i -E "error|invalid|not configured"; then
    log_pass "Empty config detected"
else
    log_fail "Empty config" "Should show error"
    echo "  Output was: $output"
fi
rm -rf "$CONFIG_DIR/empty-test"

log_test "Missing token handling"
cp "$CONFIG_DIR/sync-config.json" "$CONFIG_DIR/sync-config.json.bak"
jq 'del(.github_token)' "$CONFIG_DIR/sync-config.json" > "$CONFIG_DIR/sync-config.json.tmp"
mv "$CONFIG_DIR/sync-config.json.tmp" "$CONFIG_DIR/sync-config.json"
output=$(bash "$PLUGIN_DIR/scripts/push.sh" --dry-run 2>&1 | strip_ansi)
if echo "$output" | grep -q -i -E "token|error|not found"; then
    log_pass "Missing token detected by push"
else
    log_fail "Missing token" "Push should detect missing token"
    echo "  Output was: $output"
fi
mv "$CONFIG_DIR/sync-config.json.bak" "$CONFIG_DIR/sync-config.json"

# ============================================================
# Phase 11: Real Push/Pull (if real config)
# ============================================================
echo ""
echo "┌─ Phase 11: Real Push/Pull (if configured) ─────────────────┐"

if [ -n "$TEST_CONFIG" ]; then
    log_info "Real config detected - testing actual push/pull"

    # Test actual push with --force (non-interactive)
    log_test "Real push --force"
    if bash "$PLUGIN_DIR/scripts/push.sh" --force 2>&1; then
        log_pass "Real push succeeded"
    else
        log_fail "Real push" "Push failed"
    fi

    # Test actual pull with --force
    log_test "Real pull --force"
    if bash "$PLUGIN_DIR/scripts/pull.sh" --force 2>&1; then
        log_pass "Real pull succeeded"
    else
        log_fail "Real pull" "Pull failed"
    fi

    # Verify restore list now has backups
    log_test "Restore --list after push/pull"
    output=$(bash "$PLUGIN_DIR/scripts/restore.sh" --list 2>&1 | strip_ansi)
    if echo "$output" | grep -q -i "backup"; then
        log_pass "Backups created"
    else
        log_fail "Backups" "No backups found after push/pull"
        echo "  Output was: $output"
    fi
else
    log_info "No real config - skipping actual push/pull tests"
fi

# ============================================================
# Phase 12: Special Characters in Files
# ============================================================
echo ""
echo "┌─ Phase 12: Special Characters ─────────────────────────────┐"

log_test "CLAUDE.md with unicode"
echo "# Test with émojis 🚀 and ñ special chars" > "$CLAUDE_DIR/CLAUDE.md"
if bash "$PLUGIN_DIR/scripts/push.sh" --dry-run 2>&1; then
    log_pass "Unicode in CLAUDE.md handled"
else
    log_fail "Unicode CLAUDE.md" "Push failed with unicode"
fi

log_test "Command file with special name"
echo "---\ntest\n---" > "$CLAUDE_DIR/commands/test-file.md"
if bash "$PLUGIN_DIR/scripts/push.sh" --dry-run 2>&1; then
    log_pass "Hyphenated filename handled"
else
    log_fail "Hyphenated filename" "Push failed"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                      Test Summary                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo -e "  ${GREEN}Passed:${NC} $PASS"
echo -e "  ${RED}Failed:${NC} $FAIL"
echo ""

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "┌─ Errors ────────────────────────────────────────────────────┐"
    for err in "${ERRORS[@]}"; do
        echo -e "│ ${RED}✗${NC} $err"
    done
    echo "└──────────────────────────────────────────────────────────────┘"
fi

echo ""
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}$FAIL test(s) failed${NC}"
    exit 1
fi

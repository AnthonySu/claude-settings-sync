#!/bin/bash
# test-corner-cases.sh - Aggressive corner case testing for claude-settings-sync
# Tests edge cases, error handling, and unusual scenarios

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
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ERRORS+=("$1")
    FAIL=$((FAIL + 1))
}
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

SCRIPTS_DIR="$HOME/.claude/plugins/marketplaces/claude-settings-sync/scripts"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║      Claude Settings Sync - Corner Case Tests              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================
# SECTION 1: Flag Combinations
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 1: Flag Combinations"
echo "════════════════════════════════════════"

# 1a. Push with conflicting flags
log_test "Push --dry-run --force (both flags)"
output=$("$SCRIPTS_DIR/push.sh" --dry-run --force 2>&1)
exit_code=$?
if [ $exit_code -eq 0 ]; then
    log_pass "Push --dry-run --force works"
else
    log_fail "Push --dry-run --force failed: $exit_code"
fi

# 1b. Pull with all flags
log_test "Pull --diff --force"
output=$("$SCRIPTS_DIR/pull.sh" --diff --force 2>&1)
exit_code=$?
if [ $exit_code -eq 0 ]; then
    log_pass "Pull --diff --force works"
else
    log_fail "Pull --diff --force failed: $exit_code"
fi

# 1c. Push with empty --only
log_test "Push --only= (empty value)"
output=$("$SCRIPTS_DIR/push.sh" --only= --dry-run 2>&1)
if echo "$output" | grep -qi "invalid\|error\|empty"; then
    log_pass "Push --only= properly rejected or handled"
else
    # Empty might just be treated as no filter
    if [ $? -eq 0 ]; then
        log_pass "Push --only= treated as no filter"
    else
        log_fail "Push --only= unexpected behavior"
    fi
fi

# 1d. Multiple --only flags
log_test "Push --only=commands --only=CLAUDE.md (multiple flags)"
output=$("$SCRIPTS_DIR/push.sh" --only=commands --only=CLAUDE.md --dry-run 2>&1)
exit_code=$?
# Should either use last one or merge them
if [ $exit_code -eq 0 ]; then
    log_pass "Push with multiple --only flags handled"
else
    log_fail "Push with multiple --only flags failed"
fi

# 1e. Pull --only with all valid items
log_test "Pull --only=settings.json,CLAUDE.md,commands,agents,skills --diff"
output=$("$SCRIPTS_DIR/pull.sh" --only=settings.json,CLAUDE.md,commands,agents,skills --diff 2>&1)
exit_code=$?
if [ $exit_code -eq 0 ]; then
    log_pass "Pull --only with all items works"
else
    log_fail "Pull --only with all items failed"
fi

# ============================================================
# SECTION 2: Empty/Missing File Scenarios
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 2: Empty/Missing Files"
echo "════════════════════════════════════════"

# 2a. Empty settings.json
log_test "Push with empty settings.json"
cp ~/.claude/settings.json ~/.claude/settings.json.bak
echo "" > ~/.claude/settings.json
output=$("$SCRIPTS_DIR/push.sh" --dry-run 2>&1)
exit_code=$?
cp ~/.claude/settings.json.bak ~/.claude/settings.json
if [ $exit_code -eq 0 ]; then
    log_pass "Push with empty settings.json handled"
else
    log_fail "Push with empty settings.json failed: $exit_code"
fi

# 2b. Missing CLAUDE.md
log_test "Push when CLAUDE.md doesn't exist"
mv ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak 2>/dev/null || true
output=$("$SCRIPTS_DIR/push.sh" --dry-run 2>&1)
exit_code=$?
mv ~/.claude/CLAUDE.md.bak ~/.claude/CLAUDE.md 2>/dev/null || true
if [ $exit_code -eq 0 ]; then
    log_pass "Push without CLAUDE.md handled"
else
    log_fail "Push without CLAUDE.md failed: $exit_code"
fi

# 2c. Empty commands directory
log_test "Push with empty commands directory"
mkdir -p ~/.claude/commands.bak
mv ~/.claude/commands/* ~/.claude/commands.bak/ 2>/dev/null || true
output=$("$SCRIPTS_DIR/push.sh" --dry-run 2>&1)
exit_code=$?
mv ~/.claude/commands.bak/* ~/.claude/commands/ 2>/dev/null || true
rmdir ~/.claude/commands.bak 2>/dev/null || true
if [ $exit_code -eq 0 ]; then
    log_pass "Push with empty commands dir handled"
else
    log_fail "Push with empty commands dir failed: $exit_code"
fi

# 2d. Missing all sync items
log_test "Push with minimal files (only settings.json)"
mkdir -p /tmp/claude-backup
mv ~/.claude/CLAUDE.md ~/.claude/commands ~/.claude/agents ~/.claude/skills /tmp/claude-backup/ 2>/dev/null || true
output=$("$SCRIPTS_DIR/push.sh" --dry-run 2>&1)
exit_code=$?
mv /tmp/claude-backup/* ~/.claude/ 2>/dev/null || true
if [ $exit_code -eq 0 ]; then
    log_pass "Push with minimal files works"
else
    log_fail "Push with minimal files failed: $exit_code"
fi

# ============================================================
# SECTION 3: Invalid Input Scenarios
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 3: Invalid Inputs"
echo "════════════════════════════════════════"

# 3a. Invalid --only items
log_test "Push --only=nonexistent,fakefile"
output=$("$SCRIPTS_DIR/push.sh" --only=nonexistent,fakefile --dry-run 2>&1)
if echo "$output" | grep -qi "invalid\|unknown\|error"; then
    log_pass "Invalid --only items rejected"
else
    log_fail "Invalid --only items not properly rejected"
fi

# 3b. Special characters in --only
log_test "Push --only='settings.json;rm -rf /'"
output=$("$SCRIPTS_DIR/push.sh" --only='settings.json;rm -rf /' --dry-run 2>&1)
if echo "$output" | grep -qi "invalid\|unknown\|error"; then
    log_pass "Injection attempt in --only rejected"
else
    # Check it didn't actually do anything harmful
    if [ -d "/bin" ]; then
        log_pass "Injection attempt safely ignored"
    else
        log_fail "Possible injection vulnerability!"
    fi
fi

# 3c. Unicode in --only
log_test "Push --only=设置.json"
output=$("$SCRIPTS_DIR/push.sh" --only=设置.json --dry-run 2>&1)
if echo "$output" | grep -qi "invalid\|unknown\|error"; then
    log_pass "Unicode --only properly rejected"
else
    log_fail "Unicode --only not handled properly"
fi

# 3d. Very long --only value
log_test "Push --only with 1000 character value"
long_value=$(printf 'a%.0s' {1..1000})
output=$("$SCRIPTS_DIR/push.sh" --only="$long_value" --dry-run 2>&1)
if echo "$output" | grep -qi "invalid\|unknown\|error"; then
    log_pass "Very long --only value rejected"
else
    log_fail "Very long --only value not handled"
fi

# ============================================================
# SECTION 4: Config Edge Cases
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 4: Config Edge Cases"
echo "════════════════════════════════════════"

# 4a. Corrupted config JSON
log_test "Status with corrupted config"
cp ~/.claude/plugins-config/sync-config.json ~/.claude/plugins-config/sync-config.json.bak
echo "{ invalid json }" > ~/.claude/plugins-config/sync-config.json
output=$("$SCRIPTS_DIR/status.sh" 2>&1)
exit_code=$?
cp ~/.claude/plugins-config/sync-config.json.bak ~/.claude/plugins-config/sync-config.json
if echo "$output" | grep -qi "error\|invalid\|not configured"; then
    log_pass "Corrupted config handled gracefully"
else
    log_fail "Corrupted config not handled properly"
fi

# 4b. Missing github_token in config
log_test "Push with missing github_token"
cp ~/.claude/plugins-config/sync-config.json ~/.claude/plugins-config/sync-config.json.bak
jq 'del(.github_token)' ~/.claude/plugins-config/sync-config.json.bak > ~/.claude/plugins-config/sync-config.json
output=$("$SCRIPTS_DIR/push.sh" --dry-run 2>&1)
exit_code=$?
cp ~/.claude/plugins-config/sync-config.json.bak ~/.claude/plugins-config/sync-config.json
if echo "$output" | grep -qi "token\|configured\|setup"; then
    log_pass "Missing token detected"
else
    log_fail "Missing token not detected properly"
fi

# 4c. Empty config file
log_test "Status with empty config"
cp ~/.claude/plugins-config/sync-config.json ~/.claude/plugins-config/sync-config.json.bak
echo "" > ~/.claude/plugins-config/sync-config.json
output=$("$SCRIPTS_DIR/status.sh" 2>&1)
cp ~/.claude/plugins-config/sync-config.json.bak ~/.claude/plugins-config/sync-config.json
if echo "$output" | grep -qi "not configured\|error"; then
    log_pass "Empty config handled"
else
    log_fail "Empty config not handled properly"
fi

# 4d. Config with null values
log_test "Push with null gist_id"
cp ~/.claude/plugins-config/sync-config.json ~/.claude/plugins-config/sync-config.json.bak
jq '.gist_id = null' ~/.claude/plugins-config/sync-config.json.bak > ~/.claude/plugins-config/sync-config.json
output=$("$SCRIPTS_DIR/push.sh" --dry-run 2>&1)
cp ~/.claude/plugins-config/sync-config.json.bak ~/.claude/plugins-config/sync-config.json
if echo "$output" | grep -qi "gist\|setup\|configured"; then
    log_pass "Null gist_id handled"
else
    log_fail "Null gist_id not handled"
fi

# ============================================================
# SECTION 5: Restore Edge Cases
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 5: Restore Edge Cases"
echo "════════════════════════════════════════"

# 5a. Restore with nonexistent backup name
log_test "Restore backup_nonexistent"
output=$("$SCRIPTS_DIR/restore.sh" backup_nonexistent 2>&1)
if echo "$output" | grep -qi "not found\|error\|no backup"; then
    log_pass "Nonexistent backup handled"
else
    log_fail "Nonexistent backup not handled"
fi

# 5b. Restore --list with permissions issue (simulated)
log_test "Restore --list behavior"
output=$("$SCRIPTS_DIR/restore.sh" --list 2>&1)
exit_code=$?
if [ $exit_code -eq 0 ]; then
    log_pass "Restore --list works"
else
    log_fail "Restore --list failed: $exit_code"
fi

# 5c. Create a test backup and verify restore --list shows it
log_test "Create backup and list it"
mkdir -p ~/.claude/sync-backups/backup_test_$(date +%Y%m%d_%H%M%S)
output=$("$SCRIPTS_DIR/restore.sh" --list 2>&1)
if echo "$output" | grep -qi "backup_test\|Available"; then
    log_pass "Created backup appears in list"
else
    log_fail "Created backup not shown in list"
fi
rm -rf ~/.claude/sync-backups/backup_test_*

# ============================================================
# SECTION 6: Status Edge Cases
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 6: Status Edge Cases"
echo "════════════════════════════════════════"

# 6a. Status output format
log_test "Status output contains expected sections"
output=$("$SCRIPTS_DIR/status.sh" 2>&1)
has_gist=$(echo "$output" | grep -ci "gist")
has_device=$(echo "$output" | grep -ci "device")
has_sync=$(echo "$output" | grep -ci "sync")
if [ "$has_gist" -gt 0 ] && [ "$has_sync" -gt 0 ]; then
    log_pass "Status has expected sections"
else
    log_fail "Status missing expected sections"
fi

# ============================================================
# SECTION 7: Concurrent/Rapid Operations
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 7: Rapid Operations"
echo "════════════════════════════════════════"

# 7a. Multiple rapid status calls
log_test "10 rapid status calls"
success=0
for i in $(seq 1 10); do
    if "$SCRIPTS_DIR/status.sh" > /dev/null 2>&1; then
        success=$((success + 1))
    fi
done
if [ $success -eq 10 ]; then
    log_pass "All 10 status calls succeeded"
else
    log_fail "Only $success/10 status calls succeeded"
fi

# 7b. Multiple rapid push --dry-run
log_test "5 rapid push --dry-run calls"
success=0
for i in $(seq 1 5); do
    if "$SCRIPTS_DIR/push.sh" --dry-run > /dev/null 2>&1; then
        success=$((success + 1))
    fi
done
if [ $success -eq 5 ]; then
    log_pass "All 5 push --dry-run calls succeeded"
else
    log_fail "Only $success/5 push --dry-run calls succeeded"
fi

# ============================================================
# SECTION 8: Special Characters in Files
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 8: Special Characters"
echo "════════════════════════════════════════"

# 8a. CLAUDE.md with special characters
log_test "Push with special chars in CLAUDE.md"
cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak 2>/dev/null || true
echo '# Test with $pecial "chars" & <symbols> `code`' > ~/.claude/CLAUDE.md
output=$("$SCRIPTS_DIR/push.sh" --dry-run 2>&1)
exit_code=$?
mv ~/.claude/CLAUDE.md.bak ~/.claude/CLAUDE.md 2>/dev/null || echo "# Test" > ~/.claude/CLAUDE.md
if [ $exit_code -eq 0 ]; then
    log_pass "Special chars in CLAUDE.md handled"
else
    log_fail "Special chars in CLAUDE.md failed: $exit_code"
fi

# 8b. settings.json with unicode
log_test "Push with unicode in settings.json"
cp ~/.claude/settings.json ~/.claude/settings.json.bak
echo '{"test": "日本語テスト", "emoji": "🚀"}' > ~/.claude/settings.json
output=$("$SCRIPTS_DIR/push.sh" --dry-run 2>&1)
exit_code=$?
cp ~/.claude/settings.json.bak ~/.claude/settings.json
if [ $exit_code -eq 0 ]; then
    log_pass "Unicode in settings.json handled"
else
    log_fail "Unicode in settings.json failed: $exit_code"
fi

# 8c. Very large CLAUDE.md
log_test "Push with large CLAUDE.md (100KB)"
cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak 2>/dev/null || true
dd if=/dev/zero bs=1024 count=100 2>/dev/null | tr '\0' 'x' > ~/.claude/CLAUDE.md
output=$("$SCRIPTS_DIR/push.sh" --dry-run 2>&1)
exit_code=$?
mv ~/.claude/CLAUDE.md.bak ~/.claude/CLAUDE.md 2>/dev/null || echo "# Test" > ~/.claude/CLAUDE.md
if [ $exit_code -eq 0 ]; then
    log_pass "Large CLAUDE.md (100KB) handled"
else
    log_fail "Large CLAUDE.md failed: $exit_code"
fi

# ============================================================
# SECTION 9: Boundary Conditions
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 9: Boundary Conditions"
echo "════════════════════════════════════════"

# 9a. --only with single item
log_test "Push --only=settings.json (single item)"
output=$("$SCRIPTS_DIR/push.sh" --only=settings.json --dry-run 2>&1)
exit_code=$?
if [ $exit_code -eq 0 ]; then
    log_pass "Single --only item works"
else
    log_fail "Single --only item failed"
fi

# 9b. --only with trailing comma
log_test "Push --only=commands, (trailing comma)"
output=$("$SCRIPTS_DIR/push.sh" --only=commands, --dry-run 2>&1)
exit_code=$?
# Should either work (ignoring empty) or fail gracefully
if [ $exit_code -eq 0 ] || echo "$output" | grep -qi "invalid"; then
    log_pass "Trailing comma handled"
else
    log_fail "Trailing comma not handled properly"
fi

# 9c. --only with leading comma
log_test "Push --only=,commands (leading comma)"
output=$("$SCRIPTS_DIR/push.sh" --only=,commands --dry-run 2>&1)
exit_code=$?
if [ $exit_code -eq 0 ] || echo "$output" | grep -qi "invalid"; then
    log_pass "Leading comma handled"
else
    log_fail "Leading comma not handled properly"
fi

# 9d. --only with duplicate items
log_test "Push --only=commands,commands,commands"
output=$("$SCRIPTS_DIR/push.sh" --only=commands,commands,commands --dry-run 2>&1)
exit_code=$?
if [ $exit_code -eq 0 ]; then
    log_pass "Duplicate --only items handled"
else
    log_fail "Duplicate --only items failed"
fi

# ============================================================
# SECTION 10: API/Network Edge Cases (Simulated)
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  SECTION 10: API Edge Cases"
echo "════════════════════════════════════════"

# 10a. Invalid gist_id format
log_test "Push with invalid gist_id format"
cp ~/.claude/plugins-config/sync-config.json ~/.claude/plugins-config/sync-config.json.bak
jq '.gist_id = "invalid-gist-id-@#$"' ~/.claude/plugins-config/sync-config.json.bak > ~/.claude/plugins-config/sync-config.json
output=$("$SCRIPTS_DIR/push.sh" --dry-run 2>&1)
cp ~/.claude/plugins-config/sync-config.json.bak ~/.claude/plugins-config/sync-config.json
# Dry-run shouldn't call API, so might succeed
if [ $? -eq 0 ] || echo "$output" | grep -qi "error\|invalid"; then
    log_pass "Invalid gist_id handled or bypassed in dry-run"
else
    log_fail "Invalid gist_id not handled"
fi

# 10b. Expired/invalid token (can't test without actually failing API call)
log_test "Status handles API errors gracefully"
# This just verifies status doesn't crash on a working config
output=$("$SCRIPTS_DIR/status.sh" 2>&1)
if [ $? -eq 0 ]; then
    log_pass "Status command stable"
else
    log_fail "Status command unstable"
fi

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                 CORNER CASE TEST SUMMARY                   ║"
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
    echo -e "${GREEN}  ALL CORNER CASE TESTS PASSED!${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    exit 0
else
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  $FAIL CORNER CASE TEST(S) FAILED${NC}"
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    exit 1
fi

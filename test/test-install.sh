#!/bin/bash
# test-install.sh - Test plugin installation in clean environment
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_test() { echo -e "${CYAN}[TEST]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "========================================"
echo "  Claude Settings Sync - Install Test"
echo "========================================"
echo ""

# Show initial state
log_test "Initial ~/.claude state:"
ls -la ~/.claude/
echo ""

# Run installation
log_test "Running install script..."
echo ""
curl -fsSL https://raw.githubusercontent.com/AnthonySu/claude-settings-sync/main/install.sh | bash
echo ""

# Verify installation
echo ""
echo "========================================"
echo "  Verification"
echo "========================================"
echo ""

PASS=0
FAIL=0

# Check plugin directory
log_test "Checking plugin directory..."
if [ -d ~/.claude/plugins/marketplaces/claude-settings-sync ]; then
    log_pass "Plugin directory exists"
    else
    log_fail "Plugin directory missing"
    fi

# Check scripts
log_test "Checking scripts..."
for script in push.sh pull.sh status.sh setup.sh restore.sh; do
    if [ -x ~/.claude/plugins/marketplaces/claude-settings-sync/scripts/$script ]; then
        log_pass "  $script (executable)"
            else
        log_fail "  $script missing or not executable"
            fi
done

# Check commands
log_test "Checking command files..."
for cmd in push.md pull.md status.md setup.md restore.md; do
    if [ -f ~/.claude/plugins/marketplaces/claude-settings-sync/commands/$cmd ]; then
        log_pass "  $cmd"
            else
        log_fail "  $cmd missing"
            fi
done

# Check settings.json registration
log_test "Checking settings.json registration..."
if jq -e '.extraKnownMarketplaces["claude-settings-sync"]' ~/.claude/settings.json > /dev/null 2>&1; then
    log_pass "Plugin registered in extraKnownMarketplaces"
    else
    log_fail "Plugin not registered in extraKnownMarketplaces"
    fi

if jq -e '.enabledPlugins["claude-settings-sync@claude-settings-sync"]' ~/.claude/settings.json > /dev/null 2>&1; then
    log_pass "Plugin enabled in enabledPlugins"
    else
    log_fail "Plugin not enabled in enabledPlugins"
    fi

# Show final settings.json
echo ""
log_test "Final settings.json:"
jq '.' ~/.claude/settings.json
echo ""

# Test dry-run of scripts
log_test "Testing status script (should fail - not configured)..."
if ~/.claude/plugins/marketplaces/claude-settings-sync/scripts/status.sh 2>&1 | grep -q "Not configured"; then
    log_pass "Status correctly reports not configured"
    else
    log_fail "Status script unexpected behavior"
    fi

# Summary
echo ""
echo "========================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "========================================"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi

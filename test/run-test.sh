#!/bin/bash
# run-test.sh - Build and run the test container
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building test container..."
docker build -t claude-sync-test .

echo ""
echo "Choose mode:"
echo "  1) Run automated tests (./test-install.sh)"
echo "  2) Interactive shell (explore manually)"
echo ""
read -p "Enter choice [1/2]: " choice

case $choice in
    1)
        echo "Running automated tests..."
        docker run --rm claude-sync-test ./test-install.sh
        ;;
    2)
        echo "Starting interactive shell..."
        echo "Commands to try:"
        echo "  ./test-install.sh           # Run install test"
        echo "  ls ~/.claude/               # Check Claude dir"
        echo "  exit                         # Exit container"
        echo ""
        docker run -it --rm claude-sync-test
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

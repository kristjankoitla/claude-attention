#!/bin/bash
set -e

if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: This tool requires macOS."
    exit 1
fi

echo "Uninstalling Claude Notification..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_LABEL="com.claude.notification"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

# 1. Stop the app
echo "[1/3] Stopping app..."
launchctl bootout gui/$(id -u)/$PLIST_LABEL 2>/dev/null || \
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
pkill -f "$HOME/.claude-notification/bin/claude-notification" 2>/dev/null || true
rm -f "$PLIST_PATH"

# 2. Remove hooks from Claude settings
echo "[2/3] Removing hooks from Claude settings..."
if [ -f "$HOME/.claude-notification/scripts/remove_hooks.py" ]; then
    python3 "$HOME/.claude-notification/scripts/remove_hooks.py"
elif [ -f "$SCRIPT_DIR/scripts/remove_hooks.py" ]; then
    python3 "$SCRIPT_DIR/scripts/remove_hooks.py"
else
    echo "  Warning: remove_hooks.py not found, skipping hook removal"
fi

# 3. Remove installation directory
echo "[3/3] Removing files..."
rm -rf "$HOME/.claude-notification"

echo ""
echo "Claude Notification uninstalled."

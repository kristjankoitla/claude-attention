#!/bin/bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/scripts/preflight.sh"

echo "Installing Claude Notification..."
echo ""

INSTALL_DIR="$HOME/.claude-notification"
BIN_DIR="$INSTALL_DIR/bin"
SESSION_DIR="$INSTALL_DIR/sessions"
HOOKS_DIR="$INSTALL_DIR/hooks"
SCRIPTS_DIR="$INSTALL_DIR/scripts"
PLIST_LABEL="com.claude.notification"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

# 1. Create directories
echo "[1/5] Creating directories..."
mkdir -p "$BIN_DIR" "$HOOKS_DIR" "$SCRIPTS_DIR"
mkdir -p -m 700 "$SESSION_DIR"

# 2. Install hook scripts and Python helpers
echo "[2/5] Installing hook scripts..."
cp "$REPO_DIR/hooks/common.sh" "$HOOKS_DIR/common.sh"
cp "$REPO_DIR/hooks/signal-attention.sh" "$HOOKS_DIR/signal-attention.sh"
cp "$REPO_DIR/hooks/clear-attention.sh" "$HOOKS_DIR/clear-attention.sh"
chmod +x "$HOOKS_DIR/common.sh" "$HOOKS_DIR/signal-attention.sh" "$HOOKS_DIR/clear-attention.sh"
cp "$SCRIPT_DIR/scripts/settings_utils.py" "$SCRIPTS_DIR/settings_utils.py"
cp "$SCRIPT_DIR/scripts/configure_hooks.py" "$SCRIPTS_DIR/configure_hooks.py"
cp "$SCRIPT_DIR/scripts/remove_hooks.py" "$SCRIPTS_DIR/remove_hooks.py"

# 3. Compile Swift app
echo "[3/5] Compiling menu bar app..."
if ! swiftc -O -o "$BIN_DIR/claude-notification" \
    "$REPO_DIR"/sources/*.swift \
    "$REPO_DIR"/sources/controllers/*.swift \
    "$REPO_DIR"/sources/rendering/*.swift \
    "$REPO_DIR"/sources/monitoring/*.swift \
    -framework AppKit \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
    -Xlinker "$SCRIPT_DIR/resources/Info.plist" 2>&1; then
    echo ""
    echo "Error: Swift compilation failed. Check the output above for details."
    exit 1
fi
chmod 700 "$BIN_DIR/claude-notification"
codesign -s - -f "$BIN_DIR/claude-notification" 2>/dev/null || true

# 4. Configure Claude Code hooks
echo "[4/5] Configuring Claude Code hooks..."
mkdir -p "$HOME/.claude"
python3 "$SCRIPT_DIR/scripts/configure_hooks.py"

# 5. Set up LaunchAgent and start
echo "[5/5] Setting up auto-start..."
python3 "$SCRIPT_DIR/scripts/render_template.py" "$SCRIPT_DIR/resources/LaunchAgent.plist" \
    "%%LABEL%%" "$PLIST_LABEL" \
    "%%BINARY_PATH%%" "$BIN_DIR/claude-notification" > "$PLIST_PATH"

launchctl bootout gui/$(id -u)/$PLIST_LABEL 2>/dev/null || \
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
pkill -f "$INSTALL_DIR/bin/claude-notification" 2>/dev/null || true
sleep 0.5
launchctl bootstrap gui/$(id -u) "$PLIST_PATH" 2>/dev/null || \
    launchctl load "$PLIST_PATH"

echo ""
echo "Claude Notification installed successfully!"
echo ""
echo "  A sparkle icon now appears in your menu bar."
echo "  - Idle:      Sparkle icon (no sessions need input)"
echo "  - Attention:  Number inside sparkle (count of sessions waiting)"
echo ""
echo "  The icon updates automatically via Claude Code hooks."
echo "  Starts automatically on login."
echo ""
echo "  To uninstall: ./install/uninstall.sh"

#!/bin/bash
set -eu

if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: This tool requires macOS."
    exit 1
fi

echo "Installing Claude Notification..."
echo ""

# Check for Xcode Command Line Tools (needed for swiftc)
if ! command -v swiftc &>/dev/null; then
    echo "Error: swiftc not found. Install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

# Check for python3 (needed for settings.json manipulation)
if ! command -v python3 &>/dev/null; then
    echo "Error: python3 not found. Install Python 3 or Xcode Command Line Tools."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.claude-notification"
BIN_DIR="$INSTALL_DIR/bin"
SESSION_DIR="$INSTALL_DIR/sessions"
HOOKS_DIR="$INSTALL_DIR/hooks"
SCRIPTS_DIR="$INSTALL_DIR/scripts"
PLIST_LABEL="com.claude.notification"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

# Escape XML special characters for safe plist embedding
xml_escape() {
    printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

# 1. Create directories
echo "[1/5] Creating directories..."
mkdir -p "$BIN_DIR" "$HOOKS_DIR" "$SCRIPTS_DIR"
mkdir -p -m 700 "$SESSION_DIR"

# 2. Install hook scripts and Python helpers
echo "[2/5] Installing hook scripts..."
cp "$SCRIPT_DIR/hooks/signal-attention.sh" "$HOOKS_DIR/signal-attention.sh"
cp "$SCRIPT_DIR/hooks/clear-attention.sh" "$HOOKS_DIR/clear-attention.sh"
chmod +x "$HOOKS_DIR/signal-attention.sh" "$HOOKS_DIR/clear-attention.sh"
cp "$SCRIPT_DIR/scripts/configure_hooks.py" "$SCRIPTS_DIR/configure_hooks.py"
cp "$SCRIPT_DIR/scripts/remove_hooks.py" "$SCRIPTS_DIR/remove_hooks.py"

# 3. Compile Swift app
echo "[3/5] Compiling menu bar app..."

# Create temporary Info.plist to embed in binary
TEMP_PLIST=$(mktemp)
trap 'rm -f "$TEMP_PLIST"' EXIT

cat > "$TEMP_PLIST" << 'INFOPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.claude.notification</string>
    <key>CFBundleName</key>
    <string>Claude Notification</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
INFOPLIST

if ! swiftc -O -o "$BIN_DIR/claude-notification" "$SCRIPT_DIR"/sources/*.swift \
    -framework AppKit \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$TEMP_PLIST" 2>&1; then
    echo ""
    echo "Error: Swift compilation failed. Check the output above for details."
    exit 1
fi

# 4. Configure Claude Code hooks
echo "[4/5] Configuring Claude Code hooks..."
mkdir -p "$HOME/.claude"
python3 "$SCRIPT_DIR/scripts/configure_hooks.py"

# 5. Set up LaunchAgent and start
echo "[5/5] Setting up auto-start..."

ESCAPED_BIN_PATH="$(xml_escape "$BIN_DIR/claude-notification")"
ESCAPED_PLIST_LABEL="$(xml_escape "$PLIST_LABEL")"

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$ESCAPED_PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$ESCAPED_BIN_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF

# Stop existing instance if running
launchctl bootout gui/$(id -u)/$PLIST_LABEL 2>/dev/null || \
    launchctl unload "$PLIST_PATH" 2>/dev/null || true

# Kill any lingering process (match full binary path to avoid false positives)
pkill -f "$INSTALL_DIR/bin/claude-notification" 2>/dev/null || true
sleep 0.5

# Start
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
echo "  To uninstall: ./uninstall.sh"

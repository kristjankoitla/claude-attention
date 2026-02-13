#!/bin/bash
set -e

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
PLIST_LABEL="com.claude.notification"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

# Escape XML special characters for safe plist embedding
xml_escape() {
    printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

# 1. Create directories
echo "[1/5] Creating directories..."
mkdir -p "$BIN_DIR" "$HOOKS_DIR"
mkdir -p -m 700 "$SESSION_DIR"

# 2. Install hook scripts
echo "[2/5] Installing hook scripts..."
cp "$SCRIPT_DIR/hooks/signal-attention.sh" "$HOOKS_DIR/signal-attention.sh"
cp "$SCRIPT_DIR/hooks/clear-attention.sh" "$HOOKS_DIR/clear-attention.sh"
chmod +x "$HOOKS_DIR/signal-attention.sh" "$HOOKS_DIR/clear-attention.sh"

# 3. Compile Swift app
echo "[3/5] Compiling menu bar app..."

# Create temporary Info.plist to embed in binary
TEMP_PLIST=$(mktemp)
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

swiftc -O -o "$BIN_DIR/claude-notification" "$SCRIPT_DIR/ClaudeNotification.swift" \
    -framework AppKit \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$TEMP_PLIST" 2>&1

rm -f "$TEMP_PLIST"

# 4. Configure Claude Code hooks
echo "[4/5] Configuring Claude Code hooks..."
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"

python3 << 'PYEOF'
import json, os, sys

settings_path = os.path.expanduser("~/.claude/settings.json")
settings = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        try:
            settings = json.load(f)
        except json.JSONDecodeError:
            print("  Warning: existing settings.json is invalid, backing up...")
            import shutil
            shutil.copy2(settings_path, settings_path + ".bak")
            settings = {}

hooks = settings.setdefault("hooks", {})
home = os.path.expanduser("~")
signal_cmd = f"{home}/.claude-notification/hooks/signal-attention.sh"
clear_cmd = f"{home}/.claude-notification/hooks/clear-attention.sh"

def hook_exists(event_hooks, command):
    for group in event_hooks:
        for h in group.get("hooks", []):
            if h.get("command", "") == command:
                return True
    return False

def add_hook(event, command):
    event_hooks = hooks.setdefault(event, [])
    if not hook_exists(event_hooks, command):
        event_hooks.append({
            "hooks": [
                {
                    "type": "command",
                    "command": command
                }
            ]
        })

# Signal attention when Claude stops (waiting for input) or needs permission
add_hook("Stop", signal_cmd)
add_hook("PermissionRequest", signal_cmd)

# Clear attention when user submits a prompt or session ends
add_hook("UserPromptSubmit", clear_cmd)
add_hook("SessionEnd", clear_cmd)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("  Hooks configured in ~/.claude/settings.json")
PYEOF

# 5. Set up LaunchAgent and start
echo "[5/5] Setting up auto-start..."

ESCAPED_BIN_PATH="$(xml_escape "$BIN_DIR/claude-notification")"

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
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
rm -f "$INSTALL_DIR/.lock"
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

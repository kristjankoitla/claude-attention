#!/bin/bash
echo "Uninstalling Claude Notification..."

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
python3 << 'PYEOF'
import json, os

settings_path = os.path.expanduser("~/.claude/settings.json")
if not os.path.exists(settings_path):
    exit(0)

with open(settings_path) as f:
    try:
        settings = json.load(f)
    except json.JSONDecodeError:
        exit(0)

hooks = settings.get("hooks", {})
modified = False

for event in list(hooks.keys()):
    original = hooks[event]
    filtered = []
    for group in original:
        clean_hooks = [h for h in group.get("hooks", []) if "claude-notification" not in h.get("command", "")]
        if clean_hooks:
            group["hooks"] = clean_hooks
            filtered.append(group)
    if len(filtered) != len(original):
        modified = True
        if filtered:
            hooks[event] = filtered
        else:
            del hooks[event]

if modified:
    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print("  Hooks removed from ~/.claude/settings.json")
else:
    print("  No hooks to remove")
PYEOF

# 3. Remove installation directory
echo "[3/3] Removing files..."
rm -rf "$HOME/.claude-notification"

echo ""
echo "Claude Notification uninstalled."

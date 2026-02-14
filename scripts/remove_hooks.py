#!/usr/bin/env python3
"""Remove claude-notification hooks from Claude Code settings."""
import json
import os
import sys

settings_path = os.path.expanduser("~/.claude/settings.json")
if not os.path.exists(settings_path):
    sys.exit(0)

with open(settings_path) as f:
    try:
        settings = json.load(f)
    except json.JSONDecodeError:
        sys.exit(0)

hooks = settings.get("hooks", {})
modified = False

for event in list(hooks.keys()):
    original = hooks[event]
    filtered = []
    for group in original:
        clean_hooks = [h for h in group.get("hooks", [])
                       if "claude-notification" not in h.get("command", "")]
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

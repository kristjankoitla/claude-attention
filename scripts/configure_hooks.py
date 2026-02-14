#!/usr/bin/env python3
"""Configure Claude Code hooks for claude-notification."""
import json
import os
import shlex
import shutil
import sys

settings_path = os.path.expanduser("~/.claude/settings.json")
settings = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        try:
            settings = json.load(f)
        except json.JSONDecodeError:
            print("  Warning: existing settings.json is invalid, backing up...")
            shutil.copy2(settings_path, settings_path + ".bak")
            settings = {}

if not isinstance(settings.get("hooks"), dict):
    settings["hooks"] = {}
hooks = settings["hooks"]
home = os.path.expanduser("~")
signal_cmd = shlex.quote(f"{home}/.claude-notification/hooks/signal-attention.sh")
clear_cmd = shlex.quote(f"{home}/.claude-notification/hooks/clear-attention.sh")


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

# Clear attention when user submits a prompt, a tool executes, or session ends
add_hook("UserPromptSubmit", clear_cmd)
add_hook("PostToolUse", clear_cmd)
add_hook("SessionEnd", clear_cmd)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("  Hooks configured in ~/.claude/settings.json")

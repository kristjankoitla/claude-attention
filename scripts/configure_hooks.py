#!/usr/bin/env python3
"""Configure Claude Code hooks for claude-notification."""
import os
import shlex
import sys

sys.path.insert(0, os.path.dirname(__file__))
from settings_utils import load_settings, save_settings


def hook_exists(event_hooks, command):
    """Check whether a hook with the given command is already registered."""
    return any(
        h.get("command") == command
        for group in event_hooks
        for h in group.get("hooks", [])
    )


def add_hook(hooks, event, command):
    """Append a new hook entry for an event, skipping if already present."""
    event_hooks = hooks.setdefault(event, [])
    if not hook_exists(event_hooks, command):
        event_hooks.append({
            "hooks": [{
                "type": "command",
                "command": command,
            }]
        })


def main():
    settings = load_settings()

    if not isinstance(settings.get("hooks"), dict):
        settings["hooks"] = {}

    hooks = settings["hooks"]
    home = os.path.expanduser("~")
    signal_cmd = shlex.quote(f"{home}/.claude-notification/hooks/signal-attention.sh")
    clear_cmd = shlex.quote(f"{home}/.claude-notification/hooks/clear-attention.sh")

    add_hook(hooks, "Stop", signal_cmd)
    add_hook(hooks, "PermissionRequest", signal_cmd)
    add_hook(hooks, "UserPromptSubmit", clear_cmd)
    add_hook(hooks, "PostToolUse", clear_cmd)
    add_hook(hooks, "SessionEnd", clear_cmd)

    save_settings(settings)
    print("  Hooks configured in ~/.claude/settings.json")


if __name__ == "__main__":
    main()

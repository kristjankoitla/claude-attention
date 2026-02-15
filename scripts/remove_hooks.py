#!/usr/bin/env python3
"""Remove claude-notification hooks from Claude Code settings."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from settings_utils import load_settings, save_settings, SETTINGS_PATH


def remove_matching_hooks(hooks):
    """Strip all hooks whose command contains 'claude-notification'. Returns True if any were removed."""
    modified = False
    for event in list(hooks):
        original = hooks[event]
        filtered = []
        for group in original:
            kept = [h for h in group.get("hooks", [])
                    if "claude-notification" not in h.get("command", "")]
            if kept:
                filtered.append({**group, "hooks": kept})
        if len(filtered) != len(original):
            modified = True
            if filtered:
                hooks[event] = filtered
            else:
                del hooks[event]
    return modified


def main():
    if not os.path.exists(SETTINGS_PATH):
        return

    settings = load_settings()
    if not settings:
        print("  No hooks to remove")
        return

    hooks = settings.get("hooks", {})
    if remove_matching_hooks(hooks):
        save_settings(settings)
        print("  Hooks removed from ~/.claude/settings.json")
    else:
        print("  No hooks to remove")


if __name__ == "__main__":
    main()

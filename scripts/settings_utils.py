"""Shared utilities for loading and saving Claude Code settings.json."""
import json
import os
import shutil

SETTINGS_PATH = os.path.expanduser("~/.claude/settings.json")


def load_settings():
    """Load settings.json, returning an empty dict if missing or invalid."""
    if not os.path.exists(SETTINGS_PATH):
        return {}
    with open(SETTINGS_PATH) as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            print("  Warning: existing settings.json is invalid, backing up...")
            shutil.copy2(SETTINGS_PATH, SETTINGS_PATH + ".bak")
            return {}


def save_settings(settings):
    """Write settings dict to settings.json with consistent formatting."""
    with open(SETTINGS_PATH, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")

"""Shared utilities for loading and saving Claude Code settings.json."""
import json
import os
import shutil
import tempfile

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
    """Write settings dict to settings.json atomically."""
    settings_dir = os.path.dirname(SETTINGS_PATH)
    fd, tmp_path = tempfile.mkstemp(dir=settings_dir, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(settings, f, indent=2)
            f.write("\n")
        os.rename(tmp_path, SETTINGS_PATH)
    except BaseException:
        os.unlink(tmp_path)
        raise

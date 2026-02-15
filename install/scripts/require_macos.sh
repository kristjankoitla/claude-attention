#!/bin/bash
# Guard: exit if not running on macOS.
# Sourced by install.sh and uninstall.sh.

if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: This tool requires macOS."
    exit 1
fi

#!/bin/bash
# Pre-install validation for claude-notification.
# Sourced by install.sh — exits on failure.

if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: This tool requires macOS."
    exit 1
fi

if ! command -v swiftc &>/dev/null; then
    echo "Error: swiftc not found. Install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo "Error: python3 not found. Install Python 3 or Xcode Command Line Tools."
    exit 1
fi

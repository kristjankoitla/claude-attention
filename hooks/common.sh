#!/bin/bash
# Shared preamble for claude-notification hook scripts.
# Sets up session directory, reads stdin, and extracts/sanitizes the session ID.
umask 077
SESSION_DIR="$HOME/.claude-notification/sessions"
install -d -m 700 "$HOME/.claude-notification" "$SESSION_DIR"
INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | tr '\n' ' ' | sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p')
# Sanitize: only allow safe filename characters to prevent path traversal
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')

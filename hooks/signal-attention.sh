#!/bin/bash
# Called by Claude Code hooks (Stop, PermissionRequest) to signal that a session needs attention.
# Reads JSON from stdin to extract session_id, creates a session file with PID and timestamp.
umask 077
SESSION_DIR="$HOME/.claude-notification/sessions"
install -d -m 700 "$HOME/.claude-notification" "$SESSION_DIR"
INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | tr '\n' ' ' | sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p')
# Sanitize: only allow safe filename characters to prevent path traversal
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')
[ -n "$SESSION_ID" ] && echo "$PPID:$(date +%s)" > "$SESSION_DIR/$SESSION_ID"
exit 0

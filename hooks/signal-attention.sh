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

# Find the Claude Code (node) process by walking up the process tree.
# $PPID may be a short-lived intermediary shell that exits immediately,
# so we search ancestors for a "node" process which is the actual Claude Code runtime.
find_claude_pid() {
    local pid=$PPID
    local max_depth=10
    while [ "$max_depth" -gt 0 ] && [ "$pid" -gt 1 ]; do
        local comm
        comm=$(ps -p "$pid" -o comm= 2>/dev/null) || break
        case "$comm" in
            *node*) echo "$pid"; return ;;
        esac
        pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ') || break
        max_depth=$((max_depth - 1))
    done
    # Fallback: use PPID even if we couldn't find a node process
    echo "$PPID"
}

if [ -n "$SESSION_ID" ]; then
    CLAUDE_PID=$(find_claude_pid)
    TMPFILE=$(mktemp "$SESSION_DIR/.tmp.XXXXXX")
    echo "$CLAUDE_PID:$(date +%s)" > "$TMPFILE"
    mv -f "$TMPFILE" "$SESSION_DIR/$SESSION_ID"
fi
exit 0

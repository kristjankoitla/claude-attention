#!/bin/bash
# Called by Claude Code hooks (Stop, PermissionRequest) to signal that a session needs attention.
# Reads JSON from stdin to extract session_id, creates a session file with PID and timestamp.
source "$(dirname "$0")/common.sh"

# Get the parent PID of a given process.
get_parent_pid() {
    ps -p "$1" -o ppid= 2>/dev/null | tr -d ' '
}

# Check whether a process's command name contains "node".
is_node_process() {
    case "$(ps -p "$1" -o comm= 2>/dev/null)" in
        *node*) return 0 ;;
    esac
    return 1
}

# Find the Claude Code (node) process by walking up the process tree.
# $PPID may be a short-lived intermediary shell, so we search ancestors
# for a "node" process which is the actual Claude Code runtime.
find_claude_pid() {
    local pid=$PPID
    local depth=10
    while [ "$depth" -gt 0 ] && [ "$pid" -gt 1 ]; do
        if is_node_process "$pid"; then
            echo "$pid"
            return
        fi
        pid=$(get_parent_pid "$pid") || break
        depth=$((depth - 1))
    done
    echo "$PPID"
}

if [ -n "$SESSION_ID" ]; then
    CLAUDE_PID=$(find_claude_pid)
    TMPFILE=$(mktemp "$SESSION_DIR/.tmp.XXXXXX")
    echo "$CLAUDE_PID:$(date +%s)" > "$TMPFILE"
    mv -f "$TMPFILE" "$SESSION_DIR/$SESSION_ID"
fi
exit 0

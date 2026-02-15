#!/bin/bash
# Called by Claude Code hooks (UserPromptSubmit, SessionEnd) to clear the attention signal.
# Reads JSON from stdin to extract session_id, removes the corresponding session file.
source "$(dirname "$0")/common.sh" || { echo "Error: common.sh not found" >&2; exit 1; }
[ -n "$SESSION_ID" ] && rm -f "$SESSION_DIR/$SESSION_ID"
exit 0

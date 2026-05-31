#!/usr/bin/env bash
# Helpers used only by the session-name hooks. Source this; do not execute.
# The shared session-file scan lives in ../lib.sh; this file holds the
# session-name-specific bits (title emit + ai-title extraction).

# Emit a hookSpecificOutput.sessionTitle JSON object for the given hook event.
# Usage: emit_session_title <hookEventName> <title>
emit_session_title() {
  jq -nc --arg e "$1" --arg t "$2" \
    '{hookSpecificOutput:{hookEventName:$e,sessionTitle:$t}}'
}

# Print the newest auto-generated ai-title from a transcript JSONL, or nothing.
# The transcript holds lines like {"type":"ai-title","aiTitle":"..."}; ai-title
# is generated only after the first assistant response, so this is empty early.
latest_ai_title() {
  local transcript="$1"
  [ -n "$transcript" ] && [ -f "$transcript" ] || return 0
  grep -a '"type":"ai-title"' "$transcript" 2>/dev/null \
    | tail -n1 | jq -r '.aiTitle // empty' 2>/dev/null
}

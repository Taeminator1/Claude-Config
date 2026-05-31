#!/usr/bin/env bash
# Shared helpers for the session-name and notify hooks. Source this; do not execute.
# Centralizes the session-file scan and the sessionTitle JSON emit so the
# correctness-sensitive logic (per-file scanning) lives in exactly one place.

# Print the path of the ~/.claude/sessions/*.json file whose .sessionId matches
# the argument, or nothing if none matches. Scans one file at a time on purpose:
# a single malformed JSON aborts a multi-file jq invocation before later files
# are read, which would miss the match -- per-file is robust to that.
find_session_file() {
  local session_id="$1" f sid
  for f in "$HOME"/.claude/sessions/*.json; do
    [ -e "$f" ] || continue
    sid="$(jq -r '.sessionId // empty' "$f" 2>/dev/null)"
    if [ "$sid" = "$session_id" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 0
}

# Print the .name of the session matching the given id, or nothing.
resolve_session_name() {
  local f
  f="$(find_session_file "$1")"
  [ -n "$f" ] || return 0
  jq -r '.name // empty' "$f" 2>/dev/null
}

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

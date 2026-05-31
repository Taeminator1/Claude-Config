#!/usr/bin/env bash
# SessionStart hook. If this session already has a `.name`, emit it as
# `sessionTitle` so the live prompt-bar box shows it on start/resume.
# Box display relies on hookSpecificOutput.sessionTitle (Claude Code >= 2.1.157).
set -uo pipefail

trap 'exit 0' EXIT

PAYLOAD="$(cat)"
SESSION_ID="$(jq -r '.session_id // empty' <<<"$PAYLOAD" 2>/dev/null)"
[ -z "$SESSION_ID" ] && exit 0

SESSION_NAME="$(jq -r --arg sid "$SESSION_ID" \
  'select(.sessionId==$sid) | .name // empty' \
  "$HOME"/.claude/sessions/*.json 2>/dev/null | head -n1)"
[ -z "$SESSION_NAME" ] && exit 0

jq -nc --arg t "$SESSION_NAME" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",sessionTitle:$t}}'

exit 0

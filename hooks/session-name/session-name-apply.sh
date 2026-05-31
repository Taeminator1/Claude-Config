#!/usr/bin/env bash
# SessionStart hook. If this session already has a `.name`, emit it as
# `sessionTitle` so the live prompt-bar box shows it on start/resume.
# Box display relies on hookSpecificOutput.sessionTitle (Claude Code >= 2.1.157).
set -uo pipefail

trap 'exit 0' EXIT

PAYLOAD="$(cat)"
SESSION_ID="$(jq -r '.session_id // empty' <<<"$PAYLOAD" 2>/dev/null)"
[ -z "$SESSION_ID" ] && exit 0

SOURCE="$(jq -r '.source // empty' <<<"$PAYLOAD" 2>/dev/null)"

# After /clear the conversation is fresh and we want the naming prompt to
# re-fire. Deleting `.name` from the session JSON does NOT work: the title is
# owned by Claude Code (persisted as a `custom-title` line in the transcript,
# which survives /clear) and CC rebuilds `.name` from it on reload. Instead drop
# a re-nudge flag that the UserPromptSubmit hook checks, so it forces the prompt
# once on the next message regardless of the existing name.
if [ "$SOURCE" = "clear" ]; then
  FLAG_DIR="$HOME/.claude/.session-renudge"
  mkdir -p "$FLAG_DIR" 2>/dev/null || exit 0
  : > "$FLAG_DIR/$SESSION_ID" 2>/dev/null || true
  exit 0
fi

SESSION_NAME="$(jq -r --arg sid "$SESSION_ID" \
  'select(.sessionId==$sid) | .name // empty' \
  "$HOME"/.claude/sessions/*.json 2>/dev/null | head -n1)"
[ -z "$SESSION_NAME" ] && exit 0

jq -nc --arg t "$SESSION_NAME" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",sessionTitle:$t}}'

exit 0

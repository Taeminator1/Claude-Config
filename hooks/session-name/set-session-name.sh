#!/usr/bin/env bash
# Set a human-readable name on a Claude Code session metadata file.
# Usage: set-session-name.sh <session_id> <name>
# Finds ~/.claude/sessions/<pid>.json whose .sessionId == <session_id> and writes .name.
set -uo pipefail

SESSION_ID="${1:-}"
NAME="${2:-}"

if [ -z "$SESSION_ID" ] || [ -z "$NAME" ]; then
  echo "usage: set-session-name.sh <session_id> <name>" >&2
  exit 1
fi

TARGET=""
for f in "$HOME"/.claude/sessions/*.json; do
  [ -e "$f" ] || continue
  sid="$(jq -r '.sessionId // empty' "$f" 2>/dev/null)"
  if [ "$sid" = "$SESSION_ID" ]; then
    TARGET="$f"
    break
  fi
done

if [ -z "$TARGET" ]; then
  echo "no session file found for session_id=$SESSION_ID (name not set)"
  exit 0
fi

TMP="$(mktemp "${TARGET}.XXXXXX")" || { echo "mktemp failed" >&2; exit 1; }
if jq --arg n "$NAME" '.name=$n' "$TARGET" >"$TMP" 2>/dev/null; then
  mv "$TMP" "$TARGET"
  echo "session name set: $NAME  ($TARGET)"
else
  rm -f "$TMP"
  echo "failed to write name" >&2
  exit 1
fi

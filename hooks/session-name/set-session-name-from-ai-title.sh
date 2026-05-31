#!/usr/bin/env bash
# Set a session's `.name` from the latest auto-generated ai-title in its transcript.
# Usage: set-session-name-from-ai-title.sh <session_id> <transcript_path>
# The transcript JSONL holds lines like {"type":"ai-title","aiTitle":"..."}; the
# newest one is used. Falls back with a message if none exists yet.
set -uo pipefail

source "$(dirname "$0")/lib.sh"

SESSION_ID="${1:-}"
TRANSCRIPT_PATH="${2:-}"

if [ -z "$SESSION_ID" ]; then
  echo "usage: set-session-name-from-ai-title.sh <session_id> <transcript_path>" >&2
  exit 1
fi

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo "no transcript found (ai-title unavailable); pick a name manually"
  exit 0
fi

AI_TITLE="$(latest_ai_title "$TRANSCRIPT_PATH")"

if [ -z "$AI_TITLE" ]; then
  echo "no ai-title generated yet; pick a name manually"
  exit 0
fi

exec bash "$(dirname "$0")/set-session-name.sh" "$SESSION_ID" "$AI_TITLE"

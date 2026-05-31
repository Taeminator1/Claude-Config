#!/usr/bin/env bash
# Stop hook. Silently names an unnamed session from its auto-generated ai-title.
# ai-title is only generated after the first assistant response, so the Stop
# event (fires after each response) is the earliest reliable point to apply it.
# This replaces the old "ask the user via choices" flow: naming now happens with
# no user interaction whenever an ai-title exists. The UserPromptSubmit nudge only
# falls back to asking when an ai-title never materializes across a full turn.
set -uo pipefail

source "$(dirname "$0")/../lib.sh"
source "$(dirname "$0")/lib.sh"

# Always exit 0 so we never block the Stop event.
trap 'exit 0' EXIT

PAYLOAD="$(cat)"
SESSION_ID="$(jq -r '.session_id // empty' <<<"$PAYLOAD" 2>/dev/null)"
[ -z "$SESSION_ID" ] && exit 0

TRANSCRIPT_PATH="$(jq -r '.transcript_path // empty' <<<"$PAYLOAD" 2>/dev/null)"

NUDGED_FILE="$HOME/.claude/.session-nudged/$SESSION_ID"
GRACE_FILE="$HOME/.claude/.session-grace/$SESSION_ID"

# Naming already finalized this session (auto-applied, or the user answered /
# declined the prompt) -> nothing to do.
if [ -f "$NUDGED_FILE" ]; then
  exit 0
fi

# Already named -> record that naming is settled, stop firing. (After /clear the
# UserPromptSubmit hook asks synchronously on the first prompt and records the
# name there, so by this point the session is named or already nudged.)
if [ -n "$(resolve_session_name "$SESSION_ID")" ]; then
  mkdir -p "$HOME/.claude/.session-nudged" 2>/dev/null || true
  : > "$NUDGED_FILE" 2>/dev/null || true
  exit 0
fi

AI_TITLE="$(latest_ai_title "$TRANSCRIPT_PATH")"

# No ai-title yet -> leave everything as-is; a later Stop will retry.
[ -z "$AI_TITLE" ] && exit 0

bash "$(dirname "$0")/set-session-name.sh" "$SESSION_ID" "$AI_TITLE" >/dev/null 2>&1

# Naming done. Stamp the marker so neither this hook nor the nudge re-acts, and
# clear the grace marker.
mkdir -p "$HOME/.claude/.session-nudged" 2>/dev/null || true
: > "$NUDGED_FILE" 2>/dev/null || true
rm -f "$GRACE_FILE" 2>/dev/null || true

exit 0

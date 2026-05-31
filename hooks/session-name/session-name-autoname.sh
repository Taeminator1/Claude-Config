#!/usr/bin/env bash
# Stop hook. Silently names an unnamed session from its auto-generated ai-title.
# ai-title is only generated after the first assistant response, so the Stop
# event (fires after each response) is the earliest reliable point to apply it.
# This replaces the old "ask the user via choices" flow: naming now happens with
# no user interaction whenever an ai-title exists. The UserPromptSubmit nudge only
# falls back to asking when an ai-title never materializes across a full turn.
set -uo pipefail

source "$(dirname "$0")/../lib.sh"

# Always exit 0 so we never block the Stop event.
trap 'exit 0' EXIT

PAYLOAD="$(cat)"
SESSION_ID="$(jq -r '.session_id // empty' <<<"$PAYLOAD" 2>/dev/null)"
[ -z "$SESSION_ID" ] && exit 0

TRANSCRIPT_PATH="$(jq -r '.transcript_path // empty' <<<"$PAYLOAD" 2>/dev/null)"

NUDGED_FILE="$HOME/.claude/.session-nudged/$SESSION_ID"
RENUDGE_FILE="$HOME/.claude/.session-renudge/$SESSION_ID"

# A pending /clear re-nudge forces re-naming even though the old .name persists
# (Claude Code rebuilds it from the transcript's custom-title across /clear).
RENUDGE=0
[ -f "$RENUDGE_FILE" ] && RENUDGE=1

# Naming already finalized this session (auto-applied, or user answered/declined
# the fallback) -> nothing to do, unless a /clear re-nudge is pending.
if [ "$RENUDGE" -eq 0 ] && [ -f "$NUDGED_FILE" ]; then
  exit 0
fi

# Already named and not re-nudging -> record that naming is settled, stop firing.
if [ "$RENUDGE" -eq 0 ] && [ -n "$(resolve_session_name "$SESSION_ID")" ]; then
  mkdir -p "$HOME/.claude/.session-nudged" 2>/dev/null || true
  : > "$NUDGED_FILE" 2>/dev/null || true
  exit 0
fi

AI_TITLE="$(latest_ai_title "$TRANSCRIPT_PATH")"

# No ai-title yet -> leave everything as-is; a later Stop will retry.
[ -z "$AI_TITLE" ] && exit 0

bash "$(dirname "$0")/set-session-name.sh" "$SESSION_ID" "$AI_TITLE" >/dev/null 2>&1

# Naming done. Stamp the marker so neither this hook nor the nudge re-acts, and
# consume the /clear re-nudge flag so it fires only once.
mkdir -p "$HOME/.claude/.session-nudged" 2>/dev/null || true
: > "$NUDGED_FILE" 2>/dev/null || true
rm -f "$RENUDGE_FILE" 2>/dev/null || true

exit 0

#!/usr/bin/env bash
# UserPromptSubmit hook. Jobs, by session state:
#   1. Session has a `.name` -> emit it as `sessionTitle` so the live prompt-bar
#      box shows it (and keeps showing it, overriding the auto-titler).
#   2. Session unnamed, ai-title already exists -> apply it silently (covers
#      resume / pre-existing ai-title before any Stop hook fires this session).
#   3. Session unnamed, no ai-title yet -> wait one turn (the Stop hook names it
#      after the response). Only if an ai-title still never appears do we fall
#      back to ASKING the user via AskUserQuestion choices.
# Auto-naming itself happens in session-name-autoname.sh (Stop hook); this hook
# is the live-box display plus the no-ai-title fallback.
# Box display relies on hookSpecificOutput.sessionTitle (Claude Code >= 2.1.157).
set -uo pipefail

source "$(dirname "$0")/../lib.sh"
source "$(dirname "$0")/lib.sh"

# Always exit 0 so we never block the prompt.
trap 'exit 0' EXIT

PAYLOAD="$(cat)"
SESSION_ID="$(jq -r '.session_id // empty' <<<"$PAYLOAD" 2>/dev/null)"
[ -z "$SESSION_ID" ] && exit 0

TRANSCRIPT_PATH="$(jq -r '.transcript_path // empty' <<<"$PAYLOAD" 2>/dev/null)"

SESSION_NAME="$(resolve_session_name "$SESSION_ID")"

NUDGED_FILE="$HOME/.claude/.session-nudged/$SESSION_ID"
GRACE_FILE="$HOME/.claude/.session-grace/$SESSION_ID"
RENUDGE_FILE="$HOME/.claude/.session-renudge/$SESSION_ID"
CLEARBASE_FILE="$HOME/.claude/.session-clearbase/$SESSION_ID"

# A re-nudge flag is dropped by the SessionStart hook on /clear: the session
# still carries the old name (CC rebuilds it from the transcript), so while the
# flag is pending we treat the session as unnamed and re-derive its name.
RENUDGE=0
[ -f "$RENUDGE_FILE" ] && RENUDGE=1

# On the first prompt after /clear, capture how many ai-title lines already
# exist. Those are STALE (pre-clear); only a count above this baseline is a new
# post-clear title. Without it we'd re-pin the old name from the leftover title.
if [ "$RENUDGE" -eq 1 ] && [ ! -f "$CLEARBASE_FILE" ]; then
  mkdir -p "$HOME/.claude/.session-clearbase" 2>/dev/null || true
  count_ai_titles "$TRANSCRIPT_PATH" > "$CLEARBASE_FILE" 2>/dev/null || true
fi
BASE=0
[ -f "$CLEARBASE_FILE" ] && BASE="$(cat "$CLEARBASE_FILE" 2>/dev/null || echo 0)"

# Named (and not re-nudging) -> show it in the live box every prompt.
if [ "$RENUDGE" -eq 0 ] && [ -n "$SESSION_NAME" ]; then
  emit_session_title UserPromptSubmit "$SESSION_NAME"
  exit 0
fi

# Naming already finalized (auto-applied by the Stop hook, or user answered /
# declined the fallback) -> don't re-act.
if [ "$RENUDGE" -eq 0 ] && [ -f "$NUDGED_FILE" ]; then
  exit 0
fi

# A fresh ai-title (count above the /clear baseline) -> apply now and show it.
# Covers resume, or a title generated before any Stop hook fired this run.
AI_TITLE=""
if [ "$(count_ai_titles "$TRANSCRIPT_PATH")" -gt "$BASE" ]; then
  AI_TITLE="$(latest_ai_title "$TRANSCRIPT_PATH")"
fi
if [ -n "$AI_TITLE" ]; then
  bash "$(dirname "$0")/set-session-name.sh" "$SESSION_ID" "$AI_TITLE" >/dev/null 2>&1
  mkdir -p "$HOME/.claude/.session-nudged" 2>/dev/null || true
  : > "$NUDGED_FILE" 2>/dev/null || true
  rm -f "$RENUDGE_FILE" "$CLEARBASE_FILE" "$GRACE_FILE" 2>/dev/null || true
  emit_session_title UserPromptSubmit "$AI_TITLE"
  exit 0
fi

# No fresh ai-title yet. Give it a grace turn: the Stop hook after this response
# names the session silently. Only on a *later* prompt that STILL has no fresh
# ai-title do we fall back to asking the user.
if [ ! -f "$GRACE_FILE" ]; then
  mkdir -p "$HOME/.claude/.session-grace" 2>/dev/null || true
  : > "$GRACE_FILE" 2>/dev/null || true
  exit 0
fi

# Fallback: an ai-title never materialized across a full turn (fresh session or
# post-/clear). Ask the user to pick a name. Stamp nudged so we ask only once,
# and consume the /clear flag/baseline.
mkdir -p "$HOME/.claude/.session-nudged" 2>/dev/null || true
: > "$NUDGED_FILE" 2>/dev/null || true
rm -f "$RENUDGE_FILE" "$CLEARBASE_FILE" 2>/dev/null || true

CONTEXT="이 세션은 아직 이름(.name)이 없고 자동 제목(ai-title)도 생성되지 않았습니다. 사용자의 이번 요청에 대한 답변을 만들기 전에, 먼저 AskUserQuestion 도구로 이 세션의 이름을 짧게 무엇으로 할지 사용자에게 존댓말로 물어보세요. 선택지는 다음 순서로 구성하세요: 사용자의 이번 요청 내용을 기반으로 추천 세션 이름 1~2개를 먼저 제시하고, 마지막 선택지로 '아무 작업도 하지 않기'를 넣으세요. 사용자가 추천 이름이나 직접 입력한 이름을 주면 다음을 실행해 기록하세요: bash ~/.claude/hooks/session-name/set-session-name.sh ${SESSION_ID} \"<이름>\". (session_id=${SESSION_ID}) 사용자가 '아무 작업도 하지 않기'를 선택하면 이름을 기록하지 말고 곧바로 원래 요청을 처리하세요. 둘 중 하나를 처리한 뒤 원래 요청을 처리하세요."

jq -nc --arg ctx "$CONTEXT" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'

exit 0

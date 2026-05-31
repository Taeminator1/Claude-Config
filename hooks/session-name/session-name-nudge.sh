#!/usr/bin/env bash
# UserPromptSubmit hook. Two jobs, mutually exclusive by session state:
#   1. Session already has a `.name` -> emit it as `sessionTitle` so the live
#      prompt-bar box shows it (and keeps showing it, overriding the auto-titler).
#   2. Session has no `.name` -> inject context asking Claude to nudge the
#      user to name the session.
# Box display relies on hookSpecificOutput.sessionTitle (Claude Code >= 2.1.157).
set -uo pipefail

# Always exit 0 so we never block the prompt.
trap 'exit 0' EXIT

PAYLOAD="$(cat)"
SESSION_ID="$(jq -r '.session_id // empty' <<<"$PAYLOAD" 2>/dev/null)"
[ -z "$SESSION_ID" ] && exit 0

TRANSCRIPT_PATH="$(jq -r '.transcript_path // empty' <<<"$PAYLOAD" 2>/dev/null)"

SESSION_NAME="$(jq -r --arg sid "$SESSION_ID" \
  'select(.sessionId==$sid) | .name // empty' \
  "$HOME"/.claude/sessions/*.json 2>/dev/null | head -n1)"

# A re-nudge flag is dropped by the SessionStart hook on /clear. Honor it BEFORE
# the named branch: after /clear the session usually still carries the old name
# (CC restores it from the transcript), so without this we'd just re-show the old
# title and never re-prompt. Consume the flag so it only fires once.
FLAG_FILE="$HOME/.claude/.session-renudge/$SESSION_ID"
RENUDGE=0
if [ -f "$FLAG_FILE" ]; then
  rm -f "$FLAG_FILE" 2>/dev/null || true
  RENUDGE=1
fi

# Named (and not a pending re-nudge) -> show it in the live box every prompt.
if [ "$RENUDGE" -eq 0 ] && [ -n "$SESSION_NAME" ]; then
  jq -nc --arg t "$SESSION_NAME" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",sessionTitle:$t}}'
  exit 0
fi

if [ "$RENUDGE" -eq 1 ]; then
  LEAD="방금 /clear로 대화가 초기화되었습니다. 이전 세션 이름이 그대로 남아 있을 수 있으니, 이번 대화에 맞는 이름을 새로 정합니다."
else
  LEAD="이 세션은 아직 이름(.name)이 없습니다."
fi

CONTEXT="${LEAD} 사용자의 이번 요청에 대한 답변을 만들기 전에, 먼저 AskUserQuestion 도구로 이 세션의 이름을 짧게 무엇으로 할지 사용자에게 존댓말로 물어보세요. 선택지는 다음 순서로 구성하세요: 1번 선택지는 '현재 적용된 타이틀을 그대로 사용합니다.'로 넣고, 그다음 사용자의 이번 요청 내용을 기반으로 추천 세션 이름 1~2개를 제시하고, 마지막 선택지로 '이름 짓지 않기'를 넣으세요. 사용자가 1번을 선택하면 다음을 실행해 자동 생성된 제목을 이름으로 기록하세요: bash ~/.claude/hooks/session-name/set-session-name-from-ai-title.sh ${SESSION_ID} \"${TRANSCRIPT_PATH}\". 사용자가 추천 이름이나 직접 입력한 이름을 주면 다음을 실행해 기록하세요: bash ~/.claude/hooks/session-name/set-session-name.sh ${SESSION_ID} \"<이름>\". (session_id=${SESSION_ID}) 사용자가 '이름 짓지 않기'를 선택하면 이름을 기록하지 말고 곧바로 원래 요청을 처리하세요. 셋 중 하나를 처리한 뒤 원래 요청을 처리하세요."

jq -nc --arg ctx "$CONTEXT" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'

exit 0

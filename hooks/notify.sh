#!/usr/bin/env bash
set -uo pipefail

[ "${CLAUDE_NOTIFY_DISABLE:-}" = 1 ] && exit 0

PAYLOAD="$(cat)"
EVENT="$(jq -r '.hook_event_name // empty' <<<"$PAYLOAD")"
CWD="$(jq -r '.cwd // empty' <<<"$PAYLOAD")"
PROJECT="$(basename "${CWD:-unknown}")"
SESSION_ID="$(jq -r '.session_id // empty' <<<"$PAYLOAD")"
SESSION_NAME=""
if [ -n "$SESSION_ID" ]; then
  SESSION_NAME="$(jq -r --arg sid "$SESSION_ID" \
    'select(.sessionId==$sid) | .name // empty' \
    "$HOME"/.claude/sessions/*.json 2>/dev/null | head -n1)"
fi
ALERTER="/opt/homebrew/bin/alerter"
SUMMARY_MAX_LEN="${CLAUDE_NOTIFY_SUMMARY_MAX:-80}"
MSG_MAX_LEN="${CLAUDE_NOTIFY_MSG_MAX:-200}"

# Extract text from transcript JSONL.
# mode=first (Stop): last assistant message text; fallback = first non-empty line.
# mode=last (Notification): latest AskUserQuestion question text; fallback = last non-empty line.
# Output: LAST_TEXT\x1fFALLBACK
_extract_last_assistant_text() {
  local transcript="$1" mode="${2:-first}"
  python3 - "$transcript" "$mode" 2>/dev/null <<'PYEOF'
import json, re, sys

def strip_md(line):
    line = line.strip()
    if not line:
        return ""
    line = re.sub(r'^#{1,6}\s*', '', line)
    line = re.sub(r'\*{1,2}([^*]+)\*{1,2}', r'\1', line)
    line = re.sub(r'`[^`]+`', lambda m: m.group()[1:-1], line)
    line = re.sub(r'^[-*+]\s+', '', line)
    line = re.sub(r'^\d+\.\s+', '', line)
    line = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'\1', line)
    return line.strip()

def first_line(text):
    for line in text.splitlines():
        line = strip_md(line)
        if len(line) >= 5:
            return line[:80] + ('…' if len(line) > 80 else '')
    return ""

def last_line(text):
    for line in reversed(text.splitlines()):
        line = strip_md(line)
        if len(line) >= 5:
            return line[:80] + ('…' if len(line) > 80 else '')
    return ""

mode = sys.argv[2] if len(sys.argv) > 2 else "first"
assistants = []
try:
    with open(sys.argv[1]) as f:
        for line in f:
            try:
                d = json.loads(line)
                if d.get("type") == "assistant":
                    assistants.append(d)
            except Exception:
                pass
except Exception:
    pass

last_text = ""
if mode == "last":
    # Notification: 전체 기록을 역순으로 훑어 가장 최근 AskUserQuestion 질문 추출
    for record in reversed(assistants):
        for c in reversed(record.get("message", {}).get("content", [])):
            if isinstance(c, dict) and c.get("type") == "tool_use" and c.get("name") == "AskUserQuestion":
                questions = c.get("input", {}).get("questions", [])
                qs = [q.get("question", "").strip() for q in questions if q.get("question", "").strip()]
                if qs:
                    last_text = " / ".join(qs)
                break
        if last_text:
            break
else:
    # Stop: 텍스트 블록이 있는 가장 최근 assistant 레코드 추출
    for record in reversed(assistants):
        text_block = ""
        for c in record.get("message", {}).get("content", []):
            if isinstance(c, dict) and c.get("type") == "text":
                t = c.get("text", "").strip()
                if t:
                    text_block = t
        if text_block:
            last_text = text_block
            break

fallback = (last_line if mode == "last" else first_line)(last_text) if last_text else ""
sys.stdout.write(last_text + "\x1f" + fallback)
PYEOF
}

# Call Claude for a one-line summary.
_summarize_with_claude() {
  local text="$1" sys_prompt="$2" timeout_secs="${3:-30}"
  local summary
  summary="$(
    CLAUDE_NOTIFY_DISABLE=1 \
    printf '%s' "$text" \
    | perl -e 'alarm shift; exec @ARGV' "$timeout_secs" \
        claude -p \
          --model "${CLAUDE_NOTIFY_MODEL:-haiku}" \
          --no-session-persistence \
          --disable-slash-commands \
          --tools "" \
          --setting-sources "" \
          --system-prompt "$sys_prompt" \
          2>/dev/null \
    | tr -d '\r' \
    | awk 'NF{print; exit}'
  )"
  printf '%s' "${summary:0:$SUMMARY_MAX_LEN}"
}

_SYS_COMMON="당신은 요약기입니다. ${SUMMARY_MAX_LEN}자 이하, 마크다운/따옴표/이모지 사용 금지, 출력은 요약 문장 한 줄만. 입력으로 받은 텍스트를 한국어 한 줄로 요약하세요."

case "$EVENT" in
  PreToolUse)
    TOOL_NAME="$(jq -r '.tool_name // empty' <<<"$PAYLOAD")"
    [ "$TOOL_NAME" != "ExitPlanMode" ] && exit 0

    MSG="실행 승인이 필요합니다"
    GROUP_ID="$SESSION_ID"
    TITLE="[$PROJECT] ${SESSION_NAME:-undefined}"
    if [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ]; then
      ICON="$HOME/.claude/hooks/assets/claude-question-dark.webp"
    else
      ICON="$HOME/.claude/hooks/assets/claude-question-light.webp"
    fi
    ;;
  Notification)
    RAW_MSG="$(jq -r '.message // "입력이 필요합니다"' <<<"$PAYLOAD")"
    case "$RAW_MSG" in
      *"waiting for your input"*|*"입력을 기다리"*) exit 0 ;;
      *"needs your attention"*|*"주의가 필요"*)
        RAW_MSG="확인이 필요합니다" ;;
    esac

    MSG=""
    case "$RAW_MSG" in
      *permission*|*Permission*|*권한*)
        MSG="${RAW_MSG:0:$MSG_MAX_LEN}"
        ;;
      *)
        TRANSCRIPT="$(jq -r '.transcript_path // empty' <<<"$PAYLOAD")"
        if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
          # transcript 쓰기가 완료되길 잠시 대기
          sleep 0.3
          EXTRACTED="$(_extract_last_assistant_text "$TRANSCRIPT" last)"
          LAST_TEXT="${EXTRACTED%$'\x1f'*}"
          FALLBACK="${EXTRACTED##*$'\x1f'}"
          if [ -n "$LAST_TEXT" ]; then
            if [ "${CLAUDE_NOTIFY_SUMMARIZE:-1}" = 1 ] && command -v claude >/dev/null; then
              SYS="${_SYS_COMMON} 반드시 한국어 존댓말 의문형으로 끝맺으세요. '~인가요?', '~할까요?', '~하시겠어요?'처럼 끝내세요."
              MSG="$(_summarize_with_claude "$LAST_TEXT" "$SYS" "${CLAUDE_NOTIFY_QUESTION_TIMEOUT:-10}")"
            fi
            [ -z "$MSG" ] && MSG="${FALLBACK}"
          fi
        fi
        [ -z "$MSG" ] && MSG="${RAW_MSG:0:$MSG_MAX_LEN}"
        ;;
    esac

    GROUP_ID="$PROJECT"
    TITLE="[$PROJECT] ${SESSION_NAME:-undefined}"
    if [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ]; then
      ICON="$HOME/.claude/hooks/assets/claude-question-dark.webp"
    else
      ICON="$HOME/.claude/hooks/assets/claude-question-light.webp"
    fi
    ;;
  Stop)
    TRANSCRIPT="$(jq -r '.transcript_path // empty' <<<"$PAYLOAD")"
    LAST_TEXT=""
    FALLBACK=""
    if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
      # transcript 쓰기가 완료되길 잠시 대기
      sleep 0.3
      EXTRACTED="$(_extract_last_assistant_text "$TRANSCRIPT" first)"
      LAST_TEXT="${EXTRACTED%$'\x1f'*}"
      FALLBACK="${EXTRACTED##*$'\x1f'}"
    fi

    MSG=""
    if [ "${CLAUDE_NOTIFY_SUMMARIZE:-1}" = 1 ] && [ -n "$LAST_TEXT" ] && command -v claude >/dev/null; then
      SYS="${_SYS_COMMON} 반드시 한국어 존댓말로 끝맺으세요. '~입니다', '~했습니다', '~합니다'처럼 끝내세요."
      MSG="$(_summarize_with_claude "$LAST_TEXT" "$SYS" "${CLAUDE_NOTIFY_TIMEOUT:-30}")"
    fi
    [ -z "$MSG" ] && MSG="${FALLBACK:-작업이 끝났어요}"

    GROUP_ID="$SESSION_ID"
    TITLE="[$PROJECT] ${SESSION_NAME:-undefined}"
    ICON="$HOME/.claude/hooks/assets/claude-done.webp"
    ;;
  *) exit 0 ;;
esac

ALERTER_ARGS=(
  --title "$TITLE"
  --message "$MSG"
  --group "$GROUP_ID"
  --json
)

[ -f "${ICON:-}" ] && ALERTER_ARGS+=(--app-icon "$ICON")

(
  RESP="$("$ALERTER" "${ALERTER_ARGS[@]}" 2>/dev/null)"
  CHOICE="$(jq -r '.activationType // empty' <<<"$RESP" 2>/dev/null)"
  case "$CHOICE" in
    "contentsClicked"|"actionClicked")
      open -a "Visual Studio Code" "${CWD:-.}" ;;
  esac
) >/dev/null 2>&1 &

exit 0
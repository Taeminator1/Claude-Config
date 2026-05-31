#!/usr/bin/env bash
# Turn off the session-name nudge for ALL future sessions.
# Called by Claude when the user declines naming ("이름 짓지 않기").
set -uo pipefail

STATE_DIR="$HOME/.claude/.session-name-state"
mkdir -p "$STATE_DIR" 2>/dev/null
touch "$STATE_DIR/.nudge-disabled"
echo "session-name nudge disabled (all future sessions)"

#!/bin/sh
# Claude Code statusLine command
# Format: Dev | Sonnet 4.6 | ctx used:17% | 5h used:5% (remains 1h51m)

input=$(cat)

# ANSI colors
CYAN='\033[0;36m'
GRAY='\033[0;90m'
RESET='\033[0m'

# Current directory (basename only)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
dir=$(basename "$cwd")

# Directory (cyan)
printf "${CYAN}%s${RESET}" "$dir"

printf " ${GRAY}|${RESET}"

# Model name (strip trailing " (...)" suffixes like "(1M context)" or "(default)")
model=$(echo "$input" | jq -r '.model.display_name // empty' | sed -E 's/[[:space:]]*\([^)]*\)[[:space:]]*$//')
# Active output style (skip when default/empty so the bar stays short)
style=$(echo "$input" | jq -r '.output_style.name // empty')
if [ -n "$model" ]; then
    if [ -n "$style" ] && [ "$style" != "default" ]; then
        printf " ${GRAY}%s (%s)${RESET}" "$model" "$style"
    else
        printf " ${GRAY}%s${RESET}" "$model"
    fi
fi

# Context used percentage
ctx_used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$ctx_used" ]; then
    printf " ${GRAY}| ctx used:$(printf '%.0f' "$ctx_used")%%${RESET}"
fi

# 5-hour session rate limit usage and time remaining until reset
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

if [ -n "$five_pct" ] && [ -n "$five_resets" ]; then
    now=$(date +%s)
    diff=$((five_resets - now))
    if [ "$diff" -le 0 ]; then
        remains_str="resets now"
    else
        hours=$((diff / 3600))
        mins=$(( (diff % 3600) / 60 ))
        if [ "$hours" -gt 0 ]; then
            remains_str="${hours}h${mins}m"
        else
            remains_str="${mins}m"
        fi
    fi
    printf " ${GRAY}| 5h used:$(printf '%.0f' "$five_pct")%% (remains %s)${RESET}" "$remains_str"
fi

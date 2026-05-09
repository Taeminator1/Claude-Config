#!/bin/bash
# Format: Opus 4.7 (1M context) (style: default) | ctx used:4% | 5h used:4% (remains 3h46m)

input=$(cat)

# Model: strip "Claude " prefix, keep version only (e.g. "Sonnet 4.6")
model=$(echo "$input" | jq -r '.model.display_name // "Unknown"' | sed 's/^Claude //')

output_style=$(echo "$input" | jq -r '.output_style.name // empty')
if [ -n "$output_style" ]; then
  model="${model} (style: ${output_style})"
fi

# Context window used %
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  context_str="ctx used:${used_int}%"
else
  context_str="ctx used:-"
fi

# 5-hour rate limit: used % + remaining duration until reset
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_hour_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

if [ -n "$five_hour_pct" ] && [ -n "$five_hour_resets" ]; then
  now=$(date +%s)
  remaining_secs=$(( five_hour_resets - now ))
  if [ "$remaining_secs" -lt 0 ]; then
    remaining_secs=0
  fi
  remaining_h=$(( remaining_secs / 3600 ))
  remaining_m=$(( (remaining_secs % 3600) / 60 ))
  if [ "$remaining_h" -gt 0 ] && [ "$remaining_m" -gt 0 ]; then
    remains_str="${remaining_h}h${remaining_m}m"
  elif [ "$remaining_h" -gt 0 ]; then
    remains_str="${remaining_h}h"
  else
    remains_str="${remaining_m}m"
  fi
  five_hour_int=$(printf "%.0f" "$five_hour_pct")
  rate_str="5h used:${five_hour_int}% (remains ${remains_str})"
elif [ -n "$five_hour_pct" ]; then
  five_hour_int=$(printf "%.0f" "$five_hour_pct")
  rate_str="5h used:${five_hour_int}%"
else
  rate_str="-"
fi

printf '%s | %s | %s' "$model" "$context_str" "$rate_str"
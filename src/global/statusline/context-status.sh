#!/usr/bin/env bash
# context-status.sh — Claude Code status line script
# Shows context window usage with colored progress bar.
# Reads JSON from stdin (provided by Claude Code).
# Context window size auto-detected from session data.

input=$(cat)

# Extract values from Claude Code JSON
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' 2>/dev/null)
WINDOW_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 0' 2>/dev/null)

# Guard: if jq failed or values are null/empty, show minimal fallback
if [[ -z "$PCT" || "$PCT" == "null" || -z "$WINDOW_SIZE" || "$WINDOW_SIZE" == "null" || "$WINDOW_SIZE" == "0" ]]; then
  echo "⚡ context: waiting..."
  exit 0
fi

# Truncate percentage to integer
PCT_INT=${PCT%%.*}

# Calculate used tokens
USED_TOKENS=$(( WINDOW_SIZE * PCT_INT / 100 ))

# Format token counts for display (e.g., 23k, 1M)
format_tokens() {
  local tokens=$1
  if [[ $tokens -ge 1000000 ]]; then
    local m=$(( tokens / 1000000 ))
    local remainder=$(( (tokens % 1000000) / 100000 ))
    if [[ $remainder -gt 0 ]]; then
      echo "${m}.${remainder}M"
    else
      echo "${m}M"
    fi
  elif [[ $tokens -ge 1000 ]]; then
    local k=$(( tokens / 1000 ))
    echo "${k}k"
  else
    echo "${tokens}"
  fi
}

USED_DISPLAY=$(format_tokens "$USED_TOKENS")
TOTAL_DISPLAY=$(format_tokens "$WINDOW_SIZE")

# Color thresholds (ANSI escape codes)
# Green: 0-25% | Yellow: 25-40% | Orange: 40-60% | Red: 60%+
RST='\033[0m'
if [[ $PCT_INT -ge 60 ]]; then
  CLR='\033[31m'  # red
elif [[ $PCT_INT -ge 40 ]]; then
  CLR='\033[38;5;208m'  # orange
elif [[ $PCT_INT -ge 25 ]]; then
  CLR='\033[33m'  # yellow
else
  CLR='\033[32m'  # green
fi

# Build progress bar (10 chars)
BAR_WIDTH=10
FILLED=$(( PCT_INT * BAR_WIDTH / 100 ))
# Always show at least 1 filled block when usage > 0%
if [[ $PCT_INT -gt 0 && $FILLED -eq 0 ]]; then
  FILLED=1
fi
if [[ $FILLED -gt $BAR_WIDTH ]]; then
  FILLED=$BAR_WIDTH
fi
EMPTY=$(( BAR_WIDTH - FILLED ))

BAR=$(printf "%${FILLED}s" | tr ' ' '▓')$(printf "%${EMPTY}s" | tr ' ' '░')

echo -e "⚡ context: ${USED_DISPLAY}/${TOTAL_DISPLAY} ${CLR}${BAR}${RST} ${PCT_INT}%"

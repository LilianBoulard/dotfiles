#!/bin/bash

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for the status line to work"
  exit 0
fi

reset_color=""
directory_color="" model_color="" version_color="" git_color="" usage_color="" cost_color="" burn_rate_color=""
context_color=""

if [ -z "$NO_COLOR" ]; then
  reset_color=$'\033[0m'
  directory_color=$'\033[38;5;117m'      # sky blue
  model_color=$'\033[38;5;147m'          # light purple
  version_color=$'\033[38;5;180m'        # soft yellow
  git_color=$'\033[38;5;150m'            # soft green
  usage_color=$'\033[38;5;189m'          # lavender
  cost_color=$'\033[38;5;222m'           # light gold
  burn_rate_color=$'\033[38;5;220m'      # bright gold
  context_color=$'\033[1;37m'            # default: white
fi

progress_bar() {
  local percent="${1:-0}" width="${2:-50}"
  [[ "$percent" =~ ^[0-9]+$ ]] || percent=0
  ((percent < 0)) && percent=0
  ((percent > 100)) && percent=100
  local filled_count=$((percent * width / 100))
  local empty_count=$((width - filled_count))
  printf '%*s' "$filled_count" '' | tr ' ' '#'
  printf '%*s' "$empty_count" '' | tr ' ' '-'
}

eval "$(echo "$input" | jq -r '
  @sh "current_directory=\(.workspace.current_dir // .cwd // "unknown")",
  @sh "model_name=\(.model.display_name // "Claude")",
  @sh "model_version=\(.model.version // "")",
  @sh "context_window_size=\(.context_window.context_window_size // 200000)",
  @sh "total_cost_usd=\(.cost.total_cost_usd // "")",
  @sh "total_duration_ms=\(.cost.total_duration_ms // "")",
  @sh "total_input_tokens=\(.context_window.total_input_tokens // 0)",
  @sh "total_output_tokens=\(.context_window.total_output_tokens // 0)"
' 2>/dev/null)"
current_directory=$(echo "$current_directory" | sed "s|^$HOME|~|g")

git_branch=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  git_branch=$(git branch --show-current 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
fi

context_consumed_percent=0

current_usage=$(echo "$input" | jq '.context_window.current_usage' 2>/dev/null)

if [ "$current_usage" != "null" ] && [ -n "$current_usage" ]; then
  current_token_count=$(echo "$current_usage" | jq '(.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)' 2>/dev/null)

  if [ -n "$current_token_count" ] && [ "$current_token_count" -gt 0 ] 2>/dev/null; then
    context_consumed_percent=$((current_token_count * 100 / context_window_size))
    ((context_consumed_percent < 0)) && context_consumed_percent=0
    ((context_consumed_percent > 100)) && context_consumed_percent=100
  fi
fi

if [ -z "$NO_COLOR" ]; then
  if [ "$context_consumed_percent" -ge 80 ]; then
    context_color=$'\033[38;5;203m'    # coral red
  elif [ "$context_consumed_percent" -ge 60 ]; then
    context_color=$'\033[38;5;215m'    # peach
  else
    context_color=$'\033[38;5;158m'    # mint green
  fi
fi

cost_per_hour=""
if [ -n "$total_cost_usd" ] && [ -n "$total_duration_ms" ] && [ "$total_duration_ms" -gt 0 ]; then
  cost_per_hour=$(awk -v cost="$total_cost_usd" -v duration="$total_duration_ms" 'BEGIN {printf "%.2f", cost * 3600000 / duration}')
fi

combined_token_count=""
tokens_per_minute=""
if [ "$total_input_tokens" != "null" ] && [ "$total_output_tokens" != "null" ]; then
  combined_token_count=$((total_input_tokens + total_output_tokens))
  [ "$combined_token_count" -eq 0 ] && combined_token_count=""
fi

if [ -n "$combined_token_count" ] && [ -n "$total_duration_ms" ] && [ "$total_duration_ms" -gt 0 ]; then
  tokens_per_minute=$(awk -v tokens="$combined_token_count" -v duration="$total_duration_ms" 'BEGIN {printf "%.0f", tokens * 60000 / duration}')
fi

# Line 1: Core info (directory, git, model, version)
printf '%s%s%s' "$directory_color" "$current_directory" "$reset_color"
if [ -n "$git_branch" ]; then
  printf ' · %s%s%s' "$git_color" "$git_branch" "${reset_color} branch"
fi
printf ' · %s%s%s' "$model_color" "$model_name" "$reset_color"
if [ -n "$model_version" ] && [ "$model_version" != "null" ]; then
  printf ' · %s%s%s' "$version_color" "$model_version" "$reset_color"
fi

# Line 2: Context consumption
context_progress_bar=$(progress_bar "$context_consumed_percent")
context_line="${context_color}${context_consumed_percent}% [${context_progress_bar}]${reset_color}"

# Line 3: Cost and usage analytics
analytics_line=""
if [ -n "$total_cost_usd" ] && [[ "$total_cost_usd" =~ ^[0-9.]+$ ]]; then
  if [ -n "$cost_per_hour" ] && [[ "$cost_per_hour" =~ ^[0-9.]+$ ]]; then
    analytics_line="${cost_color}\$$(printf '%.2f' "$total_cost_usd")${reset_color} (${burn_rate_color}\$${cost_per_hour}/h${reset_color})"
  else
    analytics_line="${cost_color}\$$(printf '%.2f' "$total_cost_usd")${reset_color}"
  fi
fi

if [ -n "$combined_token_count" ] && [[ "$combined_token_count" =~ ^[0-9]+$ ]]; then
  token_summary="${usage_color}${combined_token_count} tok"
  if [ -n "$tokens_per_minute" ] && [[ "$tokens_per_minute" =~ ^[0-9.]+$ ]]; then
    token_summary="${token_summary} (${tokens_per_minute} tpm)"
  fi
  token_summary="${token_summary}${reset_color}"

  if [ -n "$analytics_line" ]; then
    analytics_line="$analytics_line · $token_summary"
  else
    analytics_line="$token_summary"
  fi
fi

# Print lines
printf '\n%s' "$context_line"
[ -n "$analytics_line" ] && printf '\n%s' "$analytics_line"
printf '\n'

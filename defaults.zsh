#!/usr/bin/zsh
# ~/.zoracle/defaults.zsh — Environment variables, tunables & system prompt

# ---------- LLM endpoint ----------
# 127.0.0.1 (not "localhost"): MSYS may try IPv6 ::1 first, which this
# server does not bind; a dropped (rather than refused) ::1 SYN would stall
# curl for the full connect timeout.
export ZORACLE_LLM_BASE_URL="${ZORACLE_LLM_BASE_URL:-http://127.0.0.1:1919}"
export ZORACLE_LLM_MODEL="${ZORACLE_LLM_MODEL:-minicpm5-2b}"
export ZORACLE_LLM_MAX_OUTPUT_TOKENS="${ZORACLE_LLM_MAX_OUTPUT_TOKENS:-65536}"
export ZORACLE_LLM_API_KEY="${ZORACLE_LLM_API_KEY:-not-needed}"

# ---------- Request timeouts (curl) ----------
typeset -g ZORACLE_CONNECT_TIMEOUT_SECONDS="${ZORACLE_CONNECT_TIMEOUT_SECONDS:-10}" # seconds to establish TCP
typeset -g ZORACLE_REQUEST_TIMEOUT_SECONDS="${ZORACLE_REQUEST_TIMEOUT_SECONDS:-600}"              # total request budget; long generations
# Abort when NOTHING at all arrives for this long (the "connected but the
# server never serves the request" wedge). Average bytes/sec in the window
# falls below ZORACLE_LOW_SPEED_LIMIT_BYTES_PER_SECOND → curl kills the transfer with rc 28.
typeset -g ZORACLE_LOW_SPEED_TIME_SECONDS="${ZORACLE_LOW_SPEED_TIME_SECONDS:-30}"
typeset -g ZORACLE_LOW_SPEED_LIMIT_BYTES_PER_SECOND="${ZORACLE_LOW_SPEED_LIMIT_BYTES_PER_SECOND:-1}"
typeset -g ZORACLE_REQUEST_MIN_INTERVAL_SECONDS=2

# ---------- Agent tunables ----------
typeset -g ZORACLE_AGENT_MAX_ITERATIONS="${ZORACLE_AGENT_MAX_ITERATIONS:-16}"
typeset -g ZORACLE_TOOL_OUTPUT_MAX_CHARS="${ZORACLE_TOOL_OUTPUT_MAX_CHARS:-4000}"
typeset -g ZORACLE_SHELL_TIMEOUT_SECONDS="${ZORACLE_SHELL_TIMEOUT_SECONDS:-10}"
typeset -g ZORACLE_FETCH_MAX_CHARS="${ZORACLE_FETCH_MAX_CHARS:-4000}"
typeset -g ZORACLE_SEARCH_MAX_RESULTS="${ZORACLE_SEARCH_MAX_RESULTS:-50}"
typeset -g ZORACLE_WORKSPACE_ROOT="${ZORACLE_WORKSPACE_ROOT:-}" # jail for file/exec/search tools
typeset -g ZORACLE_EXEC_ENABLED="${ZORACLE_EXEC_ENABLED:-0}" # kill switch: 0 = exec disabled (default), 1 = enabled
typeset -g ZORACLE_SANDBOX_IMAGE="${ZORACLE_SANDBOX_IMAGE:-alpine:3.20}"
typeset -g ZORACLE_SANDBOX_NETWORK="${ZORACLE_SANDBOX_NETWORK:-none}"

# ---------- Integration keys (all optional) ----------
# Search: TAVILY_API_KEY (preferred, free tier) or SERPAPI_KEY
# Comms:  SLACK_WEBHOOK_URL / DISCORD_WEBHOOK_URL / TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID

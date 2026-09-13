#!/usr/bin/zsh
# ~/.zoracle/tools/comms.zsh — Messaging gateways (Slack / Discord / Telegram)

_zoracle_tool_notify() {
  local platform message
  if [[ -n "${_ZORACLE_ARG_PLATFORM+x}" ]]; then
    # Native tool call: exact platform/message (newlines preserved)
    platform="$_ZORACLE_ARG_PLATFORM"
    message="$_ZORACLE_ARG_MESSAGE"
  else
    # Legacy positional form: <platform> <message>
    local input="${*:-}"
    local -a parts
    parts=(${(z)input})
    platform="${parts[1]:-}"
    message="${(j: :)parts[2,-1]}"
  fi

  if [[ -z "$platform" || -z "$message" ]]; then
    printf 'Usage: notify <slack|discord|telegram> <message>\n'
    return 1
  fi

  _zoracle_web_rate_limit

  case "$platform" in
    slack)
      if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
        printf 'ERROR: SLACK_WEBHOOK_URL is not set.\n'
        return 1
      fi
      local payload
      payload=$(jq -cn --arg t "$message" '{text: $t}')
      local resp
      resp=$(curl -sS -m 10 -X POST "$SLACK_WEBHOOK_URL" \
        -H 'Content-Type: application/json' -d "$payload")
      if [[ "$resp" == "ok" ]]; then
        printf 'OK: message sent to Slack.\n'
      else
        printf 'ERROR: Slack rejected the message: %s\n' "$resp"
        return 1
      fi
      ;;
    discord)
      if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
        printf 'ERROR: DISCORD_WEBHOOK_URL is not set.\n'
        return 1
      fi
      local payload
      payload=$(jq -cn --arg t "$message" '{content: $t}')
      local code
      code=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' -X POST "$DISCORD_WEBHOOK_URL" \
        -H 'Content-Type: application/json' -d "$payload")
      if [[ "$code" == 200 || "$code" == 204 ]]; then
        printf 'OK: message sent to Discord.\n'
      else
        printf 'ERROR: Discord returned HTTP %s\n' "$code"
        return 1
      fi
      ;;
    telegram)
      if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
        printf 'ERROR: TELEGRAM_BOT_TOKEN is not set.\n'
        return 1
      fi
      if [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        printf 'ERROR: TELEGRAM_CHAT_ID is not set.\n'
        return 1
      fi
      local payload
      payload=$(jq -cn --arg chat "$TELEGRAM_CHAT_ID" --arg t "$message" \
        '{chat_id: $chat, text: $t}')
      local resp
      resp=$(curl -sS -m 10 -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -H 'Content-Type: application/json' -d "$payload")
      if jq -e '.ok == true' <<<"$resp" >/dev/null 2>&1; then
        printf 'OK: message sent to Telegram.\n'
      else
        printf 'ERROR: Telegram API failure: %s\n' "$resp"
        return 1
      fi
      ;;
    telegram_pull)
      if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
        printf 'ERROR: TELEGRAM_BOT_TOKEN is not set.\n'
        return 1
      fi
      local resp
      resp=$(curl -sS -m 10 "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getUpdates") || return 1
      local parsed
      parsed=$(jq -r '
        .result // [] |
        map(.message // empty | "FROM: " + (.from.username // .from.first_name // "?") +
            "\nTEXT: " + (.text // "") +
            "\nDATE: " + (.date | tostring)) |
        join("\n---\n")
      ' <<<"$resp")
      if [[ -z "$parsed" ]]; then
        printf 'No pending Telegram messages.\n'
      else
        printf '%s\n' "$parsed"
      fi
      ;;
    *)
      printf 'ERROR: unknown platform "%s" (supported: slack, discord, telegram, telegram_pull)\n' "$platform"
      return 1
      ;;
  esac
}

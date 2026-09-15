#!/usr/bin/zsh

_zoracle_jq() {
  local out rc

  out=$(command jq "$@")
  rc=$?

  out="${out//$'\r'/}"
  printf '%s' "$out"
  return "$rc"
}


_zoracle_llm_turn() {
  local no_reasoning=false
  local OPTIND=1
  local option

  while getopts ':n' option; do
    case "$option" in
      n) no_reasoning=true ;;
      \?) printf 'Usage: _zoracle_llm_turn [-n] [--] prompt\n' >&2; return 2 ;;
    esac
  done

  shift $((OPTIND - 1))

  local prompt="$*"
  local request_messages
  local tools_json='[]'
  local chunk_file
  local -a pipeline_status
  local exit_code
  local failed=0

  # Tool schemas advertised to the model via the request "tools" key
  # (OpenAI function-calling format; defined in tools/schema.zsh)
  if command -v _zoracle_get_tools_json >/dev/null 2>&1; then
    tools_json=$(_zoracle_get_tools_json) || tools_json='[]'
  fi

  # Auto-inject system prompt on empty history
  if [[ "$_ZORACLE_MESSAGES_JSON" == "[]" ]]; then
    _ZORACLE_MESSAGES_JSON=$(_zoracle_jq -cn --arg sys "$_ZORACLE_SYSTEM_PROMPT" '[{role: "system", content: $sys}]')
  fi

  if [[ -n "$prompt" ]]; then
    if ! request_messages=$(
      _zoracle_jq -ce --arg prompt "$prompt" \
        '. + [{role: "user", content: $prompt}]' \
        <<<"$_ZORACLE_MESSAGES_JSON"
    ); then
      printf '_zoracle_llm_turn: conversation history is invalid\n' >&2
      return 1
    fi
  else
    request_messages="$_ZORACLE_MESSAGES_JSON"
  fi

  chunk_file=$(mktemp) || return 1

  jq -c \
  --arg model "$_ZORACLE_LLM_MODEL" \
  --argjson max_output_tokens "$ZORACLE_LLM_MAX_OUTPUT_TOKENS" \
  --argjson no_reasoning "$no_reasoning" \
  --argjson tools "$tools_json" '
    {
      model: $model,
      messages: .,
      max_tokens: $max_output_tokens,
      stream: true,
      tools: $tools
    }
    +
    (
      if $no_reasoning then
        {
          reasoning_effort: "none",
          chat_template_kwargs: {
            enable_thinking: false
          }
        }
      else
        {}
      end
    )
  ' <<<"$request_messages" |
    curl -sS -N --fail-with-body \
      --ipv4 \
      --no-keepalive \
      --connect-timeout "$ZORACLE_CONNECT_TIMEOUT_SECONDS" \
      --max-time "$ZORACLE_REQUEST_TIMEOUT_SECONDS" \
      --speed-limit "$ZORACLE_LOW_SPEED_LIMIT_BYTES_PER_SECOND" \
      --speed-time "$ZORACLE_LOW_SPEED_TIME_SECONDS" \
      "${ZORACLE_LLM_BASE_URL%/}/v1/chat/completions" \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $ZORACLE_LLM_API_KEY" \
      -d @- |
    stdbuf -oL grep '^data: {' |
    stdbuf -oL sed 's/^data: //' |

    while IFS= read -r chunk; do
      printf '%s\n' "$chunk" >&3
      printf '%s\n' "$chunk"
    done 3>"$chunk_file" |

    ## Keep untrimmed jq!
    jq --unbuffered -j '
      foreach (., inputs) as $chunk (
        {saw_reasoning: false, saw_content: false, saw_tool: false, output: ""};

        ($chunk.choices[0].delta // {}) as $delta
        | if (($delta.reasoning_content // "") | length) > 0 then
            .output = (
              "\u001b[2m" + $delta.reasoning_content + "\u001b[0m"
            )
            | .saw_reasoning = true

          elif (($delta.content // "") | length) > 0 then
            .output = (
              if .saw_reasoning and (.saw_content | not)
              then "\n\n" + $delta.content
              else $delta.content
              end
            )
            | .saw_content = true

          elif (($delta.tool_calls // []) | length) > 0 then
            .output = (
              (if (.saw_reasoning or .saw_content) and (.saw_tool | not)
               then "\n" else "" end)
              +
              ([$delta.tool_calls[] |
                 (if ((.function.name // "") | length) > 0
                  then "\u001b[1;35m→ tool: " + .function.name + "\u001b[0m("
                  else "" end)
                 + (.function.arguments // "")
               ] | join(""))
            )
            | .saw_tool = true

          elif (.saw_tool and
                (($chunk.choices[0].finish_reason // "") == "tool_calls")) then
            .output = ")\n"

          else
            .output = ""
          end;

        .output
      )
    '

  pipeline_status=("${pipestatus[@]}")
  printf '\n'

  for exit_code in "${pipeline_status[@]}"; do
    if (( exit_code != 0 )); then
      failed=1
    fi
  done

  if (( failed )); then
    rm -f "$chunk_file"
    printf '_zoracle_llm_turn: request failed (stage exit codes: %s); conversation was not updated\n' "${(j: :)pipeline_status}" >&2
    printf '  hint: rc 28 = timed out, rc 7 = could not connect, rc 22 = HTTP error.\n' >&2
    printf '  timeouts: connect=%ss no-data-abort=%ss total=%ss — endpoint %s\n' \
      "$ZORACLE_CONNECT_TIMEOUT_SECONDS" "$ZORACLE_LOW_SPEED_TIME_SECONDS" "$ZORACLE_REQUEST_TIMEOUT_SECONDS" "$ZORACLE_LLM_BASE_URL" >&2
    printf '  if the server is up but unresponsive, restart it (wedged slots make requests wait forever).\n' >&2
    return 1
  fi

  local updated_messages

  if ! updated_messages=$(
    _zoracle_jq -c \
      --arg prompt "$prompt" \
      --slurpfile chunks "$chunk_file" '
        ($chunks
         | map(.choices[0].delta.content // "")
         | join("")) as $content
        | ($chunks
           | map(.choices[0].delta.tool_calls // empty)
           | flatten
           | group_by(.index // 0)
           | map(
               (.[0].index // 0) as $idx
               | {
                   id: (
                     ([.[] | .id? // empty | select(length > 0)] | first)
                     // ("call_" + ($idx | tostring))
                   ),
                   type: "function",
                   function: {
                     name: (
                       ([.[] | .function.name? // empty | select(length > 0)] | first)
                       // "unknown"
                     ),
                     arguments: (map(.function.arguments? // "") | join(""))
                   }
                 }
             )) as $tool_calls
        | (
            (if ($prompt | length) > 0 then
               . + [{role: "user", content: $prompt}]
             else
               .
             end)
            + [{
                role: "assistant",
                content: $content
              }
              + (if ($tool_calls | length) > 0 then
                   {tool_calls: $tool_calls}
                 else
                   {}
                 end)]
          )
      ' <<<"$_ZORACLE_MESSAGES_JSON"
  ); then
    rm -f "$chunk_file"
    printf '_zoracle_llm_turn: failed to update conversation history\n' >&2
    return 1
  fi

  _ZORACLE_MESSAGES_JSON="$updated_messages"
  rm -f "$chunk_file"
}

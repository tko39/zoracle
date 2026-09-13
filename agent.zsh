#!/usr/bin/zsh
# ~/.zoracle/agent.zsh

# Source the toolchain if not already present (loads config, tools, core)
[[ $(type -w _zoracle_execute_tool_json) == *function* ]] || source ~/.zoracle/init.zsh

# Agent Driver Function
_zoracle_agent() {

  # If no arguments provided, start interactive session
  if [[ $# -eq 0 ]]; then
    _zoracle_agent_interactive
    return $?
  fi

  local max_iterations="${ZORACLE_AGENT_MAX_ITERATIONS:-8}"
  local iter=0
  local max_out="${ZORACLE_TOOL_OUTPUT_MAX_CHARS:-4000}"
  local tool_calls=""
  local call=""
  local tc_id=""
  local tc_name=""
  local tc_args=""
  local tool_output=""
  local t_rc=0
  local n_calls=0

  # Invoke primary llm turn stream (uses user's exact function)
  _zoracle_llm_turn "$@" || return 1

  while (( iter < max_iterations )); do
    (( iter++ ))

    # Native tool calls made by the newest assistant message (OpenAI
    # format: {id, type, function: {name, arguments}} where arguments is a
    # JSON *string*). Normalized here; missing ids are synthesized from
    # position so tool results can always be keyed.
    if ! tool_calls=$(_zoracle_jq -c '
      ((map(select(.role == "assistant")) | last // {})
        | .tool_calls // [])
      | to_entries
      | map({
          id: (
            (.value.id? // "")
            | if . == "" then "call_" + (.key | tostring) else . end
          ),
          name: (.value.function.name? // ""),
          arguments: (.value.function.arguments? // "")
        })
    ' <<<"$_ZORACLE_MESSAGES_JSON"); then
      printf '\033[1;31m[Agent Error]\033[0m conversation history is not valid JSON.\n' >&2
      return 1
    fi

    n_calls=$(_zoracle_jq 'length' <<<"$tool_calls") || return 1

    if (( n_calls == 0 )); then
      # No tool calls: the model finished its task
      break
    fi

    # Execute every requested tool call, then append each result as a
    # role:"tool" message keyed by tool_call_id (OpenAI format). Batched
    # calls all run before the follow-up request.
    while IFS= read -r call; do
      [[ -n "$call" ]] || continue

      tc_id=$(_zoracle_jq -r '.id // ""' <<<"$call")
      tc_name=$(_zoracle_jq -r '.name // ""' <<<"$call")
      tc_args=$(_zoracle_jq -r '.arguments // "{}"' <<<"$call")

      printf '\n\033[1;33m[Agent Intercept]\033[0m Executing tool: \033[36m%s\033[0m with args: \033[32m%s\033[0m...\n' "$tc_name" "$tc_args"

      # Execute the target tool with its JSON arguments. Fold stderr into
      # the result so tools that report failures only on stderr still show
      # up; if the tool fails with no output at all, synthesize a message
      # so the model never receives an empty tool result.
      tool_output=$(_zoracle_execute_tool_json "$tc_name" "$tc_args" 2>&1)
      t_rc=$?
      if (( t_rc != 0 )) && [[ -z "$tool_output" ]]; then
        tool_output="ERROR: tool \"$tc_name\" exited with status $t_rc and produced no output."
      fi

      # Truncate output safety check (configurable, default 4000 chars)
      if (( ${#tool_output} > max_out )); then
        tool_output="${tool_output[1,$max_out]}

[Output truncated due to length...]"
      fi

      # Surface the tool's result in the terminal — otherwise a failed call
      # looks like nothing happened and the user can't tell what went wrong.
      printf '\n\033[1;36m[Tool Result]\033[0m \033[36m%s\033[0m:\n%s\n' "$tc_name" "$tool_output"

      _ZORACLE_MESSAGES_JSON=$(
        _zoracle_jq -c --arg id "$tc_id" --arg name "$tc_name" --arg out "$tool_output" \
          '. + [{role: "tool", tool_call_id: $id, name: $name, content: $out}]' \
          <<<"$_ZORACLE_MESSAGES_JSON"
      )
    done <<<"$(_zoracle_jq -c '.[]' <<<"$tool_calls")"

    printf '\033[1;33m[Agent System]\033[0m %d tool result(s) fed back to model. Resuming thought stream...\n\n' "$n_calls"

    # Continue generation with the updated history (no new user prompt).
    # -n disables the reasoning loop on tool re-evaluations.
    _zoracle_llm_turn -n "" || return 1
  done

  if (( iter >= max_iterations )); then
    printf '\033[1;31m[Agent Error]\033[0m Maximum tool iterations (%d) reached.\n' "$max_iterations" >&2
  fi
}

_zoracle_agent_interactive() {
  setopt localoptions localtraps extendedglob

  local user_input
  printf '\033[1;32m[Agent Interactive Mode]\033[0m Type "/exit" or "/quit" to leave.\n\n'

  local temp_hist=$(mktemp)

  _cleanup() {
    local target_file="$1"
    [[ -n $target_file ]] && rm -f "$target_file"
  }

  # Set interrupt flag for external signals
  _on_interrupt() {
    _cleanup "$1"
    zle send-break
  }

  trap "_on_interrupt '$temp_hist'" INT TERM
  trap "_cleanup '$temp_hist'" EXIT

  local HISTFILE="$temp_hist"
  touch "$temp_hist"
  fc -ap "$temp_hist" 500 2>/dev/null

  local final_rc=0

  # Widget for Ctrl+D
  zle -N _self_insert_exit
  _self_insert_exit() {
    if [[ -z "$BUFFER" ]]; then
      BUFFER="/exit"
      zle accept-line
    else
      zle delete-char-or-list
    fi
  }

  _agent_complete() {
    (( CURRENT == 1 )) || return 0
    compadd -- /exit /quit /history /clear
  }

  bindkey -N agent-interactive main
  bindkey -M agent-interactive '^D' _self_insert_exit
  zle -C _agent_complete_widget complete-word _agent_complete
  bindkey -M agent-interactive '^I' _agent_complete_widget

  while true; do
    user_input=""

    # Run vared
    vared -M agent-interactive -h -p $'\033[1;34mYou:\033[0m ' -c user_input
    local exit_code=$?

    if (( exit_code != 0 )); then
      printf '\n\033[1;31m[Agent]\033[0m Interrupted.\n'
      final_rc=130
      break
    fi

    user_input="${${user_input##[[:space:]]#}%%[[:space:]]#}"

    if [[ "$user_input" =~ ^(/exit|/quit)$ ]]; then
      printf '\n\033[1;32m[Agent]\033[0m Goodbye!\n'
      final_rc=0
      break
    fi

    if [[ -z "$user_input" ]]; then
      continue
    fi

    print -s -- "$user_input"
    fc -W "$temp_hist"
    
    if [ "$user_input" = "/clear" ]; then
      _ZORACLE_MESSAGES_JSON='[]'
      printf 'Conversation cleared.\n'
      continue
    elif [ "$user_input" = "/history" ]; then
      _zoracle_jq . <<<"$_ZORACLE_MESSAGES_JSON"
      continue
    fi

    _zoracle_agent "$user_input"
  done

  return $final_rc
}


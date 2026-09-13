#!/usr/bin/zsh
# ~/.zoracle/tools/router.zsh — Unified tool router
# Maps native tool calls (name + JSON arguments object) from the model's
# tool_calls, plus legacy positional strings, onto the tool_* functions.
# Uses explicit case statements (no eval). Functions are resolved by zsh
# at call time, so load order in init.zsh does not matter.

_zoracle_execute_tool() {
  local tool_name="$1"
  shift
  local args="$*"

  case "$tool_name" in
    search|web_search)
      _zoracle_tool_web_search "$args"
      ;;
    fetch|fetch_page|scrape)
      _zoracle_tool_fetch_page "$args"
      ;;
    time|date)
      _zoracle_tool_time "$args"
      ;;
    read|read_file|cat)
      _zoracle_tool_read_file "$args"
      ;;
    write|write_file)
      _zoracle_tool_write_file "$args"
      ;;
    append|append_file)
      _zoracle_tool_append_file "$args"
      ;;
    patch|edit|edit_file)
      _zoracle_tool_patch_file "$args"
      ;;
    exec|run|shell)
      _zoracle_tool_exec "$args"
      ;;
    sandbox)
      _zoracle_tool_sandbox "$args"
      ;;
    find|locate)
      _zoracle_tool_find "$args"
      ;;
    grep|search_code)
      _zoracle_tool_grep "$args"
      ;;
    notify|send|message)
      _zoracle_tool_notify "$args"
      ;;
    *)
      printf 'ERROR: unknown tool "%s".\nAvailable tools:\n' "$tool_name"
      printf '  search <query>                 - web search (Tavily/SerpAPI)\n'
      printf '  fetch <url>                    - extract readable text from a webpage\n'
      printf '  time <now|+2 hours|<epoch>|diff e1 e2> - date/time grounding & math\n'
      printf '  read_file <path> [max_lines]   - read a text file (numbered lines)\n'
      printf '  write_file <path> <text>       - create/overwrite a file (\\n = newline)\n'
      printf '  append_file <path> <text>      - append to a file\n'
      printf '  patch_file <path> <old> @@ <new> - literal search/replace in a file\n'
      printf '  exec <command>                 - run a shell command (trusted)\n'
      printf '  sandbox <command>              - run a command in an isolated container\n'
      printf '  find <glob> [dir]              - locate files by name pattern\n'
      printf '  grep <pattern> [dir]           - search file contents (ripgrep)\n'
      printf '  notify <slack|discord|telegram> <msg> - send a message\n'
      return 1
      ;;
  esac
}

_zoracle_execute_tool_json() {
  # Execute a tool from a native function call: <name> + JSON arguments.
  # Translates the JSON object into exact-value parameters for the tool_*
  # functions. Whitespace-sensitive values (file content, patterns,
  # messages) travel via _ZORACLE_ARG_* variables that the tools read
  # directly (zsh dynamic scoping), so spaces and newlines survive intact.
  #
  # NOTE: every jq call here goes through _zoracle_jq, NOT raw jq. The
  # Windows jq build emits CRLF line endings, so a raw `jq -r 'type'`
  # returns "object\r" and the guard below would falsely reject every valid
  # arguments object (the "arguments must be a JSON object" error seen in
  # sessions). _zoracle_jq strips the stray \r from the type check AND from
  # every argument value extracted below.
  local tool_name="$1"
  local json_args="$2"
  [[ -n "$json_args" ]] || json_args='{}'

  # Guard: arguments must be a JSON object (small models sometimes emit a
  # bare string). The error text is fed back to the model as tool output.
  # Note: jq -e on this Windows build doesn't reliably return non-zero for
  # false, so we check the type string directly.
  local arg_type
  arg_type=$(_zoracle_jq -r 'type' <<<"$json_args") || {
    printf 'ERROR: tool arguments must be valid JSON (got: %s)\n' "$json_args"
    return 1
  }
  if [[ "$arg_type" != "object" ]]; then
    printf 'ERROR: tool arguments must be a JSON object matching the tool schema (got: %s)\n' "$json_args"
    return 1
  fi

  case "$tool_name" in
    search)
      _zoracle_tool_web_search "$(_zoracle_jq -r '.query // ""' <<<"$json_args")"
      ;;
    fetch)
      _zoracle_tool_fetch_page "$(_zoracle_jq -r '.url // ""' <<<"$json_args")"
      ;;
    time)
      _zoracle_tool_time "$(_zoracle_jq -r 'if ((.spec // "") | length) > 0 then .spec else "now" end' <<<"$json_args")"
      ;;
    read_file)
      local _ZORACLE_ARG_PATH _ZORACLE_ARG_MAX_LINES
      _ZORACLE_ARG_PATH=$(_zoracle_jq -r '.path // ""' <<<"$json_args")
      _ZORACLE_ARG_MAX_LINES=$(_zoracle_jq -r '.max_lines // ""' <<<"$json_args")
      _zoracle_tool_read_file
      ;;
    write_file)
      local _ZORACLE_ARG_PATH _ZORACLE_ARG_CONTENT
      _ZORACLE_ARG_PATH=$(_zoracle_jq -r '.path // ""' <<<"$json_args")
      _ZORACLE_ARG_CONTENT=$(_zoracle_jq -j '.content // ""' <<<"$json_args")
      _zoracle_tool_write_file
      ;;
    append_file)
      local _ZORACLE_ARG_PATH _ZORACLE_ARG_CONTENT
      _ZORACLE_ARG_PATH=$(_zoracle_jq -r '.path // ""' <<<"$json_args")
      _ZORACLE_ARG_CONTENT=$(_zoracle_jq -j '.content // ""' <<<"$json_args")
      _zoracle_tool_append_file
      ;;
    patch_file)
      local _ZORACLE_ARG_PATH _ZORACLE_ARG_OLD_TEXT _ZORACLE_ARG_NEW_TEXT
      _ZORACLE_ARG_PATH=$(_zoracle_jq -r '.path // ""' <<<"$json_args")
      _ZORACLE_ARG_OLD_TEXT=$(_zoracle_jq -j '.old_text // ""' <<<"$json_args")
      _ZORACLE_ARG_NEW_TEXT=$(_zoracle_jq -j '.new_text // ""' <<<"$json_args")
      _zoracle_tool_patch_file
      ;;
    exec)
      _zoracle_tool_exec "$(_zoracle_jq -r '.command // ""' <<<"$json_args")"
      ;;
    sandbox)
      _zoracle_tool_sandbox "$(_zoracle_jq -r '.command // ""' <<<"$json_args")"
      ;;
    find)
      local _ZORACLE_TOOL_ARG_PATTERN _ZORACLE_TOOL_ARG_DIR
      _ZORACLE_TOOL_ARG_PATTERN=$(_zoracle_jq -r '.pattern // ""' <<<"$json_args")
      _ZORACLE_TOOL_ARG_DIR=$(_zoracle_jq -r '.dir // ""' <<<"$json_args")
      _zoracle_tool_find
      ;;
    grep)
      local _ZORACLE_TOOL_ARG_PATTERN _ZORACLE_TOOL_ARG_DIR
      _ZORACLE_TOOL_ARG_PATTERN=$(_zoracle_jq -r '.pattern // ""' <<<"$json_args")
      _ZORACLE_TOOL_ARG_DIR=$(_zoracle_jq -r '.dir // ""' <<<"$json_args")
      _zoracle_tool_grep
      ;;
    notify)
      local _ZORACLE_ARG_PLATFORM _ZORACLE_ARG_MESSAGE
      _ZORACLE_ARG_PLATFORM=$(_zoracle_jq -r '.platform // ""' <<<"$json_args")
      _ZORACLE_ARG_MESSAGE=$(_zoracle_jq -j '.message // ""' <<<"$json_args")
      _zoracle_tool_notify
      ;;
    *)
      printf 'ERROR: unknown tool "%s".\nAvailable tools: search, fetch, time, read_file, write_file, append_file, patch_file, exec, sandbox, find, grep, notify\n' "$tool_name"
      return 1
      ;;
  esac
}

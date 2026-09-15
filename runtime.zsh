#!/usr/bin/zsh
# Derived runtime state: constructed after all overrides

_zoracle_initialize_session() {

  typeset selected_root="${ZORACLE_WORKSPACE_ROOT:-$PWD}"

  if [[ ! -d "$selected_root" ]]; then
    printf 'zoracle: workspace root is not a directory: %s\n' \
      "$selected_root" >&2
    return 1
  fi

  typeset -g _ZORACLE_WORKSPACE_ROOT="${selected_root:A}"
  typeset -g _ZORACLE_MESSAGES_JSON='[]'
  typeset -g _ZORACLE_LLM_MODEL="${ZORACLE_LLM_MODEL}"
  typeset -g _ZORACLE_LAST_REQUEST_EPOCH_SECONDS=0
  typeset -g _ZORACLE_SESSION_STARTED_AT
  typeset -g _ZORACLE_SYSTEM_PROMPT

  _ZORACLE_SESSION_STARTED_AT="$(date '+%A, %B %d, %Y, %I:%M %p %Z')"

  _ZORACLE_SYSTEM_PROMPT="You are a helpful Zsh terminal assistant with file, shell, web, time, and messaging tools, invoked through native function calling (the request's \"tools\" API).

Current date and time (static, from session start): $_ZORACLE_SESSION_STARTED_AT

Workspace root: $_ZORACLE_WORKSPACE_ROOT — relative file paths resolve here.

Tool rules:
1. To use a tool, emit a function call whose arguments match its JSON schema exactly. Never invent parameters or extra keys.
2. You may batch several independent tool calls in one turn; for dependent calls, wait for each result first.
3. Results return as \"tool\" messages tied to your tool_call_id. Read them, then continue the task.
4. For code edits prefer read_file first, then patch_file with exact literal old/new text.
5. Once the results are enough, answer the user in plain text with no tool call.
6. If no tool is needed, just answer directly."
}
#!/usr/bin/env zsh
# ~/.zoracle/init.zsh
# Main Zoracle entrypoint. Intended to be sourced by an interactive zsh.

# Re-entry guard
[[ -n "${_ZORACLE_LOADED:-}" ]] && return 0

# Directory containing this sourced file
typeset -g ZORACLE_DIR="${${(%):-%N}:A:h}"

_zoracle_require_commands() {
  local -a required=(
    jq curl timeout date awk sed grep find stdbuf
  )
  local -a optional=(
    rg python docker lynx
  )
  local -a missing=()
  local -a absent=()
  local command_name

  for command_name in "${required[@]}"; do
    command -v "$command_name" >/dev/null 2>&1 ||
      missing+=("$command_name")
  done

  if (( ${#missing[@]} )); then
    printf '\033[1;31m[zoracle]\033[0m missing required commands: %s\n' \
      "${(j: :)missing}" >&2
    printf 'Hint: run from the UCRT64 shell:\n' >&2
    printf '  C:\\msys64\\msys2_shell.cmd -defterm -no-start -ucrt64 -shell zsh\n' >&2
    return 1
  fi

  for command_name in "${optional[@]}"; do
    command -v "$command_name" >/dev/null 2>&1 ||
      absent+=("$command_name")
  done

  if (( ${#absent[@]} )) &&
   [[ "${ZORACLE_SUPPRESS_OPTIONAL_WARNING:-false}" != true ]]; then
    printf '\033[2m[zoracle]\033[0m optional commands unavailable (\033[33mRemove this message by setting ZORACLE_SUPPRESS_OPTIONAL_WARNING=true\033[0m): %s\n' \
      "${(j: :)absent}." >&2
  fi
}

_zoracle_require_commands || return 1

# Application defaults
source "$ZORACLE_DIR/defaults.zsh" || return 1

# Optional private user configuration
if [[ -r "$ZORACLE_DIR/config.zsh" ]]; then
  source "$ZORACLE_DIR/config.zsh" || return 1
fi

source "$ZORACLE_DIR/runtime.zsh" || return 1

# Tool implementations
if [[ -d "$ZORACLE_DIR/tools" ]]; then
  for tool_file in "$ZORACLE_DIR"/tools/*.zsh(N); do
    source "$tool_file" || return 1
  done
fi

source "$ZORACLE_DIR/core.zsh" || return 1
source "$ZORACLE_DIR/agent.zsh" || return 1

zoracle() {
  if [[ "${_ZORACLE_MESSAGES_JSON:-[]}" == '[]' ]]; then
    _zoracle_initialize_session
  fi

  _zoracle_agent "$@"
}

typeset -g _ZORACLE_LOADED=1

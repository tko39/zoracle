#!/usr/bin/zsh
# ~/.zoracle/tools/shell.zsh — Terminal execution with stdout/stderr/exit capture

_zoracle_tool_exec() {
  local cmd="${*:-}"
  if [[ -z "$cmd" ]]; then
    printf 'Usage: exec <command>\n'
    return 1
  fi
  if [[ "${ZORACLE_EXEC_ENABLED:-0}" == 0 ]]; then
    printf 'ERROR: exec is disabled (ZORACLE_EXEC_ENABLED=0); use the sandbox tool or enable exec.\n'
    return 1
  fi
  if [[ ! -d "${_ZORACLE_WORKSPACE_ROOT:-}" ]]; then
    printf 'ERROR: ZORACLE_WORKSPACE_ROOT does not exist: %s\n' "${_ZORACLE_WORKSPACE_ROOT:-}"
    return 1
  fi

  local out rc
  out=$( cd -- "$_ZORACLE_WORKSPACE_ROOT" && timeout "$ZORACLE_SHELL_TIMEOUT_SECONDS" zsh -c "$cmd" 2>&1 )
  rc=$?

  local max="${ZORACLE_TOOL_OUTPUT_MAX_CHARS:-4000}"
  if (( ${#out} > max )); then
    out="${out[1,$max]}
[truncated]"
  fi

  if (( rc == 124 )); then
    printf 'exit_code=%d (TIMEOUT after %ss)\n--- output ---\n%s\n' "$rc" "$ZORACLE_SHELL_TIMEOUT_SECONDS" "$out"
  else
    printf 'exit_code=%d\n--- output ---\n%s\n' "$rc" "$out"
  fi
}

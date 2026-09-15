#!/usr/bin/zsh
# ~/.zoracle/tools/sandbox.zsh — Run untrusted commands inside an isolated
# Docker container (chroot/micro-VMs are not viable on a Windows host).
# Degrades gracefully (structured error + exec fallback hint) when Docker
# is absent or the daemon is unreachable.

_zoracle_tool_sandbox() {
  local cmd="${*:-}"
  if [[ -z "$cmd" ]]; then
    printf 'Usage: sandbox <command>\n'
    return 1
  fi
  if [[ "${ZORACLE_SANDBOX_ENABLED:-1}" == 0 ]]; then
    printf 'ERROR: sandbox is disabled (ZORACLE_SANDBOX_ENABLED=0); enable sandbox in config, or use exec only if the command is trusted.\n'
    return 1
  fi

  if ! command -v docker >/dev/null 2>&1; then
    printf 'SANDBOX UNAVAILABLE: docker is not installed on this host.\n'
    printf 'Fallback: use [TOOL: exec] if the code is trusted, or ask the user to install/start Docker.\n'
    return 1
  fi

  if ! timeout 10 docker info >/dev/null 2>&1; then
    printf 'SANDBOX UNAVAILABLE: docker daemon is not reachable (start Docker Desktop / dockerd).\n'
    printf 'Fallback: use [TOOL: exec] if the code is trusted.\n'
    return 1
  fi

  if [[ ! -d "${_ZORACLE_WORKSPACE_ROOT:-}" ]]; then
    printf 'ERROR: ZORACLE_WORKSPACE_ROOT does not exist: %s\n' "${_ZORACLE_WORKSPACE_ROOT:-}"
    return 1
  fi

  # Docker on Windows needs a Windows-style path for bind mounts
  local mnt="$_ZORACLE_WORKSPACE_ROOT"
  if command -v cygpath >/dev/null 2>&1; then
    mnt=$(cygpath -w -- "$_ZORACLE_WORKSPACE_ROOT")
  fi

  local out rc
  out=$(docker run --rm \
    -v "$mnt":/work \
    -w /work \
    --network "$ZORACLE_SANDBOX_NETWORK" \
    --memory 512m --cpus 1 \
    "$ZORACLE_SANDBOX_IMAGE" \
    sh -c "$cmd" 2>&1)
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

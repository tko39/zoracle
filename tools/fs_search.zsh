#!/usr/bin/zsh
# ~/.zoracle/tools/fs_search.zsh — Filesystem search (ripgrep primary, GNU fallbacks)

_zoracle_search_dir() {
  local raw="${1:-}"
  if [[ -z "$raw" ]]; then
    printf '%s' "$_ZORACLE_WORKSPACE_ROOT"
    return 0
  fi
  local p
  p=$(_zoracle_guard_path "$raw" 2>/dev/null)
  local grc=$?
  if (( grc )); then
    _zoracle_path_error "$raw" "$grc"
    return 1
  fi
  [[ -d "$p" ]] || { printf 'ERROR: not a directory: %s\n' "$p"; return 1; }
  printf '%s' "$p"
}

_zoracle_tool_grep() {
  local pattern raw_dir
  if [[ -n "${_ZORACLE_TOOL_ARG_PATTERN+x}" ]]; then
    # Native tool call: exact pattern/dir (spaces preserved)
    pattern="$_ZORACLE_TOOL_ARG_PATTERN"
    raw_dir="${_ZORACLE_TOOL_ARG_DIR:-}"
  else
    # Legacy positional form: <pattern> [dir]
    local input="${*:-}"
    [[ -n "$input" ]] || { printf 'Usage: grep <pattern> [dir]\n'; return 1; }

    local -a parts
    parts=(${(z)input})
    pattern="${parts[1]:-}"
    raw_dir="${parts[2]:-}"
  fi

  local dir
  dir=$(_zoracle_search_dir "$raw_dir") || return 1
  [[ -n "$pattern" ]] || { printf 'ERROR: empty pattern\n'; return 1; }

  local max="${ZORACLE_SEARCH_MAX_RESULTS:-50}"
  local out
  if command -v rg >/dev/null 2>&1; then
    out=$(rg --line-number --max-columns 200 --no-messages -e "$pattern" "$dir" 2>/dev/null | head -n "$max")
  else
    out=$(grep -rn -m 1 --exclude-dir={.git,node_modules,__pycache__,.venv} -- "$pattern" "$dir" 2>/dev/null | head -n "$max")
  fi

  # Empty output == no matches for both rg and grep
  if [[ -z "$out" ]]; then
    printf 'No matches for pattern: %s\n' "$pattern"
    return 0
  fi
  printf '%s\n' "$out"
  if [[ "$(printf '%s\n' "$out" | wc -l)" -ge "$max" ]]; then
    printf '\n[results capped at %d — narrow the pattern or search a subdirectory]\n' "$max"
  fi
}

_zoracle_tool_find() {
  local pattern raw_dir
  if [[ -n "${_ZORACLE_TOOL_ARG_PATTERN+x}" ]]; then
    # Native tool call: exact pattern/dir (spaces preserved)
    pattern="$_ZORACLE_TOOL_ARG_PATTERN"
    raw_dir="${_ZORACLE_TOOL_ARG_DIR:-}"
  else
    # Legacy positional form: <glob-pattern> [dir]
    local input="${*:-}"
    [[ -n "$input" ]] || { printf 'Usage: find <glob-pattern> [dir]\n'; return 1; }

    local -a parts
    parts=(${(z)input})
    pattern="${parts[1]:-}"
    raw_dir="${parts[2]:-}"
  fi

  local dir
  dir=$(_zoracle_search_dir "$raw_dir") || return 1
  [[ -n "$pattern" ]] || { printf 'ERROR: empty pattern\n'; return 1; }

  local max="${ZORACLE_SEARCH_MAX_RESULTS:-50}"
  local out
  out=$(find "$dir" \
    \( -name .git -o -name node_modules -o -name __pycache__ -o -name .venv \) -prune -o \
    -name "$pattern" -type f -print 2>/dev/null | head -n "$max")

  if [[ -z "$out" ]]; then
    printf 'No files matching: %s\n' "$pattern"
  else
    printf '%s\n' "$out"
    if [[ "$(printf '%s\n' "$out" | wc -l)" -ge "$max" ]]; then
      printf '\n[results capped at %d]\n' "$max"
    fi
  fi
}

#!/usr/bin/zsh
# ~/.zoracle/tools/files.zsh — File operations (read/write/append/patch)
# All paths are jailed to _ZORACLE_WORKSPACE_ROOT.

# Resolve a tool path argument to an absolute path inside _ZORACLE_WORKSPACE_ROOT.
# rc 0 = ok (prints resolved path); rc 2 = outside root; rc 1/3 = invalid.
_zoracle_guard_path() {
  local raw="${1:-}"
  [[ -n "$raw" ]] || return 3
  local full="$raw"
  [[ "$full" == /* ]] || full="$_ZORACLE_WORKSPACE_ROOT/$full"
  local resolved root
  resolved=$(realpath -m -- "$full" 2>/dev/null) || return 1
  root=$(realpath -m -- "$_ZORACLE_WORKSPACE_ROOT" 2>/dev/null) || return 1
  [[ "$resolved" == "$root" || "$resolved" == "$root"/* ]] || return 2
  printf '%s' "$resolved"
}

_zoracle_path_error() {
  local raw="$1" code="$2"
  case "$code" in
    2) printf 'ERROR: path escapes workspace root (%s): %s\n' "$_ZORACLE_WORKSPACE_ROOT" "$raw" ;;
    *) printf 'ERROR: invalid path: %s\n' "$raw" ;;
  esac
}

# Decode literal \n and \t escapes emitted by the model.
# NOTE: $'\n' is NOT expanded inside double quotes, so build via variables.
_zoracle_decode_escapes() {
  local s="$1"
  local nl=$'\n' tab=$'\t'
  s="${s//\\t/$tab}"
  s="${s//\\n/$nl}"
  printf '%s' "$s"
}

_zoracle_tool_read_file() {
  local raw max_lines
  if [[ -n "${_ZORACLE_ARG_PATH+x}" ]]; then
    # Native tool call: exact path + optional line limit
    raw="$_ZORACLE_ARG_PATH"
    max_lines="${_ZORACLE_ARG_MAX_LINES:-400}"
  else
    # Legacy positional form: <path> [max_lines]
    local -a parts
    parts=(${=1})
    raw="${parts[1]:-}"
    max_lines="${parts[2]:-400}"
  fi
  [[ "$max_lines" == <-> ]] || max_lines=400

  local p
  p=$(_zoracle_guard_path "$raw")
  local grc=$?
  (( grc )) && { _zoracle_path_error "$raw" "$grc"; return 1; }

  [[ -f "$p" ]] || { printf 'ERROR: file not found: %s\n' "$p"; return 1; }
  [[ -r "$p" ]] || { printf 'ERROR: file not readable: %s\n' "$p"; return 1; }
  [[ -s "$p" ]] || { printf 'OK: file exists but is empty: %s\n' "$p"; return 0; }
  if head -c 8192 -- "$p" 2>/dev/null | od -An -tx1 2>/dev/null | grep -q ' 00'; then
    printf 'ERROR: appears to be a binary file: %s\n' "$p"
    return 1
  fi

  local total
  total=$(wc -l < "$p")
  awk '{ printf "%6d| %s\n", NR, $0 }' "$p" | cut -c 1-500 | head -n "$max_lines"
  if (( total > max_lines )); then
    printf '\n[showing lines 1-%d of %d total lines — raise the limit or use grep]\n' "$max_lines" "$total"
  fi
}

_zoracle_tool_write_file() {
  local raw content
  if [[ -n "${_ZORACLE_ARG_PATH+x}" ]]; then
    # Native tool call: exact content, no escape decoding
    raw="$_ZORACLE_ARG_PATH"
    content="$_ZORACLE_ARG_CONTENT"
  else
    # Legacy positional form: <path> <text> (\n decoded as newline)
    raw="${1%%[[:space:]]*}"
    content="${1#"$raw"}"
    content="${content#"${content%%[![:space:]]*}"}"
    content=$(_zoracle_decode_escapes "$content")
  fi
  [[ -n "$raw" ]] || { printf 'Usage: write_file <path> <text> (\\n = newline)\n'; return 1; }

  local p
  p=$(_zoracle_guard_path "$raw")
  local grc=$?
  (( grc )) && { _zoracle_path_error "$raw" "$grc"; return 1; }

  [[ "$content" != *$'\n' ]] && content+=$'\n'

  local dir="${p:h}"
  mkdir -p -- "$dir" 2>/dev/null || { printf 'ERROR: cannot create directory: %s\n' "$dir"; return 1; }
  local tmp
  tmp=$(mktemp "$dir/.zoracle-tmp.XXXXXX" 2>/dev/null) \
    || { printf 'ERROR: mktemp failed in %s\n' "$dir"; return 1; }

  if printf '%s' "$content" > "$tmp" && mv -f -- "$tmp" "$p"; then
    printf 'OK: wrote %s (%d bytes)\n' "$p" "$(wc -c < "$p")"
  else
    rm -f -- "$tmp" 2>/dev/null
    printf 'ERROR: write failed: %s\n' "$p"
    return 1
  fi
}

_zoracle_tool_append_file() {
  local raw content
  if [[ -n "${_ZORACLE_ARG_PATH+x}" ]]; then
    # Native tool call: exact content, no escape decoding
    raw="$_ZORACLE_ARG_PATH"
    content="$_ZORACLE_ARG_CONTENT"
  else
    # Legacy positional form: <path> <text> (\n decoded as newline)
    raw="${1%%[[:space:]]*}"
    content="${1#"$raw"}"
    content="${content#"${content%%[![:space:]]*}"}"
    content=$(_zoracle_decode_escapes "$content")
  fi
  [[ -n "$raw" ]] || { printf 'Usage: append_file <path> <text> (\\n = newline)\n'; return 1; }
  [[ -n "$content" ]] || { printf 'ERROR: nothing to append\n'; return 1; }

  local p
  p=$(_zoracle_guard_path "$raw")
  local grc=$?
  (( grc )) && { _zoracle_path_error "$raw" "$grc"; return 1; }

  local dir="${p:h}"
  mkdir -p -- "$dir" 2>/dev/null || { printf 'ERROR: cannot create directory: %s\n' "$dir"; return 1; }
  [[ -f "$p" ]] || : > "$p" 2>/dev/null || { printf 'ERROR: cannot create: %s\n' "$p"; return 1; }

  # Ensure previous content ends with a newline before appending
  if [[ -n "$(tail -c 1 -- "$p" 2>/dev/null)" ]]; then
    printf '\n' >> "$p"
  fi
  if printf '%s\n' "$content" >> "$p"; then
    printf 'OK: appended to %s (file now %d bytes)\n' "$p" "$(wc -c < "$p")"
  else
    printf 'ERROR: append failed: %s\n' "$p"
    return 1
  fi
}

_zoracle_tool_patch_file() {
  local raw old_text new_text
  if [[ -n "${_ZORACLE_ARG_PATH+x}" ]]; then
    # Native tool call: exact literal old/new text, no escape decoding
    raw="$_ZORACLE_ARG_PATH"
    old_text="$_ZORACLE_ARG_OLD_TEXT"
    new_text="$_ZORACLE_ARG_NEW_TEXT"
  else
    # Legacy positional form: <path> <old> @@ <new>
    raw="${1%%[[:space:]]*}"
    local rest="${1#"$raw"}"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    if [[ "$rest" != *" @@ "* ]]; then
      printf 'Usage: patch_file <path> <old_text> @@ <new_text> (literal replace, first occurrence)\n'
      return 1
    fi
    old_text="${rest%% @@ *}"
    new_text="${rest#*" @@ "}"
    old_text=$(_zoracle_decode_escapes "$old_text")
    new_text=$(_zoracle_decode_escapes "$new_text")
  fi
  [[ -n "$raw" ]] || { printf 'Usage: patch_file <path> <old> @@ <new>\n'; return 1; }
  [[ -n "$old_text" ]] || { printf 'ERROR: empty <old> text\n'; return 1; }

  local p
  p=$(_zoracle_guard_path "$raw")
  local grc=$?
  (( grc )) && { _zoracle_path_error "$raw" "$grc"; return 1; }
  [[ -f "$p" ]] || { printf 'ERROR: file not found: %s\n' "$p"; return 1; }

  _ZORACLE_PATCH_FILE="$p" \
  _ZORACLE_PATCH_OLD="$old_text" \
  _ZORACLE_PATCH_NEW="$new_text" \
  python - <<'PY'
import os, sys
p = os.environ["_ZORACLE_PATCH_FILE"]
old = os.environ["_ZORACLE_PATCH_OLD"]
new = os.environ["_ZORACLE_PATCH_NEW"]
try:
    with open(p, encoding="utf-8", errors="surrogateescape") as f:
        data = f.read()
except OSError as e:
    print("ERROR: cannot read %s: %s" % (p, e))
    sys.exit(1)
count = data.count(old)
if count == 0:
    print("ERROR: old text not found in file (must match literally and exactly)")
    sys.exit(4)
data = data.replace(old, new, 1)
try:
    with open(p, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(data)
except OSError as e:
    print("ERROR: cannot write %s: %s" % (p, e))
    sys.exit(1)
print("OK: patched first of %d occurrence(s) in %s" % (count, p))
PY
  local prc=$?
  return "$prc"
}

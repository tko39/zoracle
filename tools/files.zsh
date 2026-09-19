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
  awk '{ printf "%6d|%s\n", NR, $0 }' "$p" | cut -c 1-500 | head -n "$max_lines"
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
  # Append content as-is, ensuring exactly one trailing newline (the file
  # should end with a newline) without doubling an existing one.
  local arc=0
  if [[ "$content" == *$'\n' ]]; then
    printf '%s' "$content" >> "$p" || arc=$?
  else
    printf '%s\n' "$content" >> "$p" || arc=$?
  fi
  if (( arc != 0 )); then
    printf 'ERROR: append failed: %s\n' "$p"
    return 1
  fi
  printf 'OK: appended to %s (file now %d bytes)\n' "$p" "$(wc -c < "$p")"
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

  # Pass <old>/<new> to Python through temp files: immune to Windows
  # env-var size limits and newline munging, and keeps exact bytes intact.
  local dir="${p:h}"
  local tmpdir
  tmpdir=$(mktemp -d "$dir/.zoracle-patch.XXXXXX" 2>/dev/null) \
    || { printf 'ERROR: mktemp failed in %s\n' "$dir"; return 1; }
  if ! printf '%s' "$old_text" > "$tmpdir/old" 2>/dev/null \
     || ! printf '%s' "$new_text" > "$tmpdir/new" 2>/dev/null; then
    rm -rf -- "$tmpdir"
    printf 'ERROR: cannot stage patch text\n'
    return 1
  fi

  python - "$p" "$tmpdir/old" "$tmpdir/new" <<'PY'
import sys

p, oldf, newf = sys.argv[1:4]


def lead_spaces(s):
    n = 0
    while n < len(s) and s[n] == " ":
        n += 1
    return n


def diagnose(norm, old):
    """Best-effort explanation of why a literal match failed."""
    old_lines = old.split("\n")
    file_lines = norm.split("\n")
    n = len(old_lines)
    anchor = old_lines[0].strip()
    starts = []
    for i, ln in enumerate(file_lines):
        match = (ln.strip() == anchor) if anchor else (ln == old_lines[0])
        if match:
            starts.append(i)
            if len(starts) >= 5:
                break
    best = None  # (mismatches, start line, sample diffs)
    for i in starts:
        block = file_lines[i:i + n]
        mism, sample = 0, []
        for k in range(min(n, len(block))):
            a, b = old_lines[k], block[k]
            if a != b:
                mism += 1
                if len(sample) < 4:
                    sample.append((k + 1, a, b))
        if best is None or mism < best[0]:
            best = (mism, i, sample)
    if best is not None:
        mism, i, sample = best
        covered = min(n, len(file_lines[i:i + n]))
        print("  closest match: file line %d (%d of %d line(s) differ exactly)"
              % (i + 1, mism, covered))
        for (k, a, b) in sample:
            if a.lstrip(" ") == b.lstrip(" "):
                print("    line %d: leading spaces differ: <old>=%d, file=%d"
                      % (k, lead_spaces(a), lead_spaces(b)))
                print("      <old> |" + "+" * lead_spaces(a) + a.lstrip(" ")[:80])
                print("      file  |" + "+" * lead_spaces(b) + b.lstrip(" ")[:80])
            elif a.rstrip() == b.rstrip():
                print("    line %d: trailing whitespace differs" % k)
                print("      <old> |" + a[:100] + "|")
                print("      file  |" + b[:100] + "|")
            else:
                print("    line %d: text differs" % k)
                print("      <old> |" + a[:100] + "|")
                print("      file  |" + b[:100] + "|")
    else:
        print("  no file line matches even the first line of <old>.")
    print("  patch_file replaces exact literal text only - every space, tab and newline counts.")
    print("  retry with a smaller <old> chunk copied verbatim from the read_file output.")


try:
    with open(oldf, "rb") as fh:
        old = fh.read().decode("utf-8", "surrogateescape")
    with open(newf, "rb") as fh:
        new = fh.read().decode("utf-8", "surrogateescape")
except OSError as e:
    print("ERROR: cannot read staged patch text: %s" % e)
    sys.exit(1)

try:
    with open(p, "r", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        data = fh.read()
except OSError as e:
    print("ERROR: cannot read %s: %s" % (p, e))
    sys.exit(1)

# Work on a single newline flavor, remember which one the file uses so
# the write-back preserves it (avoids accidental LF<->CRLF conversion
# when Python's os.linesep disagrees with the file's line endings).
eol = "\r\n" if "\r\n" in data else "\n"
norm = data.replace("\r\n", "\n")
old_n = old.replace("\r\n", "\n")
new_n = new.replace("\r\n", "\n")

count = norm.count(old_n)
if count == 0:
    print("ERROR: old text not found in file (must match literally and exactly)")
    diagnose(norm, old_n)
    sys.exit(4)

norm = norm.replace(old_n, new_n, 1)
data = norm.replace("\n", eol)

try:
    with open(p, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write(data)
except OSError as e:
    print("ERROR: cannot write %s: %s" % (p, e))
    sys.exit(1)
print("OK: patched first of %d occurrence(s) in %s" % (count, p))
PY
  local prc=$?
  rm -rf -- "$tmpdir" 2>/dev/null
  return "$prc"
}

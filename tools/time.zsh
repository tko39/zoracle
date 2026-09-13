#!/usr/bin/zsh
# ~/.zoracle/tools/time.zsh — Temporal grounding & relative date calculations

_zoracle_tool_time() {
  local input="${1:-}"
  local -a parts
  parts=(${=input})
  local sub="${parts[1]:-}"
  local fmt='+%A, %B %d, %Y, %I:%M %p %Z'

  if [[ -z "$sub" || "$sub" == -h || "$sub" == --help || "$sub" == help ]]; then
    printf 'Usage: time now | time <+offset> | time <epoch> | time diff <epoch1> <epoch2>\n'
    printf 'Offsets are GNU date relative items: "+2 hours", "-3d", "+90 minutes", "tomorrow".\n'
    return 1
  fi

  case "$sub" in
    now)
      printf 'LOCAL:    %s\n' "$(date "$fmt")"
      printf 'EPOCH:    %s\n' "$(date +%s)"
      printf 'UTC:      %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S')"
      ;;
    diff)
      local a="${parts[2]:-}" b="${parts[3]:-}"
      if [[ "$a" == <-> && "$b" == <-> ]]; then
        local delta=$(( b - a ))
        local dur=$(( delta < 0 ? -delta : delta ))
        local days=$(( dur / 86400 ))
        local rem=$(( dur % 86400 ))
        printf 'DELTA:    %d seconds\nDURATION: %dd %dh %dm %ds\n' \
          "$delta" "$days" $(( rem / 3600 )) $(( (rem % 3600) / 60 )) $(( rem % 60 ))
      else
        printf 'ERROR: diff needs two integer epochs. Example: time diff 1789145737 1789155737\n'
        return 1
      fi
      ;;
    *)
      if [[ "$sub" == <-> && ${#parts[@]} -eq 1 ]]; then
        local human
        human=$(date -d "@$sub" "$fmt" 2>/dev/null) \
          || { printf 'ERROR: invalid epoch: %s\n' "$sub"; return 1; }
        printf 'EPOCH:    %s\nREADABLE: %s\n' "$sub" "$human"
      else
        local spec="${parts[*]}"
        local readable epoch
        readable=$(date -d "$spec" "$fmt" 2>/dev/null) \
          || { printf 'ERROR: cannot parse time spec: %s\n' "$spec"; return 1; }
        epoch=$(date -d "$spec" '+%s' 2>/dev/null)
        printf 'SPEC:     %s\nREADABLE: %s\nEPOCH:    %s\n' "$spec" "$readable" "$epoch"
      fi
      ;;
  esac
}

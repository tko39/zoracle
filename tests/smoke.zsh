#!/usr/bin/zsh
# ~/.zoracle/tests/smoke.zsh — Function-level smoke tests for the agent toolchain.
# Run from the UCRT64 shell:
#   C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -shell zsh -c '~/.zoracle/tests/smoke.zsh'
# Network-dependent tools (search/fetch/notify) are tested for graceful
# failure only — no API keys required.

emulate -L zsh
setopt no_aliases 2>/dev/null

ZORACLE_HOME="$HOME/.zoracle"
PASS=0
FAIL=0

t_ok() {   # t_ok <label> <rc> — rc 0 expected
  if (( $2 == 0 )); then (( PASS++ )); printf '  \033[32mPASS\033[0m %s\n' "$1"
  else (( FAIL++ )); printf '  \033[1;31mFAIL\033[0m %s (rc=%d)\n' "$1" "$2"; fi
}
t_fail() { # t_fail <label> <rc> — non-zero rc expected
  if (( $2 != 0 )); then (( PASS++ )); printf '  \033[32mPASS\033[0m %s\n' "$1"
  else (( FAIL++ )); printf '  \033[1;31mFAIL\033[0m %s (expected failure, rc=0)\n' "$1"; fi
}
t_contains() { # t_contains <label> <haystack> <needle>
  if [[ "$2" == *"$3"* ]]; then (( PASS++ )); printf '  \033[32mPASS\033[0m %s\n' "$1"
  else (( FAIL++ )); printf '  \033[1;31mFAIL\033[0m %s (missing: %s)\n' "$1" "$3"; fi
}

printf '\033[1m=== zoracle toolchain smoke tests ===\033[0m\n'

# ---------- Boot the toolchain with an isolated workspace root ----------
WORK="$(mktemp -d)"
export ZORACLE_WORKSPACE_ROOT="$WORK"
source "$ZORACLE_HOME/init.zsh" || { printf 'FATAL: init.zsh failed to load\n'; exit 1; }
_zoracle_initialize_session

# ---------- 1. Time tools ----------
printf '\n\033[1m[time]\033[0m\n'
out=$(_zoracle_tool_time now)
t_ok "time now" $?
t_contains "time now shows EPOCH" "$out" "EPOCH:"
t_contains "time now shows readable date" "$out" "2026"
out=$(_zoracle_tool_time "+2 hours")
t_ok "time +2 hours (GNU relative)" $?
t_contains "relative shows EPOCH" "$out" "EPOCH:"
out=$(_zoracle_tool_time 1789145737)
t_contains "epoch->readable" "$out" "READABLE:"
out=$(_zoracle_tool_time "diff 1000000000 1000086400")
t_contains "diff shows 86400s as 1d" "$out" "1d 0h 0m 0s"
_zoracle_tool_time 'blorp zum' >/dev/null 2>&1; t_fail "time with garbage spec" $?

# ---------- 2. File tools ----------
printf '\n\033[1m[files]\033[0m\n'
out=$(_zoracle_tool_write_file "notes.txt hello world\nsecond line")
echo "TKTK $out"
t_contains "write_file reports OK" "$out" "OK: wrote"
out=$(_zoracle_tool_read_file "notes.txt")
t_ok "read_file" $?
t_contains "read_file shows numbered line 2" "$out" "2| second line"
t_contains "read_file shows line 1" "$out" "hello world"
out=$(_zoracle_tool_append_file "notes.txt third line")
t_contains "append_file reports OK" "$out" "OK: appended"
out=$(_zoracle_tool_read_file "notes.txt")
t_contains "append visible" "$out" "3| third line"
t_contains "append kept newline between lines" "$out" "second line"
_zoracle_tool_read_file '../../etc/passwd' >/dev/null 2>&1
t_fail "path escaping root rejected" $?
_zoracle_tool_read_file '/etc/passwd' >/dev/null 2>&1
t_fail "absolute path outside root rejected" $?
_zoracle_tool_read_file 'nope.txt' >/dev/null 2>&1
t_fail "read missing file errors" $?
_zoracle_tool_write_file "code.py value = a.b(1) + 2\nprint(value)\n" >/dev/null
out=$(_zoracle_tool_patch_file "code.py a.b(1) + 2 @@ c.d(9) * 7")
t_contains "patch_file with metachars reports OK" "$out" "OK: patched"
out=$(_zoracle_tool_read_file "code.py")
t_contains "patched content correct" "$out" "c.d(9) * 7"
_zoracle_tool_patch_file "code.py NOT PRESENT @@ x" >/dev/null 2>&1
t_fail "patch_file old-not-found errors" $?
out=$(_zoracle_tool_write_file "sub/dir/new.txt deep")
t_contains "write creates parent dirs" "$out" "OK: wrote"

# ---------- 3. exec ----------
printf '\n\033[1m[exec]\033[0m\n'
ZORACLE_EXEC_ENABLED=1
out=$(_zoracle_tool_exec "echo hi && pwd")
t_contains "exec captures stdout" "$out" "hi"
t_contains "exec runs in workspace root" "$out" "$WORK"
t_contains "exec reports exit_code=0" "$out" "exit_code=0"
out=$(_zoracle_tool_exec "grep zzz /dev/null; exit 3")
t_contains "exec reports non-zero exit code" "$out" "exit_code=3"
out=$(_zoracle_tool_exec "sleep 60")
t_contains "exec timeout honored" "$out" "TIMEOUT"
out=$(_zoracle_tool_exec "echo err >&2")
t_contains "exec merges stderr into output" "$out" "err"
ZORACLE_EXEC_ENABLED=0
out=$(_zoracle_tool_exec "echo nope")
t_contains "exec kill-switch works" "$out" "disabled"
ZORACLE_EXEC_ENABLED=1

# ---------- 4. fs_search ----------
printf '\n\033[1m[fs_search]\033[0m\n'
_zoracle_tool_write_file "needle.txt the SECRET_TOKEN is here\n" >/dev/null
_zoracle_tool_write_file "other.txt nothing to see\n" >/dev/null
out=$(_zoracle_tool_grep "SECRET_TOKEN")
t_contains "grep finds content (ripgrep path)" "$out" "SECRET_TOKEN is here"
out=$(_zoracle_tool_find "*.txt")
t_contains "find locates files by glob" "$out" "needle.txt"
out=$(_zoracle_tool_grep "SECRET_TOKEN" "sub")
t_contains "grep restricted to subdir finds nothing" "$out" "No matches"

# ---------- 5. sandbox (docker expected absent) ----------
printf '\n\033[1m[sandbox]\033[0m\n'
out=$(_zoracle_tool_sandbox "echo hi")
if command -v docker >/dev/null 2>&1; then
  t_contains "sandbox ran or degraded cleanly" "$out" "exit_code"
else
  t_contains "sandbox degrades without docker" "$out" "SANDBOX UNAVAILABLE"
fi
ZORACLE_SANDBOX_ENABLED=0
out=$(_zoracle_tool_sandbox "echo nope")
t_contains "sandbox kill-switch works" "$out" "disabled"
ZORACLE_SANDBOX_ENABLED=1

# ---------- 6. router ----------
printf '\n\033[1m[router]\033[0m\n'
out=$(_zoracle_execute_tool time "now")
t_ok "router routes 'time'" $?
out=$(_zoracle_execute_tool totally_bogus "x")
t_contains "unknown tool lists catalog" "$out" "Available tools:"
out=$(_zoracle_execute_tool grep "SECRET_TOKEN")
t_contains "router routes 'grep' alias" "$out" "SECRET_TOKEN"

# ---------- 6b. JSON router (native function calls) ----------
printf '\n\033[1m[json router]\033[0m\n'
schema=$(_zoracle_get_tools_json)
t_ok "tools schema is a JSON array" $?
t_contains "schema lists grep" "$schema" "grep"
t_contains "schema lists sandbox" "$schema" "sandbox"
ZORACLE_EXEC_ENABLED=0
schema=$(_zoracle_get_tools_json)
[[ "$schema" == *"exec"* ]] && { (( FAIL++ )); printf '  \033[1;31mFAIL\033[0m schema omits exec when disabled (found exec)\n'; } || { (( PASS++ )); printf '  \033[32mPASS\033[0m schema omits exec when disabled\n'; }
ZORACLE_EXEC_ENABLED=1
schema=$(_zoracle_get_tools_json)
t_contains "schema includes exec when enabled" "$schema" "exec"
ZORACLE_SANDBOX_ENABLED=0
schema=$(_zoracle_get_tools_json)
[[ "$schema" == *"sandbox"* ]] && { (( FAIL++ )); printf '  \033[1;31mFAIL\033[0m schema omits sandbox when disabled (found sandbox)\n'; } || { (( PASS++ )); printf '  \033[32mPASS\033[0m schema omits sandbox when disabled\n'; }
ZORACLE_SANDBOX_ENABLED=1
schema=$(_zoracle_get_tools_json)
t_contains "schema includes sandbox when enabled" "$schema" "sandbox"
out=$(_zoracle_execute_tool_json time '{"spec":"now"}')
t_contains "json time now" "$out" "EPOCH:"
out=$(_zoracle_execute_tool_json write_file '{"path":"json_test.txt","content":"hello world"}')
t_contains "json write_file ok" "$out" "OK: wrote"
out=$(_zoracle_execute_tool_json read_file '{"path":"json_test.txt"}')
t_contains "json read preserves inner double space" "$out" "hello world"
out=$(_zoracle_execute_tool_json append_file '{"path":"json_test.txt","content":"\nsecond line"}')
t_contains "json append ok" "$out" "OK: appended"
out=$(_zoracle_execute_tool_json read_file '{"path":"json_test.txt"}')
t_contains "json append visible" "$out" "second line"
out=$(_zoracle_execute_tool_json write_file '{"path":"leading.txt","content":"  indented"}')
t_contains "json write preserves leading spaces" "$out" "OK: wrote"
out=$(_zoracle_execute_tool_json read_file '{"path":"leading.txt"}')
t_contains "json read shows leading spaces" "$out" "  indented"
out=$(_zoracle_execute_tool_json write_file '{"path":"multi.py","content":"def foo():\n    return 1\n"}')
out=$(_zoracle_execute_tool_json patch_file '{"path":"multi.py","old_text":"return 1","new_text":"return 2"}')
t_contains "json patch_file ok" "$out" "OK: patched"
out=$(_zoracle_execute_tool_json read_file '{"path":"multi.py"}')
t_contains "json patch applied" "$out" "return 2"
out=$(_zoracle_execute_tool_json grep '{"pattern":"SECRET_TOKEN is here"}')
t_contains "json grep pattern with spaces" "$out" "SECRET_TOKEN is here"
out=$(_zoracle_execute_tool_json bogus_tool '{"x":1}')
t_contains "json unknown tool errors" "$out" "unknown tool"
out=$(_zoracle_execute_tool_json time '"just a string"')
t_contains "json non-object args rejected" "$out" "must be a JSON object"
out=$(_zoracle_execute_tool_json notify '{"platform":"slack","message":"hello"}')
t_contains "json notify degrades without key" "$out" "SLACK_WEBHOOK_URL is not set"

# ---------- 7. Agent loop (stubbed LLM, native tool calls) ----------
printf '\n\033[1m[agent loop]\033[0m\n'
_zoracle_llm_turn() {
  local no_reasoning=false
  local OPTIND=1 option
  while getopts ':n' option; do case "$option" in n) no_reasoning=true ;; esac; done
  shift $((OPTIND - 1))
  local prompt="$*"
  # Mirror core.zsh: inject the system message on an empty history
  if [[ "$_ZORACLE_MESSAGES_JSON" == "[]" ]]; then
    _ZORACLE_MESSAGES_JSON=$(jq -c --arg s "$_ZORACLE_SYSTEM_PROMPT" '[{role:"system",content:$s}]' <<<"$_ZORACLE_MESSAGES_JSON")
  fi
  if (( ${#prompt} )); then
    _ZORACLE_MESSAGES_JSON=$(jq -c --arg p "$prompt" '. + [{role:"user",content:$p}]' <<<"$_ZORACLE_MESSAGES_JSON")
  fi
  local step="${_ASKAI_STUB_STEP:-0}"
  case "$step" in
    0)
      # First call: return a native tool call for time
      _ZORACLE_MESSAGES_JSON=$(jq -c '. + [{role:"assistant",content:"",tool_calls:[{id:"call_t1",type:"function",function:{name:"time",arguments:"{\"spec\":\"now\"}"}}]}]' <<<"$_ZORACLE_MESSAGES_JSON")
      printf '→ tool: time({"spec":"now"})'
      ;;
    *)
      # Second call: return final answer (no tool calls)
      _ZORACLE_MESSAGES_JSON=$(jq -c '. + [{role:"assistant",content:"Final: the time is shown above."}]' <<<"$_ZORACLE_MESSAGES_JSON")
      printf 'Final: the time is shown above.'
      ;;
  esac
  _ASKAI_STUB_STEP=$(( step + 1 ))
  return 0
}
typeset -g _ASKAI_STUB_STEP=0
_ZORACLE_MESSAGES_JSON='[]'
_zoracle_agent "what time is it?" >/dev/null 2>&1
t_ok "agent loop completes" $?
last=$(jq -r 'map(select(.role=="assistant")) | last | .content' <<<"$_ZORACLE_MESSAGES_JSON")
t_contains "loop reached final answer" "$last" "Final: the time is shown above."
n_tool_results=$(jq '[.[] | select(.role=="tool")] | length' <<<"$_ZORACLE_MESSAGES_JSON")
t_contains "tool result recorded" "$n_tool_results" "1"
n_msgs=$(jq 'length' <<<"$_ZORACLE_MESSAGES_JSON")
t_contains "history: sys+user+assistant+tool+assistant = 5 messages" "$n_msgs" "5"

# ---------- 8. Comms (graceful failure without keys) ----------
printf '\n\033[1m[comms]\033[0m\n'
unset SLACK_WEBHOOK_URL
out=$(_zoracle_tool_notify "slack" "hello")
t_contains "notify without key degrades cleanly" "$out" "SLACK_WEBHOOK_URL is not set"

# ---------- cleanup ----------
rm -rf "$WORK"
printf '\n\033[1mResult: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
(( FAIL == 0 )) || exit 1

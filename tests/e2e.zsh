#!/usr/bin/zsh
# ~/.zoracle/tests/e2e.zsh — End-to-end test of native tool calling:
# core _zoracle_llm_turn must advertise tools via the request "tools" key, notice the
# model's streamed tool_calls, and the agent loop must execute them and feed
# results back as role:"tool" messages. Runs against tests/mock_llm.py.
# Run from the UCRT64 shell:
#   C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -shell zsh -c '~/.zoracle/tests/e2e.zsh'

emulate -L zsh

ZORACLE_HOME="$HOME/.zoracle"
PASS=0
FAIL=0
WORK=""
MOCK_PID=""

cleanup() {
  [[ -n "$MOCK_PID" ]] && kill "$MOCK_PID" 2>/dev/null
  [[ -n "$WORK" ]] && rm -rf "$WORK"
}
trap cleanup EXIT

t_ok() {
  if (( $2 == 0 )); then (( PASS++ )); printf '  \033[32mPASS\033[0m %s\n' "$1"
  else (( FAIL++ )); printf '  \033[1;31mFAIL\033[0m %s (rc=%d)\n' "$1" "$2"; fi
}
t_contains() {
  if [[ "$2" == *"$3"* ]]; then (( PASS++ )); printf '  \033[32mPASS\033[0m %s\n' "$1"
  else (( FAIL++ )); printf '  \033[1;31mFAIL\033[0m %s (missing: %s)\n' "$1" "$3"; fi
}
t_fail() { # t_fail <label> <rc> — non-zero rc expected
  if (( $2 != 0 )); then (( PASS++ )); printf '  \033[32mPASS\033[0m %s\n' "$1"
  else (( FAIL++ )); printf '  \033[1;31mFAIL\033[0m %s (expected failure, rc=0)\n' "$1"; fi
}
t_not_contains() { # t_not_contains <label> <haystack> <needle-that-must-be-absent>
  if [[ "$2" != *"$3"* ]]; then (( PASS++ )); printf '  \033[32mPASS\033[0m %s\n' "$1"
  else (( FAIL++ )); printf '  \033[1;31mFAIL\033[0m %s (unexpected: %s)\n' "$1" "$3"; fi
}

if ! command -v python >/dev/null 2>&1; then
  printf '\033[1;33m[skip]\033[0m python not available; e2e test skipped\n'
  exit 0
fi

WORK="$(mktemp -d)"
export ZORACLE_WORKSPACE_ROOT="$WORK"
export MOCK_STATE_DIR="$WORK/mock"
mkdir -p "$MOCK_STATE_DIR"

printf '\033[1m=== zoracle native tool-calling e2e (mock server) ===\033[0m\n'

python "$ZORACLE_HOME/tests/mock_llm.py" &
MOCK_PID=$!

# Wait for the mock to publish its port
PORT=""
for i in {1..50}; do
  if [[ -s "$MOCK_STATE_DIR/port" ]]; then PORT=$(<"$MOCK_STATE_DIR/port"); break; fi
  sleep 0.1
done
if [[ -z "$PORT" ]]; then
  printf '\033[1;31mFAIL\033[0m mock server did not start\n'
  exit 1
fi

source "$ZORACLE_HOME/init.zsh" || exit 1
export ZORACLE_LLM_BASE_URL="http://127.0.0.1:$PORT"
export ZORACLE_LLM_MODEL="mock-model"
export ZORACLE_LLM_API_KEY="test"

_zoracle_initialize_session

reset_mock() {
  rm -f "$MOCK_STATE_DIR"/request_*.json(N) "$MOCK_STATE_DIR/request_count"
}

# ---------- 1. core _zoracle_llm_turn: tools on the request + tool_calls noticed ----------
printf '\n\033[1m[core]\033[0m\n'
_ZORACLE_MESSAGES_JSON='[]'
reset_mock
# NOTE: capture via file redirection, NOT $(...): command substitution
# runs the function in a subshell, which would throw away _zoracle_llm_turn's
# _ZORACLE_MESSAGES_JSON global update (the assertions below read that global).
_zoracle_llm_turn "What is the current weather in Tokyo?" >"$WORK/core.out"
out=$(<"$WORK/core.out")
t_contains "core streams a tool-call notice" "$out" "→ tool: time"

req0=$(cat "$MOCK_STATE_DIR/request_0.json" 2>/dev/null)
t_contains "request carries the tools key" "$req0" '"tools"'
t_contains "request advertises the time tool" "$req0" '"name":"time"'
t_contains "request advertises patch_file schema" "$req0" '"old_text"'
t_contains "request carries the session model" "$req0" '"model":"mock-model"'

last=$(jq -c 'map(select(.role=="assistant")) | last' <<<"$_ZORACLE_MESSAGES_JSON")
t_contains "assistant message carries tool_calls" "$last" '"tool_calls"'
t_contains "tool call id captured" "$last" '"call_e2e_1"'
t_contains "tool name captured" "$last" '"name":"time"'
tc_args=$(jq -r 'map(select(.role=="assistant")) | last | .tool_calls[0].function.arguments' <<<"$_ZORACLE_MESSAGES_JSON" 2>/dev/null)
t_contains "argument fragments assembled" "$tc_args" '{"spec":"now"}'

# ---------- 2. agent loop: execute + feed back ----------
printf '\n\033[1m[agent loop]\033[0m\n'
_ZORACLE_MESSAGES_JSON='[]'
reset_mock
_zoracle_agent "What time is it?" >"$WORK/agent.out"
a_rc=$?
out=$(<"$WORK/agent.out")
t_ok "agent loop completes" "$a_rc"

tool_msg=$(jq -c '[.[] | select(.role=="tool")] | last // empty' <<<"$_ZORACLE_MESSAGES_JSON")
t_contains "tool result recorded as role:tool" "$tool_msg" '"role":"tool"'
t_contains "tool result keyed by tool_call_id" "$tool_msg" '"tool_call_id":"call_e2e_1"'
tool_out=$(jq -r '[.[] | select(.role=="tool")] | last | .content' <<<"$_ZORACLE_MESSAGES_JSON" 2>/dev/null)
t_contains "tool result carries tool output" "$tool_out" "EPOCH:"

req1=$(cat "$MOCK_STATE_DIR/request_1.json" 2>/dev/null)
t_contains "follow-up request replays assistant tool_calls turn" "$req1" '"tool_calls"'
t_contains "follow-up request carries the tool result" "$req1" '"tool_call_id":"call_e2e_1"'

final=$(jq -r 'map(select(.role=="assistant")) | last | .content' <<<"$_ZORACLE_MESSAGES_JSON")
t_contains "loop reached final answer" "$final" "Final answer:"

# ---------- 3. error handling & CRLF regressions (bugs) ----------
printf '\n\033[1m[error handling]\033[0m\n'

# Bug 2 regression: on this Windows build raw `jq -r 'type'` emits
# "object\r", so the router guard used to reject every valid JSON object
# (and every tool call silently returned a schema error). A real tool's
# args object must now pass straight through.
out=$(_zoracle_execute_tool_json time '{"spec":"now"}'); rc=$?
t_ok "router accepts a valid JSON object (CRLF regression)" $rc
t_contains "target tool actually executed" "$out" "EPOCH:"
t_not_contains "no spurious schema-mismatch error" "$out" "must be a JSON object"

# The same guard must still reject a bare string argument.
out=$(_zoracle_execute_tool_json time '"now"'); rc=$?
t_fail "non-object args still rejected" $rc
t_contains "rejection message mentions the schema" "$out" "must be a JSON object"

# Unknown tool → non-empty error (guard no longer shadows the case branch).
out=$(_zoracle_execute_tool_json nope '{}'); rc=$?
t_fail "unknown tool errors" $rc
t_contains "unknown tool error text" "$out" "unknown tool"

# Bug 1 regression: the agent loop must surface the tool result to the user
# and must never hand the model an empty tool result on failure.
_ZORACLE_MESSAGES_JSON='[]'
reset_mock
_zoracle_agent "What time is it?" >"$WORK/agent2.out"
a_rc=$?
out=$(<"$WORK/agent2.out")
t_ok "agent loop completes (error handling run)" "$a_rc"
t_contains "agent displays the tool result to the user" "$out" "[Tool Result]"
tool_msg=$(jq -c '[.[] | select(.role=="tool")] | last // empty' <<<"$_ZORACLE_MESSAGES_JSON")
t_contains "recorded tool result is non-empty" "$tool_msg" '"content":"'
tool_content=$(jq -r '[.[] | select(.role=="tool")] | last | .content' <<<"$_ZORACLE_MESSAGES_JSON")
t_contains "recorded tool result carries real output" "$tool_content" "EPOCH:"

# ---------- 4. /v1/models listing (mock GET) ----------
printf '\n\033[1m[model list]\033[0m\n'
out=$(_zoracle_llm_list_models); ml_rc=$?
t_ok "model list fetches and parses" "$ml_rc"
t_contains "model list shows an advertised model" "$out" "mock-model-a"
t_contains "model list shows every model" "$out" "mock-model-b"
t_contains "model list marks the current model" "$out" "<- current"
t_contains "model list renders llama.cpp status" "$out" "[loaded]"

printf '\n\033[1mResult: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
(( FAIL == 0 )) || exit 1

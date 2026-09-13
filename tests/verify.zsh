#!/usr/bin/zsh
# Final end-to-end verification (simulates .zshrc sourcing + live network)
. ~/.zoracle/init.zsh
echo '--- load check ---'
type -w _zoracle_execute_tool _zoracle_tool_time _zoracle_tool_fetch_page _zoracle_tool_notify
echo '--- router via time ---'
_zoracle_execute_tool time now
echo '--- json router via time (native tool-call args) ---'
_zoracle_execute_tool_json time '{"spec": "now"}'
echo '--- live fetch (network; DNS unavailable offline) ---'
_zoracle_execute_tool fetch https://example.com | head -c 600
echo ''
echo '--- search without key (graceful) ---'
_zoracle_execute_tool search "test query"
echo '--- verify done ---'
exit 0

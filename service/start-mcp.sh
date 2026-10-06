#!/usr/bin/env bash
# Supervisor for the shared Playwright MCP server.
# Installed to ~/.config/playwright-mcp/start-mcp.sh by `shared-browser-mcp install`.
#
# - waits for the browser's CDP endpoint, then runs @playwright/mcp attached to it
# - if the browser disappears for PLAYWRIGHT_MCP_CDP_DOWN_GRACE seconds, stops MCP so that the next
#   start re-attaches cleanly (and re-resolves @latest)
# - once per PLAYWRIGHT_MCP_UPDATE_CHECK_INTERVAL runs `shared-browser-mcp check-updates`
# - while the browser is closed, activates a staged Chrome for Testing update
# - optionally serves ~/.config/playwright-mcp/status/ on PLAYWRIGHT_MCP_STATUS_PORT (127.0.0.1 only)
set -u

CONFIG_DIR="${SBM_CONFIG_DIR:-$HOME/.config/playwright-mcp}"
# shellcheck disable=SC1091
[ -f "$CONFIG_DIR/local.env" ] && . "$CONFIG_DIR/local.env"

export PLAYWRIGHT_CDP_URL="${PLAYWRIGHT_CDP_URL:-http://127.0.0.1:${PLAYWRIGHT_CDP_PORT:-9223}}"
export PLAYWRIGHT_MCP_HOST="${PLAYWRIGHT_MCP_HOST:-127.0.0.1}"
export PLAYWRIGHT_MCP_PORT="${PLAYWRIGHT_MCP_PORT:-8931}"
export PLAYWRIGHT_MCP_URL="${PLAYWRIGHT_MCP_URL:-http://localhost:${PLAYWRIGHT_MCP_PORT}}"
export PLAYWRIGHT_MCP_NPM_SPEC="${PLAYWRIGHT_MCP_NPM_SPEC:-@playwright/mcp@latest}"
GRACE="${PLAYWRIGHT_MCP_CDP_DOWN_GRACE:-30}"
CHECK_INTERVAL="${PLAYWRIGHT_MCP_UPDATE_CHECK_INTERVAL:-86400}"
STATUS_PORT="${PLAYWRIGHT_MCP_STATUS_PORT:-8932}"

TOOL="$(cat "$CONFIG_DIR/repo-path" 2>/dev/null)/shared-browser-mcp"
[ -x "$TOOL" ] || TOOL=""

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*"; }
cdp_up() { curl -sS -o /dev/null --max-time 1 "${PLAYWRIGHT_CDP_URL}/json/version" 2>/dev/null; }

if command -v bunx >/dev/null 2>&1; then launcher=bunx
elif command -v npx >/dev/null 2>&1; then launcher=npx
else log "Neither bunx nor npx found"; exit 1; fi

mcp_pid=""
status_pid=""
cleanup() {
  [ -n "$mcp_pid" ] && kill -TERM -- "-$mcp_pid" 2>/dev/null
  [ -n "$status_pid" ] && kill "$status_pid" 2>/dev/null
  exit 0
}
trap cleanup TERM INT

if [ "$STATUS_PORT" != 0 ] && command -v python3 >/dev/null 2>&1; then
  mkdir -p "$CONFIG_DIR/status"
  python3 -m http.server --bind 127.0.0.1 --directory "$CONFIG_DIR/status" "$STATUS_PORT" >/dev/null 2>&1 &
  status_pid=$!
fi

last_check=0
maybe_check_updates() {
  [ -n "$TOOL" ] || return 0
  local now; now=$(date +%s)
  [ $((now - last_check)) -ge "$CHECK_INTERVAL" ] || return 0
  last_check=$now
  ( "$TOOL" check-updates --quiet --notify --stage >>"$CONFIG_DIR/updates.log" 2>&1 ) &
}
activate_staged() { [ -n "$TOOL" ] && "$TOOL" activate-staged --quiet --notify >>"$CONFIG_DIR/updates.log" 2>&1; }

while true; do
  activated=0
  until cdp_up; do
    maybe_check_updates
    if [ "$activated" = 0 ]; then activate_staged; activated=1; fi
    sleep 2
  done

  log "browser reachable at ${PLAYWRIGHT_CDP_URL}; starting MCP (${PLAYWRIGHT_MCP_NPM_SPEC}) on ${PLAYWRIGHT_MCP_URL}"
  setsid "$launcher" -y "$PLAYWRIGHT_MCP_NPM_SPEC" \
    --cdp-endpoint "$PLAYWRIGHT_CDP_URL" \
    --host "$PLAYWRIGHT_MCP_HOST" \
    --port "$PLAYWRIGHT_MCP_PORT" \
    --caps devtools \
    --shared-browser-context &
  mcp_pid=$!

  down_since=0
  while kill -0 "$mcp_pid" 2>/dev/null; do
    sleep 5
    maybe_check_updates
    if cdp_up; then
      down_since=0
    else
      now=$(date +%s)
      [ "$down_since" = 0 ] && down_since=$now
      if [ $((now - down_since)) -ge "$GRACE" ]; then
        log "browser gone for ${GRACE}s; stopping MCP until it returns"
        kill -TERM -- "-$mcp_pid" 2>/dev/null
        wait "$mcp_pid" 2>/dev/null
        break
      fi
    fi
  done
  mcp_pid=""
  sleep 1
done

#!/usr/bin/env bash
# Linux (GNOME) branch. UNTESTED: derived from the manual steps in docs/manual-setup.md.
# Browser, profile and launcher all live under $HOME.

CFT_PLATFORM_KEY=linux64
case "$(uname -m)" in aarch64|arm64) CFT_PLATFORM_KEY=linux-arm64 ;; esac

plat_init() {
  need python3; need curl
  CFT_ROOT="$SBM_CONFIG_DIR/chrome-for-testing"
  CFT_EXE="$CFT_ROOT/current/chrome"
  PROFILE_DIR="$SBM_CONFIG_DIR/cft-profile"
  LAUNCHER="$HOME/.local/share/applications/browser-playwright-mcp.desktop"
  LAUNCHER_ARGS="--user-data-dir=${PROFILE_DIR} --remote-debugging-port=${PLAYWRIGHT_CDP_PORT} ${CFT_LAUNCH_FLAGS}"
  LAUNCHER_HINT="start \"Browser Playwright MCP\" from the applications menu"
}

plat_cft_current_version() { [ -L "$CFT_ROOT/current" ] && basename "$(readlink "$CFT_ROOT/current")"; }
plat_cft_versions() { ls -1 "$CFT_ROOT" 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+){3}$' || true; }
plat_cft_legacy_version() { return 1; }
plat_cft_migrate_legacy() { :; }
plat_cft_unpack() { # ZIP VERSION
  local tmp="$CFT_ROOT/.unpack-$2"; rm -rf "$tmp"; mkdir -p "$tmp"
  need unzip; unzip -q "$1" -d "$tmp"
  rm -rf "$CFT_ROOT/$2"; mv "$tmp"/chrome-linux* "$CFT_ROOT/$2"; rm -rf "$tmp"
}
plat_cft_activate() { [ -x "$CFT_ROOT/$1/chrome" ] || die "no chrome in $CFT_ROOT/$1"; ln -sfn "$CFT_ROOT/$1" "$CFT_ROOT/current"; }

launcher_content() {
  cat <<EOF
[Desktop Entry]
Name=Browser Playwright MCP
Type=Application
Terminal=false
Exec=${CFT_EXE} ${LAUNCHER_ARGS}
Icon=${CFT_ROOT}/current/product_logo_256.png
Categories=Development;
EOF
}
plat_launcher_check() {
  if [ ! -f "$LAUNCHER" ]; then report MISSING launcher "$LAUNCHER"
  elif ! diff -q "$LAUNCHER" <(launcher_content) >/dev/null; then report DRIFT launcher "$LAUNCHER differs from template"
  else report OK launcher "$LAUNCHER"; fi
}
plat_launcher_install() { mkdir -p "$(dirname "$LAUNCHER")"; launcher_content > "$LAUNCHER"; }

plat_service_check() {
  local unit="$HOME/.config/systemd/user/playwright-mcp.service"
  if [ ! -f "$unit" ]; then report MISSING service "$unit"
  elif ! diff -q "$unit" <(service_unit_content) >/dev/null; then report DRIFT service "unit file differs from template"
  elif [ "$(systemctl --user is-active playwright-mcp.service)" != active ]; then report DRIFT service "not active (run: systemctl --user start playwright-mcp.service)"
  else report OK service "systemd --user playwright-mcp.service active"; fi
}
plat_service_install() {
  mkdir -p "$HOME/.config/systemd/user"
  service_unit_content > "$HOME/.config/systemd/user/playwright-mcp.service"
  systemctl --user daemon-reload
  systemctl --user enable playwright-mcp.service >/dev/null 2>&1
  if [ "${1:-}" = restart ] || [ "$(systemctl --user is-active playwright-mcp.service)" != active ]; then
    systemctl --user restart playwright-mcp.service
  else
    log "service files updated; restart when no agent is using the browser: systemctl --user restart playwright-mcp.service"
  fi
}
plat_service_start_command() { echo "systemctl --user start playwright-mcp.service"; }

plat_notify() { command -v notify-send >/dev/null 2>&1 && notify-send "$1" "$2" || true; }

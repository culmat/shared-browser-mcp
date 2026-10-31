#!/usr/bin/env bash
# Linux (GNOME) branch. Tested on Ubuntu GNOME (with the DING desktop-icons extension).
# Browser, profile and launcher all live under $HOME. The launcher goes to the applications menu
# and, when a desktop folder exists, to the desktop as well (executable + gio-trusted, or GNOME
# refuses to launch it).

CFT_PLATFORM_KEY=linux64
case "$(uname -m)" in aarch64|arm64) CFT_PLATFORM_KEY=linux-arm64 ;; esac

plat_init() {
  need python3; need curl
  CFT_ROOT="$SBM_CONFIG_DIR/chrome-for-testing"
  CFT_EXE="$CFT_ROOT/current/chrome"
  PROFILE_DIR="$SBM_CONFIG_DIR/cft-profile"
  LAUNCHER="$HOME/.local/share/applications/browser-playwright-mcp.desktop"
  local desk; desk=$(xdg-user-dir DESKTOP 2>/dev/null || true); [ -n "$desk" ] || desk="$HOME/Desktop"
  DESKTOP_LAUNCHER=""
  [ -d "$desk" ] && [ "$desk" != "$HOME" ] && DESKTOP_LAUNCHER="$desk/browser-playwright-mcp.desktop"
  LAUNCHER_ARGS="--user-data-dir=${PROFILE_DIR} --remote-debugging-port=${PLAYWRIGHT_CDP_PORT} ${CFT_LAUNCH_FLAGS}"
  LAUNCHER_HINT="start \"Browser Playwright MCP\" from the desktop or the applications menu"
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

# Chrome for Testing ships only some product_logo_<size>.png files (linux64: 48 only); use the largest.
launcher_icon() {
  local n
  for n in 256 128 64 48 32 24 16; do
    [ -f "$CFT_ROOT/current/product_logo_$n.png" ] && { echo "$CFT_ROOT/current/product_logo_$n.png"; return; }
  done
  echo "$CFT_EXE"
}
launcher_content() {
  cat <<EOF
[Desktop Entry]
Name=Browser Playwright MCP
Type=Application
Terminal=false
Exec=${CFT_EXE} ${LAUNCHER_ARGS}
Icon=$(launcher_icon)
Categories=Development;
EOF
}
launcher_trusted() { command -v gio >/dev/null 2>&1 || return 0; gio info -a metadata::trusted "$1" 2>/dev/null | grep -q 'trusted: true'; }
plat_launcher_check() {
  local f
  for f in "$LAUNCHER" $DESKTOP_LAUNCHER; do
    if [ ! -f "$f" ]; then report MISSING launcher "$f"; return
    elif ! diff -q "$f" <(launcher_content) >/dev/null; then report DRIFT launcher "$f differs from template"; return
    fi
  done
  if [ -n "$DESKTOP_LAUNCHER" ] && { [ ! -x "$DESKTOP_LAUNCHER" ] || ! launcher_trusted "$DESKTOP_LAUNCHER"; }; then
    report DRIFT launcher "$DESKTOP_LAUNCHER not executable/trusted"; return
  fi
  report OK launcher "$LAUNCHER${DESKTOP_LAUNCHER:+ + $DESKTOP_LAUNCHER}"
}
plat_launcher_install() {
  mkdir -p "$(dirname "$LAUNCHER")"; launcher_content > "$LAUNCHER"
  if [ -n "$DESKTOP_LAUNCHER" ]; then
    launcher_content > "$DESKTOP_LAUNCHER"; chmod +x "$DESKTOP_LAUNCHER"
    command -v gio >/dev/null 2>&1 && gio set "$DESKTOP_LAUNCHER" metadata::trusted true 2>/dev/null || true
  fi
}

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

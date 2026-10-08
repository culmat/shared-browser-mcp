#!/usr/bin/env bash
# macOS branch. UNTESTED: derived from the manual steps in docs/manual-setup.md.
# Browser and profile live under ~/.config/playwright-mcp, the launcher is a small .app on the Desktop.

CFT_PLATFORM_KEY=mac-x64
case "$(uname -m)" in arm64) CFT_PLATFORM_KEY=mac-arm64 ;; esac

plat_init() {
  need python3; need curl
  CFT_ROOT="$SBM_CONFIG_DIR/chrome-for-testing"
  CFT_APP="$CFT_ROOT/current/Google Chrome for Testing.app"
  PROFILE_DIR="$SBM_CONFIG_DIR/cft-profile"
  LAUNCHER="$HOME/Desktop/Browser-Playwright-MCP.app"
  LAUNCHER_ARGS="--user-data-dir=${PROFILE_DIR} --remote-debugging-port=${PLAYWRIGHT_CDP_PORT} ${CFT_LAUNCH_FLAGS}"
  LAUNCHER_HINT="start \"Browser-Playwright-MCP\" from the Desktop"
}

plat_cft_current_version() { [ -L "$CFT_ROOT/current" ] && basename "$(readlink "$CFT_ROOT/current")"; }
plat_cft_versions() { ls -1 "$CFT_ROOT" 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+){3}$' || true; }
plat_cft_legacy_version() { return 1; }
plat_cft_migrate_legacy() { :; }
plat_cft_unpack() { # ZIP VERSION
  local tmp="$CFT_ROOT/.unpack-$2"; rm -rf "$tmp"; mkdir -p "$tmp"
  need unzip; unzip -q "$1" -d "$tmp"
  rm -rf "$CFT_ROOT/$2"; mv "$tmp"/chrome-mac* "$CFT_ROOT/$2"; rm -rf "$tmp"
}
plat_cft_activate() { [ -d "$CFT_ROOT/$1/Google Chrome for Testing.app" ] || die "no app bundle in $CFT_ROOT/$1"; ln -sfn "$CFT_ROOT/$1" "$CFT_ROOT/current"; }

launcher_script() { printf 'do shell script "open -na " & quoted form of "%s" & " --args %s"\n' "$CFT_APP" "$LAUNCHER_ARGS"; }
plat_launcher_check() {
  if [ ! -d "$LAUNCHER" ]; then report MISSING launcher "$LAUNCHER"
  elif [ ! -f "$LAUNCHER/Contents/Resources/sbm-launcher.applescript" ] || ! diff -q "$LAUNCHER/Contents/Resources/sbm-launcher.applescript" <(launcher_script) >/dev/null; then report DRIFT launcher "$LAUNCHER differs from template"
  else report OK launcher "$LAUNCHER"; fi
}
plat_launcher_install() {
  need osacompile
  local src="$SBM_CONFIG_DIR/launcher.applescript"
  launcher_script > "$src"
  rm -rf "$LAUNCHER"
  osacompile -o "$LAUNCHER" "$src"
  cp "$src" "$LAUNCHER/Contents/Resources/sbm-launcher.applescript"
  local icon="$CFT_APP/Contents/Resources/app.icns"
  [ -f "$icon" ] && cp "$icon" "$LAUNCHER/Contents/Resources/applet.icns" && touch "$LAUNCHER"
}

plist_content() {
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key><string>local.playwright-mcp</string>
    <key>ProgramArguments</key>
    <array><string>/bin/bash</string><string>-l</string><string>${SBM_CONFIG_DIR}/start-mcp.sh</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>5</integer>
    <key>StandardOutPath</key><string>/tmp/playwright-mcp.log</string>
    <key>StandardErrorPath</key><string>/tmp/playwright-mcp.err.log</string>
  </dict>
</plist>
EOF
}
plat_service_check() {
  local plist="$HOME/Library/LaunchAgents/local.playwright-mcp.plist"
  if [ ! -f "$plist" ]; then report MISSING service "$plist"
  elif ! diff -q "$plist" <(plist_content) >/dev/null; then report DRIFT service "plist differs from template"
  elif ! launchctl print "gui/$(id -u)/local.playwright-mcp" >/dev/null 2>&1; then report DRIFT service "not loaded (run: launchctl bootstrap gui/$(id -u) $plist)"
  else report OK service "launchd local.playwright-mcp loaded"; fi
}
plat_service_install() {
  local plist="$HOME/Library/LaunchAgents/local.playwright-mcp.plist"
  mkdir -p "$(dirname "$plist")"; plist_content > "$plist"
  if launchctl print "gui/$(id -u)/local.playwright-mcp" >/dev/null 2>&1; then
    if [ "${1:-}" = restart ]; then launchctl kickstart -k "gui/$(id -u)/local.playwright-mcp"
    else log "service files updated; restart when no agent is using the browser: launchctl kickstart -k gui/$(id -u)/local.playwright-mcp"; fi
  else
    launchctl bootstrap "gui/$(id -u)" "$plist"; launchctl enable "gui/$(id -u)/local.playwright-mcp"
  fi
}
plat_service_start_command() { echo "launchctl kickstart -k gui/$(id -u)/local.playwright-mcp"; }

plat_notify() { osascript -e "display notification \"${2//\"/\\\"}\" with title \"${1//\"/\\\"}\"" >/dev/null 2>&1 || true; }

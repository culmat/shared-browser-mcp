#!/usr/bin/env bash
# Windows + WSL branch. The browser, profile and desktop shortcut live on the Windows side;
# the MCP service runs inside WSL. Windows is driven through powershell.exe.

CFT_PLATFORM_KEY=win64

# run a PowerShell snippet from a Windows cwd (avoids UNC-cwd warnings), strip CRs
ps1() { (cd "$WIN_ROOT" && powershell.exe -NoProfile -NonInteractive -Command "$1") | tr -d '\r'; }

plat_init() {
  need powershell.exe; need wslpath; need python3; need curl
  WIN_ROOT=$(wslpath -u 'C:\')
  LOCALAPPDATA_WIN=$(ps1 'Write-Output $env:LOCALAPPDATA')
  [ -n "$LOCALAPPDATA_WIN" ] || die "cannot read %LOCALAPPDATA% via powershell.exe"
  LOCALAPPDATA_UNIX=$(wslpath -u "$LOCALAPPDATA_WIN")
  DESKTOP_WIN=$(ps1 '[Environment]::GetFolderPath("Desktop")')
  SBM_WIN_DIR="${LOCALAPPDATA_WIN}\\PlaywrightMCP"
  SBM_WIN_DIR_UNIX="${LOCALAPPDATA_UNIX}/PlaywrightMCP"
  CFT_ROOT="${SBM_WIN_DIR_UNIX}/chrome-for-testing"
  CFT_ROOT_WIN="${SBM_WIN_DIR}\\chrome-for-testing"
  CFT_EXE_WIN="${CFT_ROOT_WIN}\\current\\chrome.exe"
  PROFILE_DIR="${SBM_WIN_DIR_UNIX}/cft-profile"
  PROFILE_DIR_WIN="${SBM_WIN_DIR}\\cft-profile"
  LAUNCHER_WIN="${DESKTOP_WIN}\\Browser Playwright MCP.lnk"
  LAUNCHER_ARGS="--user-data-dir=\"${PROFILE_DIR_WIN}\" --remote-debugging-port=${PLAYWRIGHT_CDP_PORT} ${CFT_LAUNCH_FLAGS}"
  LAUNCHER_HINT="start \"Browser Playwright MCP\" from the Windows desktop"
}

# --- Chrome for Testing ---
plat_cft_current_version() {
  [ -e "$CFT_ROOT/current" ] || return 1
  local t
  t=$(ps1 "(Get-Item '${CFT_ROOT_WIN}\\current' -ErrorAction SilentlyContinue).Target")
  [ -n "$t" ] || return 1
  basename "${t//\\//}"
}
plat_cft_versions() { ls -1 "$CFT_ROOT" 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+){3}$' || true; }
plat_cft_exe_version() { # VERSION -> ProductVersion of chrome.exe in that folder
  ps1 "(Get-Item '${CFT_ROOT_WIN}\\$1\\chrome.exe' -ErrorAction SilentlyContinue).VersionInfo.ProductVersion"
}
# an install made before versioned folders existed: <root>/chrome-win64/chrome.exe
plat_cft_legacy_version() {
  [ -f "$CFT_ROOT/chrome-win64/chrome.exe" ] || return 1
  ls -1 "$CFT_ROOT/chrome-win64" | grep -oE '^[0-9]+(\.[0-9]+){3}' | head -1
}
plat_cft_migrate_legacy() { # VERSION
  cdp_up && die "the automation browser is running; close it, then re-run install"
  log "moving legacy chrome-win64 into versioned folder $1"
  mv "$CFT_ROOT/chrome-win64" "$CFT_ROOT/$1"
}
plat_cft_unpack() { # ZIP VERSION
  local tmp="$CFT_ROOT/.unpack-$2"
  rm -rf "$tmp"; mkdir -p "$tmp"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$1" -d "$tmp"
  else
    ps1 "Expand-Archive -LiteralPath '$(wslpath -w "$1")' -DestinationPath '$(wslpath -w "$tmp")' -Force"
  fi
  rm -rf "$CFT_ROOT/$2"
  mv "$tmp/chrome-win64" "$CFT_ROOT/$2"
  rm -rf "$tmp"
}
plat_cft_activate() { # VERSION
  [ -f "$CFT_ROOT/$1/chrome.exe" ] || die "no chrome.exe in $CFT_ROOT/$1"
  ps1 "if (Test-Path '${CFT_ROOT_WIN}\\current') { (Get-Item '${CFT_ROOT_WIN}\\current').Delete() }; New-Item -ItemType Junction -Path '${CFT_ROOT_WIN}\\current' -Target '${CFT_ROOT_WIN}\\$1' | Out-Null"
}

# --- launcher (desktop shortcut) ---
plat_launcher_check() {
  local have
  have=$(ps1 "\$s=(New-Object -ComObject WScript.Shell).CreateShortcut('${LAUNCHER_WIN}'); if (Test-Path '${LAUNCHER_WIN}') { \$s.TargetPath + '|' + \$s.Arguments }")
  if [ -z "$have" ]; then report MISSING launcher "$LAUNCHER_WIN"
  elif [ "$have" = "${CFT_EXE_WIN}|${LAUNCHER_ARGS}" ]; then report OK launcher "$LAUNCHER_WIN"
  else report DRIFT launcher "target/args differ: $have"
  fi
}
plat_launcher_install() {
  ps1 "\$s=(New-Object -ComObject WScript.Shell).CreateShortcut('${LAUNCHER_WIN}'); \$s.TargetPath='${CFT_EXE_WIN}'; \$s.Arguments='$(printf '%s' "$LAUNCHER_ARGS" | sed "s/'/''/g")'; \$s.WorkingDirectory='${CFT_ROOT_WIN}\\current'; \$s.IconLocation='${CFT_EXE_WIN},0'; \$s.Description='AUTOMATION browser (Chrome for Testing, CDP ${PLAYWRIGHT_CDP_PORT})'; \$s.Save()"
}

# --- service (systemd --user inside WSL; Task Scheduler fallback) ---
plat_has_systemd() { systemctl --user show-environment >/dev/null 2>&1; }
plat_service_check() {
  if plat_has_systemd; then
    local unit="$HOME/.config/systemd/user/playwright-mcp.service"
    if [ ! -f "$unit" ]; then report MISSING service "$unit"
    elif ! diff -q "$unit" <(service_unit_content) >/dev/null; then report DRIFT service "unit file differs from template"
    elif [ "$(systemctl --user is-active playwright-mcp.service)" != active ]; then report DRIFT service "not active (run: systemctl --user start playwright-mcp.service)"
    else report OK service "systemd --user playwright-mcp.service active"
    fi
  else
    if ps1 'schtasks /Query /TN PlaywrightMCP 2>$null | Out-String' | grep -q PlaywrightMCP; then report OK service "Task Scheduler task PlaywrightMCP"
    else report MISSING service "Task Scheduler task PlaywrightMCP (no systemd --user in this WSL)"
    fi
  fi
}
plat_service_install() { # [restart]
  if plat_has_systemd; then
    mkdir -p "$HOME/.config/systemd/user"
    service_unit_content > "$HOME/.config/systemd/user/playwright-mcp.service"
    systemctl --user daemon-reload
    systemctl --user enable playwright-mcp.service >/dev/null 2>&1
    if [ "${1:-}" = restart ] || [ "$(systemctl --user is-active playwright-mcp.service)" != active ]; then
      systemctl --user restart playwright-mcp.service
    else
      log "service files updated; restart when no agent is using the browser: systemctl --user restart playwright-mcp.service"
    fi
  else
    local distro="${WSL_DISTRO_NAME:-}" user; user=$(id -un)
    [ -n "$distro" ] || die "WSL_DISTRO_NAME not set; create the logon task manually (see docs/manual-setup.md)"
    ps1 "schtasks /Create /SC ONLOGON /TN PlaywrightMCP /TR \"wsl.exe -d $distro --user $user bash -lc '~/.config/playwright-mcp/start-mcp.sh'\" /F | Out-Null; schtasks /Run /TN PlaywrightMCP | Out-Null"
  fi
}
plat_service_start_command() {
  if plat_has_systemd; then echo "systemctl --user start playwright-mcp.service"; else echo "schtasks /Run /TN PlaywrightMCP (from cmd.exe)"; fi
}

# --- desktop notification (WinRT toast, no extra modules) ---
plat_notify() { # TITLE BODY
  local t=${1//\'/\'\'} b=${2//\'/\'\'}
  ps1 "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null; [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null; \$x = New-Object Windows.Data.Xml.Dom.XmlDocument; \$x.LoadXml('<toast><visual><binding template=\"ToastGeneric\"><text>' + [System.Security.SecurityElement]::Escape('$t') + '</text><text>' + [System.Security.SecurityElement]::Escape('$b') + '</text></binding></visual></toast>'); \$id = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe'; [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(\$id).Show([Windows.UI.Notifications.ToastNotification]::new(\$x))" >/dev/null 2>&1 || true
}

# Shared Chromium + Playwright MCP — manual setup and reference

This is the specification behind `shared-browser-mcp` and the fallback when the tool cannot do a step on your machine. Prefer the tool ([README](../README.md)); come here to understand what it does, or to do a step by hand.

Platform status: **Windows + WSL — tested**. macOS and Linux GNOME — written from earlier, hand-applied versions of this guide, **untested** with the current layout.

## Flow

1. A user-level service starts at login and keeps the **supervisor** (`~/.config/playwright-mcp/start-mcp.sh`) alive.
2. You start **Chrome for Testing** manually from a desktop shortcut, with a dedicated profile and a fixed DevTools port.
3. The supervisor sees the port, starts `@playwright/mcp` attached to it and exposes it on one HTTP endpoint for all agents.
4. When you close the browser, the supervisor stops MCP after a grace period and waits. When the browser is back, MCP is started again; agents reconnect to the same endpoint.
5. Once a day the supervisor checks for updates (browser, MCP, this repo), notifies you, and swaps in a new browser version only while the browser is closed.

## Shared runtime variables

Names are fixed; values are defaults. Override in `~/.config/playwright-mcp/local.env` (untracked). Change all related values together when you change a port.

```bash
PLAYWRIGHT_CDP_PORT=9223
PLAYWRIGHT_CDP_URL="http://127.0.0.1:9223"   # browser DevTools endpoint (used by the supervisor)
PLAYWRIGHT_MCP_HOST="127.0.0.1"
PLAYWRIGHT_MCP_PORT="8931"
PLAYWRIGHT_MCP_URL="http://localhost:8931"   # what agents connect to
```

`PLAYWRIGHT_CDP_URL` and `PLAYWRIGHT_MCP_URL` are different endpoints and must not be mixed.

> `PLAYWRIGHT_MCP_URL` uses `localhost`, not `127.0.0.1`: `@playwright/mcp` checks the `Host` header and answers `403` to `Host: 127.0.0.1`.

Ports are examples. Before binding, make sure the port is free; bind on `127.0.0.1` only; avoid ports below 1024.

## Step 1: Chrome for Testing

Why a separate binary and not a second profile of your normal browser: it gets its own icon, taskbar/dock entry and Alt-Tab/Cmd-Tab entry, so you always know which window the agents are in; its version is pinned, so it cannot update under running automation; and since Chrome 136 `--remote-debugging-port` is ignored on the default user data directory anyway.

Trade-off: Chrome for Testing reads enterprise policy from its own location (`SOFTWARE\Policies\Google\Chrome for Testing` on Windows). **Your organisation's Chrome policies do not apply to it** — no force-installed extensions, no managed settings, no auto-update. Step 1b covers the extensions you may need (SSO), and the supervisor covers updates.

### Layout

```text
<root>/chrome-for-testing/<version>/        one folder per installed version
<root>/chrome-for-testing/current            junction (Windows) / symlink → the active version
<root>/cft-profile/                          the AUTOMATION profile (user data dir)
```

`<root>` is `%LOCALAPPDATA%\PlaywrightMCP` on Windows and `~/.config/playwright-mcp` on macOS/Linux. The launcher points at `current`, so a version switch is a pointer swap.

### Download

Read the Stable version from `https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json` and download

```text
https://storage.googleapis.com/chrome-for-testing-public/<version>/<platform>/chrome-<platform>.zip
```

with `<platform>` = `win64`, `mac-arm64`, `mac-x64`, `linux64` or `linux-arm64`. Use `curl` — it honours `HTTPS_PROXY`/`NO_PROXY`. (`npx @puppeteer/browsers install chrome@stable` does the same thing but may fail behind corporate proxies.) Unzip, move the inner `chrome-<platform>` folder to `<root>/chrome-for-testing/<version>`, and point `current` at it:

```bash
# macOS / Linux
ln -sfn "$HOME/.config/playwright-mcp/chrome-for-testing/<version>" "$HOME/.config/playwright-mcp/chrome-for-testing/current"
```

```powershell
# Windows (no admin needed for a junction)
New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\PlaywrightMCP\chrome-for-testing\current" -Target "$env:LOCALAPPDATA\PlaywrightMCP\chrome-for-testing\<version>"
```

Executable: `current\chrome.exe` (Windows), `current/Google Chrome for Testing.app` (macOS), `current/chrome` (Linux).

### Fallback: another Chromium-based browser

Any Chromium-based browser accepts the same flags. If you cannot run Chrome for Testing, point the launcher at Chromium / Chrome / Edge / Brave / Vivaldi instead and keep everything else. You lose the separate icon and the pinned version; your organisation's policies will apply.

### Launcher

All platforms use the same arguments:

```text
--user-data-dir=<root>/cft-profile --remote-debugging-port=9223 --no-first-run --no-default-browser-check --hide-crash-restore-bubble --new-window about:blank
```

`--hide-crash-restore-bubble` matters: the browser is often closed programmatically (CDP `Browser.close`, service shutdown), which Chrome treats as a crash and would otherwise offer to restore the previous tabs.

**Windows** — shortcut `Browser Playwright MCP.lnk` on the Desktop (`[Environment]::GetFolderPath("Desktop")`, which respects folder redirection). Target `…\chrome-for-testing\current\chrome.exe`, the arguments above with the absolute profile path, icon `current\chrome.exe,0`. Create it with `WScript.Shell`:

```powershell
$s = (New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath("Desktop") + "\Browser Playwright MCP.lnk")
$s.TargetPath = "$env:LOCALAPPDATA\PlaywrightMCP\chrome-for-testing\current\chrome.exe"
$s.Arguments  = "--user-data-dir=`"$env:LOCALAPPDATA\PlaywrightMCP\cft-profile`" --remote-debugging-port=9223 --no-first-run --no-default-browser-check --hide-crash-restore-bubble --new-window about:blank"
$s.IconLocation = "$env:LOCALAPPDATA\PlaywrightMCP\chrome-for-testing\current\chrome.exe,0"
$s.Save()
```

**macOS** — a small `.app` on the Desktop compiled with `osacompile` from

```applescript
do shell script "open -na '/Users/YOU/.config/playwright-mcp/chrome-for-testing/current/Google Chrome for Testing.app' --args --user-data-dir=/Users/YOU/.config/playwright-mcp/cft-profile --remote-debugging-port=9223 --no-first-run --no-default-browser-check --hide-crash-restore-bubble --new-window about:blank"
```

then copy `Contents/Resources/app.icns` from the browser bundle to `Browser-Playwright-MCP.app/Contents/Resources/applet.icns`.

**Linux GNOME** — `~/.local/share/applications/browser-playwright-mcp.desktop`:

```ini
[Desktop Entry]
Name=Browser Playwright MCP
Type=Application
Terminal=false
Exec=/home/YOU/.config/playwright-mcp/chrome-for-testing/current/chrome --user-data-dir=/home/YOU/.config/playwright-mcp/cft-profile --remote-debugging-port=9223 --no-first-run --no-default-browser-check --hide-crash-restore-bubble --new-window about:blank
Icon=/home/YOU/.config/playwright-mcp/chrome-for-testing/current/product_logo_256.png
Categories=Development;
```

## Step 1b: The AUTOMATION profile

The profile is a plain user data directory. Three preferences make it recognisable and predictable; all are JSON edits in `<profile>/Default/Preferences` and `<profile>/Local State` that must be made **while the browser is closed** (it rewrites both files on exit).

| What | Where | Value |
|---|---|---|
| Profile name | `Preferences: profile.name`, `Local State: profile.info_cache.Default.name` | `AUTOMATION` |
| Start with a blank tab, never restore the last session | `Preferences: session.restore_on_startup` | `5` |
| Accent colour | `Preferences: browser.theme.user_color2` (signed 32-bit ARGB) + `extensions.theme.id = user_color_theme_id` | your colour |

The tool writes these with `python3` (`lib/common.sh`, `prefs_tool`). By hand:

```bash
python3 - <<'PY'
import json, pathlib, struct
profile = pathlib.Path.home() / '.config/playwright-mcp/cft-profile'   # Windows: %LOCALAPPDATA%/PlaywrightMCP/cft-profile
r, g, b = 250, 223, 115
color = struct.unpack('i', struct.pack('I', (255 << 24) | (r << 16) | (g << 8) | b))[0]
p = profile / 'Default/Preferences'; d = json.loads(p.read_text()) if p.exists() else {}
d.setdefault('profile', {}).update({'name': 'AUTOMATION', 'using_default_name': False})
d.setdefault('session', {})['restore_on_startup'] = 5
d.setdefault('browser', {}).setdefault('theme', {}).update({'user_color2': color, 'user_color': color, 'color_variant2': 1, 'color_variant': 1, 'follows_system_colors': False})
d.setdefault('extensions', {})['theme'] = {'id': 'user_color_theme_id'}
p.parent.mkdir(parents=True, exist_ok=True); p.write_text(json.dumps(d, separators=(',', ':')))
s = profile / 'Local State'; ls = json.loads(s.read_text()) if s.exists() else {}
ls.setdefault('profile', {}).setdefault('info_cache', {}).setdefault('Default', {}).update({'name': 'AUTOMATION', 'is_using_default_name': False})
s.write_text(json.dumps(ls, separators=(',', ':')))
PY
```

If the colour does not stick after the first start (seen once: a theme written before the profile's first clean exit was reset), pick it once in *Customize Chrome*; `shared-browser-mcp check` tells you whether the stored value matches.

**Bookmarks**: copy `<old profile>/Default/Bookmarks` into the new profile while the browser is closed, after deleting its `checksum` and `sync_metadata` keys; Chrome recomputes them.

**Accounts**: log into only the accounts your automation needs. Do not sign in with a personal Google account and do not enable sync — that would pull personal data into the shared session and defeat the separation.

**Extensions** (e.g. your organisation's single-sign-on helper): Chrome for Testing ignores enterprise force-install policies, and on managed machines the policy registry keys are usually locked anyway. Put the Web Store IDs in `local.env` (`PLAYWRIGHT_MCP_EXTENSIONS="id1 id2"`); `shared-browser-mcp install-extensions` opens each store page in the automation browser (`PUT http://127.0.0.1:9223/json/new?https://chromewebstore.google.com/detail/<id>`) and waits until `<profile>/Default/Extensions/<id>` appears — one click on *Add to Chrome* per extension. Installed extensions update themselves.

## Step 2: Supervisor and service

The supervisor is [`service/start-mcp.sh`](../service/start-mcp.sh); `install` copies it to `~/.config/playwright-mcp/start-mcp.sh` and records the repo checkout path in `~/.config/playwright-mcp/repo-path` so it can run `shared-browser-mcp check-updates`. It:

- waits for `PLAYWRIGHT_CDP_URL/json/version`, then runs `bunx`/`npx -y @playwright/mcp@latest --cdp-endpoint … --host … --port … --caps devtools --shared-browser-context` in its own process group;
- polls the browser every 5 s; after `PLAYWRIGHT_MCP_CDP_DOWN_GRACE` (30 s) without it, kills the MCP process group and goes back to waiting. (`@playwright/mcp` does **not** exit by itself when the browser goes away; without this, it would sit disconnected and never pick up a new `@latest`.)
- runs `check-updates --stage --notify` once per `PLAYWRIGHT_MCP_UPDATE_CHECK_INTERVAL`, and `activate-staged` whenever it finds the browser closed;
- serves `~/.config/playwright-mcp/status/` on `127.0.0.1:PLAYWRIGHT_MCP_STATUS_PORT` with `python3 -m http.server` (`0` disables).

**Linux and WSL with `systemd --user`** — [`service/playwright-mcp.service`](../service/playwright-mcp.service) goes to `~/.config/systemd/user/`, then `systemctl --user daemon-reload && systemctl --user enable --now playwright-mcp.service`. Variables come from `local.env`, not from the unit.

**WSL without `systemd --user`** — Windows logon task (from `cmd.exe`): `schtasks /Create /SC ONLOGON /TN PlaywrightMCP /TR "wsl.exe -d <Distro> --user <user> bash -lc '~/.config/playwright-mcp/start-mcp.sh'" /F`, then `schtasks /Run /TN PlaywrightMCP`.

**macOS** — `~/Library/LaunchAgents/local.playwright-mcp.plist` running `/bin/bash -l ~/.config/playwright-mcp/start-mcp.sh` with `RunAtLoad`, `KeepAlive`, `ThrottleInterval 5`, logs in `/tmp/playwright-mcp.log` / `.err.log`; `launchctl bootstrap gui/$(id -u) <plist> && launchctl enable gui/$(id -u)/local.playwright-mcp`. (The earlier guide compiled a small C stub so Login Items shows a readable name instead of "bash"; the tool does not do that — add it back if the label bothers you.)

Restarting the service kills the running MCP and disconnects every agent session, so `install` writes the files and only restarts when the service is not running (or with `--restart-service`).

## Step 3: Agents

Same pattern everywhere: a remote MCP server named `shared-browser` at `PLAYWRIGHT_MCP_URL`.

- **Claude Code**: `claude mcp add --scope user --transport http shared-browser http://localhost:8931` (the default scope is per-project; `--scope user` makes it global). Verify with `claude mcp list`.
- **OpenCode**: in `~/.config/opencode/opencode.json`: `{"mcp": {"shared-browser": {"type": "remote", "url": "http://localhost:8931"}}}`.
- **Others**: look for `MCP`, `mcpServers`, `remote MCP`, `HTTP transport`, `SSE transport`; URL `http://localhost:8931`, or `http://localhost:8931/sse` for clients that need an explicit SSE path.

Agents must not launch their own Playwright MCP; disable any per-agent auto-start. Give them [agent-instructions.md](agent-instructions.md).

## Step 4: Self-healing and status

Clients that fail to connect follow the order in [agent-instructions.md](agent-instructions.md) (as-is → `localhost` → toggle `/sse`) and report one short line.

Status contract (`shared-browser-mcp status`, `http://127.0.0.1:8932/status.json`):

```json
{
  "chrome": {"installed": "154.0.8037.92", "latest": "154.0.8037.92", "update": false, "staged": ""},
  "mcp":    {"installed": "0.0.83", "latest": "0.0.83", "update": false},
  "repo":   {"installed": "b245242", "latest": "b245242", "update": false},
  "serviceStartCommand": "systemctl --user start playwright-mcp.service",
  "configuredUrl": "http://localhost:8931",
  "updatedAt": "2026-10-06T11:05:10+0200"
}
```

Live state is probed, not stored: browser = `PLAYWRIGHT_CDP_URL/json/version` answers; MCP = `PLAYWRIGHT_MCP_URL/mcp` answers `200/400/405/406`.

## Updates by hand

- Chrome for Testing: download the new version into `<root>/chrome-for-testing/<version>` (Step 1), close the browser, repoint `current`, start it. Keep the previous folder until you are happy.
- `@playwright/mcp`: close the browser for > 30 s (or restart the service) — the next start resolves `@latest` again. Pin with `PLAYWRIGHT_MCP_NPM_SPEC=@playwright/mcp@0.0.83` in `local.env` if you need to.
- This repo: `git pull`, then `shared-browser-mcp install`.

## Troubleshooting

```bash
curl -s http://127.0.0.1:9223/json/version                              # browser
curl -s -o /dev/null -w '%{http_code}' http://localhost:8931/mcp        # MCP: 200/400/405 = up
systemctl --user --no-pager status playwright-mcp.service               # Linux / WSL
launchctl print "gui/$(id -u)/local.playwright-mcp" | grep -E "state =|last exit code"   # macOS
schtasks /Query /TN PlaywrightMCP                                       # Windows task fallback
journalctl --user -u playwright-mcp.service --since -1h                 # supervisor log
cat ~/.config/playwright-mcp/updates.log                                # update checks
```

- Browser closed → MCP goes away 30 s later by design; agents connected at the time stay disconnected until they reconnect (Claude Code: `/mcp`). New sessions just work once the browser is back.
- `403` from MCP → use `localhost`, not `127.0.0.1`.
- Screenshots fail in a non-CfT browser → an enterprise `DisableScreenshots` policy; Chrome for Testing is not subject to it.
- The browser starts with yesterday's tabs → `session.restore_on_startup` is not `5`, or the launcher lacks `--hide-crash-restore-bubble`; run `check`.

## Upgrading from earlier layouts

- **Shell bootstrap** (`~/.config/shell/playwright-mcp-bootstrap.sh` sourced from `.bashrc`/`.zshrc`): remove the line and the script; the service replaces it.
- **Regular Chrome/Chromium with `browser-profile/`**: `install` writes a new launcher for Chrome for Testing and a new `cft-profile`. Copy bookmarks as in Step 1b; log in afresh; delete the old `browser-profile` once you are sure (it may hold sessions of personal accounts).
- **Unversioned `chrome-for-testing/chrome-win64/`**: `install` moves it to `chrome-for-testing/<version>/` and creates `current` (browser must be closed).
- **Gist-era `start-mcp.sh` and unit with `Environment=` lines**: `install` replaces both; variables now live in `local.env`.

## Known limitations

- Each agent session opens its own tab and nothing raises the window; hence the handoff rule.
- The supervisor's update check needs network access to `googlechromelabs.github.io`, `storage.googleapis.com`, the npm registry and GitHub; failures are logged and ignored.
- Chrome for Testing is unmanaged: no enterprise policies, no OS-level auto-update. The supervisor's daily check is what keeps it current.
- macOS and Linux branches are untested with this layout.

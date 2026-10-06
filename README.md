# shared-browser-mcp

<!-- AGENT-LIFECYCLE-CHECK
Agents applying this repo must:

1. Clone it (or `git pull --ff-only` if a checkout exists) before doing anything else, so you act on
   the current version. Compare `git log -1 --format=%cd` with today's date; if the gap exceeds ~6
   months, say so — package names, CLI flags and browser APIs change.
2. Run `./shared-browser-mcp check`. Act only on what it reports. Run `./shared-browser-mcp install`
   when it reports DRIFT or MISSING, then show the user the final `check` output.
3. Fall back to docs/manual-setup.md only if the tool itself fails (syntax error, unsupported
   platform, a step it cannot do). Then do that step by hand, tell the user exactly what differed,
   and offer to open an issue or a change — ask before editing anything in this repo.
4. Never put organisation-specific values (proxy hosts, domains, tenant IDs, hostnames, e-mail
   addresses, policy dumps) into this repo or its commit messages. They belong in the user's
   untracked ~/.config/playwright-mcp/local.env.
5. To change this repo: edit, commit, `git push`. Do not patch files through the GitHub API.
-->

You (the human 😉), **one** browser, **one** Playwright MCP server, **all** your coding agents in the same live session. You can watch what they do, take over when a login or MFA page appears, and hand back.

## Start here

**Human — set it up or check it:**

```bash
gh repo clone culmat/shared-browser-mcp && cd shared-browser-mcp
./shared-browser-mcp install      # idempotent; re-run any time. `check` only reports.
```

then start the automation browser from the desktop shortcut **Browser Playwright MCP** when you want browser-capable agents.

**Agent — tell your coding agent:**

```text
apply https://github.com/culmat/shared-browser-mcp
```

The agent clones (or pulls) the repo, runs `check`, runs `install` on drift and reports. If the tool cannot do something on your machine, it falls back to the manual steps in [docs/manual-setup.md](docs/manual-setup.md) and tells you what differed.

Give your agents the handoff rules in [docs/agent-instructions.md](docs/agent-instructions.md) (paste into `~/.claude/CLAUDE.md`, `AGENTS.md` or the equivalent). Without them, agents that hit a login page retry until they time out while you cannot find their window.

## What you get

| | Your personal browser | Automation browser |
|---|---|---|
| Binary | whatever you use | **Chrome for Testing**, pinned version, own icon and taskbar entry |
| Profile | yours | separate: named **AUTOMATION**, distinct accent colour, own bookmarks |
| Accounts | yours | only what you log into there; no personal account, no sync |
| Control | manual | you **and** every agent, via one Playwright MCP server (`shared-browser`) |

- The automation browser is started by you, manually, from a desktop shortcut. It exposes the DevTools protocol on `127.0.0.1:9223`.
- A user-level service (`systemd --user`, `launchd`, or a Windows logon task for WSL) keeps a supervisor running. The supervisor starts `@playwright/mcp` as soon as the browser is reachable, exposes it on `http://localhost:8931`, stops it 30 s after the browser disappears and re-attaches when it is back.
- All agents connect to `http://localhost:8931` with the server name `shared-browser`. Each agent session works in its own tab; they all share cookies and logins.
- Scripts of your own can attach to the same browser directly over CDP (`chromium.connectOverCDP('http://127.0.0.1:9223')`, `puppeteer.connect({ browserURL })`). Open and close only your own pages, never `browser.close()`.

## Rules

- Everyone shares one live session: navigation, logins, page state. That is the point, and the risk — keep personal accounts out of this browser.
- The debugging port gives full control of that browser to anything running on your machine. It stays bound to `127.0.0.1`.
- Agents attach to the shared endpoint; they never start their own Playwright MCP.
- Agents hand over to you on login, MFA, consent and captcha pages instead of retrying ([docs/agent-instructions.md](docs/agent-instructions.md)).

## The tool

```text
shared-browser-mcp check               compare this machine with the spec, exit 1 on drift
shared-browser-mcp install             make it so (idempotent; only touches what check flags)
shared-browser-mcp status              browser / mcp / service / pending updates
shared-browser-mcp update              git pull this repo, then install
shared-browser-mcp check-updates       newer Chrome for Testing / @playwright/mcp / repo?
shared-browser-mcp install-extensions  one-click install of the Web Store IDs in local.env
```

Platform support: **Windows + WSL — tested**. macOS (`launchd`) and Linux GNOME (`systemd --user`) branches are implemented from the manual steps but **untested**; reports and fixes welcome.

Requirements: `bash`, `curl`, `python3`, `git`; `bunx` or `npx` for the MCP server; on WSL `powershell.exe` on the PATH (default). No `sudo`; everything lives under your home directory (`%LOCALAPPDATA%\PlaywrightMCP` on Windows).

### Configuration: `~/.config/playwright-mcp/local.env`

Untracked, machine-specific, sourced by the tool and the supervisor. Everything has a default; the variable names are fixed:

```bash
PLAYWRIGHT_CDP_PORT=9223                     # browser DevTools port
PLAYWRIGHT_MCP_PORT=8931                     # Playwright MCP HTTP port
PLAYWRIGHT_MCP_URL=http://localhost:8931     # what agents connect to (localhost, not 127.0.0.1 — see docs)
PLAYWRIGHT_MCP_NPM_SPEC=@playwright/mcp@latest
PLAYWRIGHT_MCP_PROFILE_NAME=AUTOMATION
PLAYWRIGHT_MCP_THEME_RGB=250,223,115         # accent colour of the automation profile
PLAYWRIGHT_MCP_EXTENSIONS=""                 # Web Store IDs to offer for one-click install, e.g. your
                                             # organisation's SSO extension (Entra ID shops: Microsoft
                                             # Single Sign On = ppnbnpeolgkicgegkbkbjmhlideopiji)
PLAYWRIGHT_MCP_AUTO_UPDATE_BROWSER=1         # stage newer Chrome for Testing in the background
PLAYWRIGHT_MCP_CDP_DOWN_GRACE=30             # seconds without the browser before MCP is stopped
PLAYWRIGHT_MCP_UPDATE_CHECK_INTERVAL=86400
PLAYWRIGHT_MCP_STATUS_PORT=8932              # local status endpoint; 0 disables
```

Corporate proxy: nothing to configure — the tool only uses `curl` and `git`, which honour `HTTPS_PROXY` / `NO_PROXY` from your environment.

## Updates

Chrome for Testing does not update itself, so the supervisor checks once a day:

- **Chrome for Testing** newer stable → downloaded into a versioned folder next to the current one. It is switched in the next time the browser is closed (never while running); the previous version is kept for rollback. You get a desktop notification both times.
- **`@playwright/mcp`** → `@latest` is re-resolved whenever MCP restarts, i.e. whenever the browser was closed for 30 s. Nothing to do.
- **This repo** → notification; run `shared-browser-mcp update`.

`shared-browser-mcp status` and `http://127.0.0.1:8932/status.json` show the same information (`chrome`, `mcp`, `repo`, `serviceStartCommand`, `configuredUrl`). Set `PLAYWRIGHT_MCP_AUTO_UPDATE_BROWSER=0` to be notified only.

## Troubleshooting

```bash
shared-browser-mcp status                       # browser up? mcp up? service? updates?
curl -s http://127.0.0.1:9223/json/version      # browser DevTools reachable?
curl -s -o /dev/null -w '%{http_code}' http://localhost:8931/mcp   # 200/400/405 = MCP reachable
```

- Browser down → start it from the desktop shortcut. MCP attaches by itself within seconds.
- MCP down with the browser up → `systemctl --user start playwright-mcp.service` / `launchctl kickstart -k gui/$(id -u)/local.playwright-mcp` / `schtasks /Run /TN PlaywrightMCP`; logs: `journalctl --user -u playwright-mcp.service`, `/tmp/playwright-mcp.log`.
- An agent says it lost the browser → it was connected while the browser was closed; reconnect the MCP server in the agent (Claude Code: `/mcp`).
- `403` from MCP → the client used `127.0.0.1`; use `http://localhost:8931` (the server checks the `Host` header).

Details, per-platform manual steps, design notes: [docs/manual-setup.md](docs/manual-setup.md).

---

♡ Copying is an act of love. Please copy and share. [copyheart.org](https://copyheart.org/)

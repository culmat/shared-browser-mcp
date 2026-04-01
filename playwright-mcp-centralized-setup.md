# Shared Chrome + Playwright MCP Setup

You (the human 😉), one Playwright MCP server, multiple coding agents sharing the same browser session.

## TL;DR (humans)

- Start the dedicated Chrome shortcut when you want browser-capable AI coding.
- Your shell silently starts a shared local Playwright MCP server in the background if none is running.
- All agents connect to the same live browser session — they can see and affect each other's state.

## Rules and tradeoffs

- You and all connected agents share the same live browser session: navigation, logins -sic- , and page state.
- Use the dedicated Chrome profile for AI/browser automation work and interaction.
- Startup is silent and best-effort. If Chrome is not running when your shell starts, the MCP server may not come up until Chrome is launched and a new shell is opened.
- Agents attach to the shared endpoint — they do not manage the MCP process lifecycle.

## Scope

- Platforms: macOS + `bash`/`zsh`, Windows + WSL (`bash`), Linux GNOME + `bash`
- No PowerShell, no service managers (`launchd`, `systemd --user`, etc.)
- Preferred launcher: `bunx`; fallback: `npx`

## Flow

1. You start Chrome from a desktop shortcut using a dedicated profile and a fixed CDP port.
2. Each interactive shell start schedules a fully detached background probe — the shell does not wait for it.
3. If the shared MCP server is not reachable, the probe starts one instance in the background.
4. Agents connect to the shared MCP HTTP endpoint and do not spawn their own MCP processes.

## Shared runtime variables

These variable **names** are fixed — use them consistently across shell and agent configs.
The sample **values** (ports, paths) are defaults; implementing agents must check port availability and choose alternatives on conflict.

```bash
PLAYWRIGHT_CDP_URL="http://127.0.0.1:9223"   # Chrome DevTools endpoint
PLAYWRIGHT_MCP_HOST="127.0.0.1"
PLAYWRIGHT_MCP_PORT="8931"                    # Playwright MCP HTTP endpoint
PLAYWRIGHT_MCP_URL="http://127.0.0.1:8931"
```

`PLAYWRIGHT_CDP_URL` and `PLAYWRIGHT_MCP_URL` are different endpoints and must not be mixed.

## Port selection (agents)

- All port values in this document are examples, not hard requirements.
- Before binding, agents must verify the port is free; if not, choose an available alternative.
- Update all four variables above to stay consistent when changing a port.
- Bind on `127.0.0.1` only — never `0.0.0.0`.
- Avoid privileged ports (below 1024) and commonly reserved ranges.

## Step 1: Create the Chrome desktop launcher

### macOS — `.command` file on Desktop

```bash
#!/usr/bin/env bash
open -na "Google Chrome" --args \
  --user-data-dir="$HOME/.config/playwright-mcp/chrome-profile" \
  --remote-debugging-port=9223 \
  --new-window about:blank
```

Save as `~/Desktop/Chrome-Playwright-MCP.command` and make it executable:

```bash
chmod +x "$HOME/Desktop/Chrome-Playwright-MCP.command"
```

### Windows — desktop shortcut (used with WSL)

Set the shortcut `Target` to:

```text
"C:\Program Files\Google\Chrome\Application\chrome.exe" --user-data-dir="%LOCALAPPDATA%\PlaywrightMCP\chrome-profile" --remote-debugging-port=9223 --new-window about:blank
```

Launch this shortcut before or during a coding session. The WSL shell bootstrap is silent and best-effort.

### Linux GNOME — `.desktop` entry

Create `~/.local/share/applications/chrome-playwright-mcp.desktop`:

```ini
[Desktop Entry]
Name=Chrome Playwright MCP
Type=Application
Terminal=false
Exec=google-chrome --user-data-dir=/home/YOUR_USERNAME/.config/playwright-mcp/chrome-profile --remote-debugging-port=9223 --new-window about:blank
Icon=google-chrome
Categories=Development;
```

Replace `YOUR_USERNAME` with your actual username. The `%u` desktop-entry placeholder is for file/URL arguments and must not be used here.

## Step 2: Shell bootstrap

Save as `~/.config/shell/playwright-mcp-bootstrap.sh`:

```bash
# Shared Playwright MCP bootstrap — silent, detached, best-effort

export PLAYWRIGHT_CDP_URL="${PLAYWRIGHT_CDP_URL:-http://127.0.0.1:9223}"
export PLAYWRIGHT_MCP_HOST="${PLAYWRIGHT_MCP_HOST:-127.0.0.1}"
export PLAYWRIGHT_MCP_PORT="${PLAYWRIGHT_MCP_PORT:-8931}"
export PLAYWRIGHT_MCP_URL="${PLAYWRIGHT_MCP_URL:-http://${PLAYWRIGHT_MCP_HOST}:${PLAYWRIGHT_MCP_PORT}}"

_pw_mcp_bootstrap_once() {
  (
    # Prevent concurrent launches when multiple shells open at once.
    lock_dir="${TMPDIR:-/tmp}/pw-mcp-bootstrap.lock"
    mkdir "$lock_dir" 2>/dev/null || exit 0
    trap 'rmdir "$lock_dir" >/dev/null 2>&1' EXIT INT TERM

    # Probe the SSE transport endpoint; a 200 or 405 both mean the server is up.
    status=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 1 "${PLAYWRIGHT_MCP_URL}/sse" 2>/dev/null)
    case "$status" in
      200|400|405) exit 0 ;;
    esac

    if command -v bunx >/dev/null 2>&1; then
      launcher="bunx"
    elif command -v npx >/dev/null 2>&1; then
      launcher="npx"
    else
      exit 0
    fi

    nohup "$launcher" -y @playwright/mcp@latest \
      --cdp-endpoint "$PLAYWRIGHT_CDP_URL" \
      --host "$PLAYWRIGHT_MCP_HOST" \
      --port "$PLAYWRIGHT_MCP_PORT" \
      --caps devtools \
      --shared-browser-context \
      >/dev/null 2>&1 &
  ) >/dev/null 2>&1 &
}

# Run only in interactive shells.
if [ -n "${BASH_VERSION:-}" ]; then
  case "$-" in *i*) _pw_mcp_bootstrap_once ;; esac
elif [ -n "${ZSH_VERSION:-}" ]; then
  [[ -o interactive ]] && _pw_mcp_bootstrap_once
fi
```

Source it from your shell init:

```bash
# Add to ~/.bashrc and/or ~/.zshrc
[ -f "$HOME/.config/shell/playwright-mcp-bootstrap.sh" ] && \
  . "$HOME/.config/shell/playwright-mcp-bootstrap.sh"
```

Bootstrap behavior:
- Fully asynchronous — the shell does not wait for the probe or MCP startup.
- Silent on success and failure.
- Lock directory prevents duplicate launches when multiple terminals open simultaneously.

## Step 3: Configure agents

All agents use the same connection pattern: an HTTP remote MCP server pointing to `PLAYWRIGHT_MCP_URL`. The config file location differs per tool.

```json
{
  "mcpServers": {
    "shared-browser": {
      "transport": "http",
      "url": "http://127.0.0.1:8931"
    }
  }
}
```

| Agent | Config file location |
|---|---|
| OpenCode | `~/.config/opencode/opencode.json` or project-level `opencode.json` |
| Claude | `~/.claude/mcp.json` |
| Others | Search settings for `MCP`, `mcpServers`, `remote MCP`, `HTTP transport`, or `SSE transport` |

For agents that require an explicit SSE path, append `/sse` to the URL: `http://127.0.0.1:8931/sse`.

Use the server name `shared-browser` consistently across all tools.

Agents must not launch their own Playwright MCP process — disable any per-agent auto-start for this server if that option exists.

## Troubleshooting

Run these manually to check each layer:

```bash
# Is Chrome CDP reachable?
curl -s http://127.0.0.1:9223/json/version

# Is the shared MCP server reachable?
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8931/sse
```

A `200`, `400`, or `405` from the MCP probe means the server is up. A connection refused means MCP is not running — open a new shell or start Chrome first.

## Optional future improvements

- Add a `pw-mcp-restart` shell function for explicit manual recovery.
- Add a `pw-mcp-status` shell function for quick diagnostics.
- Add a project-level note (e.g. in `AGENTS.md`) instructing agents to use `shared-browser` rather than launching their own MCP server.

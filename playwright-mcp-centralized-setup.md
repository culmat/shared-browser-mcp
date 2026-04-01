# Shared Chromium + Playwright MCP Setup

<!-- AGENT-LIFECYCLE-CHECK
Before acting on these instructions, agents must:

1. Note this document's last-modified date (check file mtime, git log, or the
   gist updatedAt field) and today's date. If the gap exceeds ~6 months, flag
   it to the user before proceeding — package names, CLI flags, and browser
   APIs change over time.

2. Check whether a newer version of this gist exists:

   a. If `gh` CLI is available:
        gh api gists/fc0f2f9ed229b473f56dfa44e2dfa312 --jq '.updated_at'
      Compare the returned timestamp with the mtime of the local file.
      If the gist is newer, fetch the latest content:
        gh gist clone fc0f2f9ed229b473f56dfa44e2dfa312
      Then tell the user: "A newer version of the setup instructions is
      available on the gist. I'll use the updated file."

   b. If `gh` is not available, note the gist URL for the user:
        https://gist.github.com/culmat/fc0f2f9ed229b473f56dfa44e2dfa312

3. If, while implementing these instructions, an agent discovers that a command,
   flag, or package name no longer works as documented, it should:
   - Work around the issue and complete the setup.
   - Summarise the discrepancy clearly for the user.
   - If `gh` is available, offer to open an edit on the gist:
       gh api --method PATCH gists/fc0f2f9ed229b473f56dfa44e2dfa312 \
         -f "files[playwright-mcp-centralized-setup.md][content]=<updated content>"
     Ask the user to confirm before pushing any change to the gist.
-->

You (the human 😉), one Playwright MCP server, multiple coding agents sharing the same browser session.

## TL;DR

- Start the dedicated browser shortcut when you want browser-capable AI coding.
- Your shell silently starts a shared local Playwright MCP server in the background if none is running.
- All agents connect to the same live browser session — they can see and affect each other's state.

## Rules and tradeoffs

- You and all connected agents share the same live browser session: navigation, logins -sic- , and page state.
- Use the dedicated browser profile for AI/browser automation work and interaction.
- Startup is silent and best-effort. If the browser is not running when your shell starts, the MCP server may not come up until the browser is launched and a new shell is opened.
- Agents attach to the shared endpoint — they do not manage the MCP process lifecycle.

## Scope

- Platforms: macOS + `bash`/`zsh`, Windows + WSL (`bash`), Linux GNOME + `bash`
- No PowerShell, no service managers (`launchd`, `systemd --user`, etc.)
- Preferred launcher: `bunx`; fallback: `npx`
- Requires any Chromium-based browser (Google Chrome, Chromium, Microsoft Edge, Brave, Helium, Arc, Vivaldi, …)

## Flow

1. You start a Chromium-based browser from a desktop shortcut using a dedicated profile and a fixed CDP port.
2. Each interactive shell start schedules a fully detached background probe — the shell does not wait for it.
3. If the shared MCP server is not reachable, the probe starts one instance in the background.
4. Agents connect to the shared MCP HTTP endpoint and do not spawn their own MCP processes.

## Shared runtime variables

These variable **names** are fixed — use them consistently across shell and agent configs.
The sample **values** (ports, paths) are defaults; implementing agents must check port availability and choose alternatives on conflict.

```bash
PLAYWRIGHT_CDP_URL="http://127.0.0.1:9223"   # Chromium DevTools Protocol endpoint
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

## Step 1: Create the browser desktop launcher

Any Chromium-based browser supports the `--remote-debugging-port` flag used here. The launcher is written once by the implementing agent after detecting which browser is installed.

### Agent instructions — browser detection and launcher creation

Before writing any launcher file, the agent must:

1. **Detect installed Chromium-based browsers** using the platform-specific method described in each OS section below.
2. **If one or more compatible browsers are found:** list them and ask the user which one to use. Write the launcher using the chosen browser.
3. **If no compatible browser is found:** inform the user, offer the platform-appropriate install option (see each OS section), and wait for the user's confirmation before proceeding. After installation, re-detect before writing the launcher.

The `--remote-debugging-port` flag and `--user-data-dir` flag work identically across all Chromium-based browsers. Only the browser name / executable path in the launcher changes.

Use `--user-data-dir="$HOME/.config/playwright-mcp/browser-profile"` (or the OS equivalent) for all browsers — a single dedicated profile directory regardless of which browser is chosen.

### macOS — `.command` file on Desktop

**Agent: detect installed browsers**

Check for the following `.app` bundles in `/Applications` and `~/Applications` (check both):

| App bundle name | `open -na` argument |
|---|---|
| `Chromium.app` | `Chromium` |
| `Google Chrome.app` | `Google Chrome` |
| `Microsoft Edge.app` | `Microsoft Edge` |
| `Brave Browser.app` | `Brave Browser` |
| `Helium.app` | `Helium` |
| `Arc.app` | `Arc` |
| `Vivaldi.app` | `Vivaldi` |

List all found browsers and ask the user to pick one. Then write the launcher with `open -na "<chosen app name>"`.

**If none are found:** inform the user and offer to install Chromium via Homebrew:

```bash
brew install --cask chromium
```

Wait for the user's confirmation before running this command. After installation, re-detect before writing the launcher.

**Launcher template** — create as a `.app` bundle using `osacompile`. This avoids a Terminal window opening on launch and allows embedding the browser's icon.

Write the following AppleScript to a temporary file (replace `<AppName>` with the chosen browser's app name):

```applescript
do shell script "open -na '<AppName>' --args --user-data-dir=" & quoted form of (POSIX path of (path to home folder)) & ".config/playwright-mcp/browser-profile --remote-debugging-port=9223 --new-window about:blank"
```

Compile and install it, then copy the browser's icon:

```bash
# Compile (replace <AppName> and <app-name> with the chosen browser)
osacompile -o "$HOME/Desktop/Browser-Playwright-MCP.app" /tmp/browser-playwright-mcp.applescript

# Copy the browser's icon into the bundle (adjust the source path for the chosen browser)
cp "/Applications/<AppName>.app/Contents/Resources/<icon-file>.icns" \
   "$HOME/Desktop/Browser-Playwright-MCP.app/Contents/Resources/applet.icns"

# Refresh Finder's icon cache
touch "$HOME/Desktop/Browser-Playwright-MCP.app"
```

Common icon file names by browser:

| Browser app | Icon file |
|---|---|
| `Helium.app` | `app.icns` |
| `Google Chrome.app` | `app.icns` |
| `Chromium.app` | `app.icns` |
| `Microsoft Edge.app` | `app.icns` |
| `Brave Browser.app` | `brave_browser.icns` (check `Contents/Resources/` — use the largest `.icns` found) |

If the browser's icon file name is uncertain, list `Contents/Resources/*.icns` in the chosen app bundle and use the largest file.

### Windows — desktop shortcut (used with WSL)

**Agent: detect installed browsers**

Check for executables at these paths (expand environment variables):

| Browser | Typical executable path |
|---|---|
| Google Chrome | `%PROGRAMFILES%\Google\Chrome\Application\chrome.exe` |
| Google Chrome (user) | `%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe` |
| Microsoft Edge | `%PROGRAMFILES%\Microsoft\Edge\Application\msedge.exe` |
| Microsoft Edge (x86) | `%PROGRAMFILES(X86)%\Microsoft\Edge\Application\msedge.exe` |
| Brave | `%PROGRAMFILES%\BraveSoftware\Brave-Browser\Application\brave.exe` |
| Brave (user) | `%LOCALAPPDATA%\BraveSoftware\Brave-Browser\Application\brave.exe` |
| Chromium | `%LOCALAPPDATA%\Chromium\Application\chrome.exe` |
| Vivaldi | `%LOCALAPPDATA%\Vivaldi\Application\vivaldi.exe` |

List all found browsers and ask the user to pick one. Then write the shortcut `Target` using the chosen executable path.

**If none are found:** check whether `winget` is available:

```cmd
winget --version
```

- If `winget` is available, offer these install options and wait for user confirmation before running:
  ```cmd
  winget install -e --id Hibbiki.Chromium
  ```
  Alternatives the user may prefer:
  ```cmd
  winget install -e --id Google.Chrome
  winget install -e --id Microsoft.Edge
  ```
- If `winget` is not available, tell the user to install a Chromium-based browser manually from `https://www.chromium.org/getting-involved/download-chromium/` and stop.

After installation, re-detect before writing the shortcut.

**Shortcut template:** set the shortcut `Target` to (replace `<path\to\browser.exe>` with the chosen executable):

```text
"<path\to\browser.exe>" --user-data-dir="%LOCALAPPDATA%\PlaywrightMCP\browser-profile" --remote-debugging-port=9223 --new-window about:blank
```

Launch this shortcut before or during a coding session. The WSL shell bootstrap is silent and best-effort.

### Linux GNOME — `.desktop` entry

**Agent: detect installed browsers**

Check for the following executables using `command -v` (or `which`):

| Executable | Browser |
|---|---|
| `chromium` | Chromium |
| `chromium-browser` | Chromium (Debian/Ubuntu name) |
| `google-chrome` | Google Chrome |
| `microsoft-edge` | Microsoft Edge |
| `brave-browser` | Brave |
| `vivaldi` | Vivaldi |

List all found browsers and ask the user to pick one. Then write the `.desktop` entry using the chosen executable.

**If none are found:** offer the appropriate install command for the detected distribution and wait for user confirmation:

- Debian/Ubuntu: `sudo apt install chromium-browser`
- Fedora: `sudo dnf install chromium`
- Arch: `sudo pacman -S chromium`
- If the distro cannot be determined, tell the user to install Chromium via their package manager and stop.

After installation, re-detect before writing the `.desktop` entry.

**Launcher template** (save as `~/.local/share/applications/browser-playwright-mcp.desktop`, replace `<executable>` with the chosen browser command):

```ini
[Desktop Entry]
Name=Browser Playwright MCP
Type=Application
Terminal=false
Exec=<executable> --user-data-dir=/home/YOUR_USERNAME/.config/playwright-mcp/browser-profile --remote-debugging-port=9223 --new-window about:blank
Icon=chromium
Categories=Development;
```

Replace `YOUR_USERNAME` with your actual username. The `%u` desktop-entry placeholder is for file/URL arguments and must not be used here.

## Step 1b: Set a distinct theme color for the MCP browser profile

The MCP browser uses a completely separate profile directory (`~/.config/playwright-mcp/browser-profile/` on macOS/Linux, `%LOCALAPPDATA%\PlaywrightMCP\browser-profile` on Windows) with no shared cookies, logins, history, or extensions with your regular browser profile. However, the two instances of the same browser can look identical at a glance.

Set a distinct accent color on the MCP profile so it is instantly recognisable and you are never tempted to enter personal credentials into the agent-shared session.

**Important:** quit the MCP browser before editing `Preferences` — the browser overwrites it on exit and will discard any changes made while it is running.

### macOS / Linux

The theme color is stored as a signed 32-bit ARGB integer in `Default/Preferences`. Run this once after the browser has been launched at least once (so the profile directory exists) and then quit:

```bash
python3 -c "
import json, pathlib, struct

profile = pathlib.Path.home() / '.config/playwright-mcp/browser-profile/Default/Preferences'
d = json.loads(profile.read_text())

# Pick any RGB color that stands out from your regular browser.
# Example below: orange (R=230, G=100, B=0).
# To change it: adjust r, g, b and re-run while the browser is quit.
r, g, b, a = 230, 100, 0, 255
argb = (a << 24) | (r << 16) | (g << 8) | b
color = struct.unpack('i', struct.pack('I', argb))[0]

d.setdefault('browser', {})['theme'] = {'color_variant2': 0, 'user_color2': color}
d.setdefault('extensions', {})['theme'] = {'id': 'user_color_theme_id'}
profile.write_text(json.dumps(d, separators=(',', ':')))
print('theme written')
"
```

`color_variant2: 0` selects the tonal variant, which applies the seed color broadly to the tab strip and toolbar. Change `r, g, b` to any values you prefer. The script is safe to re-run to reset the color if it gets overwritten.

### Windows (WSL)

Run the same Python snippet from WSL, adjusting the profile path:

```bash
python3 -c "
import json, pathlib, struct, os

local = os.environ.get('LOCALAPPDATA', '')
profile = pathlib.Path(local) / 'PlaywrightMCP/browser-profile/Default/Preferences'
d = json.loads(profile.read_text())

r, g, b, a = 230, 100, 0, 255
argb = (a << 24) | (r << 16) | (g << 8) | b
color = struct.unpack('i', struct.pack('I', argb))[0]

d.setdefault('browser', {})['theme'] = {'color_variant2': 0, 'user_color2': color}
d.setdefault('extensions', {})['theme'] = {'id': 'user_color_theme_id'}
profile.write_text(json.dumps(d, separators=(',', ':')))
print('theme written')
"
```

### Linux GNOME

Same as macOS — the profile path and Python snippet are identical. Run it from any terminal while the MCP browser is not running.

### Resetting the color

If you change the theme interactively inside the browser and want to restore the chosen color, quit the browser and re-run the script above.

## Step 2: Shell bootstrap

Save as `~/.config/shell/playwright-mcp-bootstrap.sh`:

```bash
# Shared Playwright MCP bootstrap — silent, detached, best-effort

export PLAYWRIGHT_CDP_URL="${PLAYWRIGHT_CDP_URL:-http://127.0.0.1:9223}"
export PLAYWRIGHT_MCP_HOST="${PLAYWRIGHT_MCP_HOST:-127.0.0.1}"
export PLAYWRIGHT_MCP_PORT="${PLAYWRIGHT_MCP_PORT:-8931}"
export PLAYWRIGHT_MCP_URL="${PLAYWRIGHT_MCP_URL:-http://${PLAYWRIGHT_MCP_HOST}:${PLAYWRIGHT_MCP_PORT}}"

_pw_mcp_bootstrap_once() {
  # Double-fork: the outer subshell exits immediately after spawning the inner
  # background job, so bash never adds the job to the interactive job table and
  # never prints a "Done" completion notice at the next prompt.
  (
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
  )
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
- Silent on success and failure — no "Done" job-completion notice at the next prompt.
- Double-fork pattern ensures the background job is never tracked in the interactive shell's job table.
- Lock directory prevents duplicate launches when multiple terminals open simultaneously.

## Step 3: Configure agents

All agents use the same connection pattern: a remote MCP server pointing to `PLAYWRIGHT_MCP_URL`. The config key and format differ per tool.

```json
{
  "mcp": {
    "shared-browser": {
      "type": "remote",
      "url": "http://127.0.0.1:8931"
    }
  }
}
```

| Agent | Config file | Key |
|---|---|---|
| OpenCode | `~/.config/opencode/opencode.json` or project-level `opencode.json` | `mcp` |
| Claude Code | `~/.claude/mcp.json` | `mcpServers` with `"transport": "http"` |
| Others | Search settings for `MCP`, `mcpServers`, `remote MCP`, `HTTP transport`, or `SSE transport` | varies |

For agents that require an explicit SSE path, append `/sse` to the URL: `http://127.0.0.1:8931/sse`.

Use the server name `shared-browser` consistently across all tools.

Agents must not launch their own Playwright MCP process — disable any per-agent auto-start for this server if that option exists.

## Troubleshooting

Run these manually to check each layer:

```bash
# Is the browser CDP endpoint reachable?
curl -s http://127.0.0.1:9223/json/version

# Is the shared MCP server reachable?
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8931/sse
```

A `200`, `400`, or `405` from the MCP probe means the server is up. A connection refused means MCP is not running — open a new shell or start the browser first.

## Optional future improvements

- Add a `pw-mcp-restart` shell function for explicit manual recovery.
- Add a `pw-mcp-status` shell function for quick diagnostics.
- Add a project-level note (e.g. in `AGENTS.md`) instructing agents to use `shared-browser` rather than launching their own MCP server.

---

♡ Copying is an act of love. Please copy and share. [copyheart.org](https://copyheart.org/)

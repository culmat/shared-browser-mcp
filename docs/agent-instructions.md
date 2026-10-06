# Agent instructions for the shared browser

Paste the block below into your agent's global instructions (`~/.claude/CLAUDE.md`, `AGENTS.md`, `.cursorrules`, …). Adjust the window description to your setup (browser name, profile name, accent colour) so the agent can tell you where to look.

Why this is needed: with `@playwright/mcp` each agent session silently opens its own tab, and nothing brings that tab to the front. An agent that reaches a login page therefore retries until it times out, while you cannot see which window or tab it is talking about. The rule below turns that into a one-line handoff.

```markdown
## shared-browser (Playwright MCP)

- `shared-browser` drives ONE browser shared with the user and other agents: Chrome for Testing,
  profile "AUTOMATION" (yellow accent, Chrome-for-Testing icon in the taskbar/dock), CDP 127.0.0.1:9223.
- Your first browser action opens your own tab. Remember its index; never close or navigate tabs
  you did not open.
- Human handoff — on a login, MFA, consent, captcha, or any page you cannot get past:
  1. `browser_tabs` action `select` with your tab index (brings the tab to the front).
  2. Tell the user in one line: "Please log in in the yellow AUTOMATION browser, tab <N>: <title>.
     Reply when done." The OS does not raise the window over the editor, so always say where to look.
  3. Stop and wait for the user's reply. Do not retry, type credentials, or open more tabs meanwhile.
  4. After the reply, `browser_snapshot` to confirm you are past the page, then continue.
- Never enter credentials unless the user provides them for the task.
- If tools report the browser is closed/disconnected: ask the user to start "Browser Playwright MCP"
  from the desktop, then reconnect the MCP server (Claude Code: `/mcp`).
- Never start your own Playwright MCP or browser; always use `shared-browser`.
```

Connection self-healing for clients that fail to reach `shared-browser` (keep messages short):

1. Try the configured URL as-is.
2. If the host is `127.0.0.1` or `[::1]`, retry with `localhost` (the server checks the `Host` header).
3. Toggle the `/sse` suffix once (add if missing, remove if present).
4. Report only `cannot connect to <last url>. <next thing to try>` or `config fixed to <url>. reconnect MCP or restart me.` Persist a config change only when the new URL actually connects.

`<next thing to try>`: browser down → `start the browser from the desktop shortcut`; MCP down, browser up → `run: <serviceStartCommand>` from `http://127.0.0.1:8932/status.json`; otherwise `reconfigure shared-browser to <url>`.

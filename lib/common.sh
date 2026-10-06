#!/usr/bin/env bash
# Shared helpers for shared-browser-mcp. Sourced, not executed.
# Nothing in here is organisation-specific; machine specifics come from local.env.

SBM_CONFIG_DIR="${SBM_CONFIG_DIR:-$HOME/.config/playwright-mcp}"
SBM_LOCAL_ENV="$SBM_CONFIG_DIR/local.env"
SBM_STATUS_DIR="$SBM_CONFIG_DIR/status"
SBM_STATUS_JSON="$SBM_STATUS_DIR/status.json"

# shellcheck disable=SC1090
[ -f "$SBM_LOCAL_ENV" ] && . "$SBM_LOCAL_ENV"

# --- runtime variables (names are fixed, values are defaults; override in local.env) ---
: "${PLAYWRIGHT_CDP_PORT:=9223}"
: "${PLAYWRIGHT_CDP_URL:=http://127.0.0.1:${PLAYWRIGHT_CDP_PORT}}"
: "${PLAYWRIGHT_MCP_HOST:=127.0.0.1}"
: "${PLAYWRIGHT_MCP_PORT:=8931}"
: "${PLAYWRIGHT_MCP_URL:=http://localhost:${PLAYWRIGHT_MCP_PORT}}"
: "${PLAYWRIGHT_MCP_NPM_SPEC:=@playwright/mcp@latest}"
: "${PLAYWRIGHT_MCP_SERVER_NAME:=shared-browser}"

# --- browser profile ---
: "${PLAYWRIGHT_MCP_PROFILE_NAME:=AUTOMATION}"
: "${PLAYWRIGHT_MCP_THEME_RGB:=250,223,115}"      # R,G,B accent colour of the automation profile
: "${PLAYWRIGHT_MCP_EXTENSIONS:=}"                 # space-separated Web Store IDs offered for one-click install

# --- updates / supervisor ---
: "${PLAYWRIGHT_MCP_AUTO_UPDATE_BROWSER:=1}"       # 1: stage newer Chrome for Testing in the background
: "${PLAYWRIGHT_MCP_CDP_DOWN_GRACE:=30}"           # seconds without CDP before the supervisor stops MCP
: "${PLAYWRIGHT_MCP_UPDATE_CHECK_INTERVAL:=86400}" # seconds between update checks
: "${PLAYWRIGHT_MCP_STATUS_PORT:=8932}"            # 0 disables the local status endpoint

export PLAYWRIGHT_CDP_URL PLAYWRIGHT_MCP_HOST PLAYWRIGHT_MCP_PORT PLAYWRIGHT_MCP_URL PLAYWRIGHT_MCP_NPM_SPEC

CFT_VERSIONS_URL="https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json"
CFT_LAUNCH_FLAGS="--no-first-run --no-default-browser-check --hide-crash-restore-bubble --new-window about:blank"

SBM_DRIFT=0
SBM_QUIET=0

log()  { [ "$SBM_QUIET" = 1 ] || printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

# report STATUS NAME [DETAIL]  — one line per checked item. STATUS: OK | DRIFT | MISSING | SKIP | INFO
report() {
  local st=$1 name=$2 detail=${3:-}
  case "$st" in DRIFT|MISSING) SBM_DRIFT=1 ;; esac
  [ "$SBM_QUIET" = 1 ] && [ "$st" = OK ] && return 0
  printf '%-8s %-20s %s\n' "$st" "$name" "$detail"
}

need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

sbm_platform() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux)  if grep -qi microsoft /proc/version 2>/dev/null; then echo wsl; else echo linux; fi ;;
    *)      echo unsupported ;;
  esac
}

# --- probes ---
cdp_up() { curl -sS -o /dev/null --max-time 1 "${PLAYWRIGHT_CDP_URL}/json/version" 2>/dev/null; }
cdp_browser() { curl -sS --max-time 1 "${PLAYWRIGHT_CDP_URL}/json/version" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("Browser",""))' 2>/dev/null; }
mcp_up() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "${PLAYWRIGHT_MCP_URL}/mcp" 2>/dev/null)
  case "$code" in 200|400|405|406) return 0 ;; esac
  return 1
}
# version of the @playwright/mcp that is actually running (from its process command line)
mcp_running_version() {
  local bin dir
  bin=$(pgrep -af 'playwright-mcp' 2>/dev/null | grep -o '/[^ ]*node_modules/\.bin/playwright-mcp' | head -1)
  [ -n "$bin" ] || return 1
  dir=${bin%/.bin/playwright-mcp}
  python3 -c "import json;print(json.load(open('$dir/@playwright/mcp/package.json'))['version'])" 2>/dev/null
}
mcp_latest_version() { npm view "$PLAYWRIGHT_MCP_NPM_SPEC" version 2>/dev/null | tail -1; }

# ver_gt A B  -> true if A > B (dotted numeric)
ver_gt() { python3 -c 'import sys; a=[int(x) for x in sys.argv[1].split(".")]; b=[int(x) for x in sys.argv[2].split(".")]; sys.exit(0 if a>b else 1)' "$1" "$2"; }

# --- Chrome for Testing metadata ---
cft_stable_json() { curl -fsS --max-time 20 "$CFT_VERSIONS_URL"; }
cft_stable_version() { cft_stable_json | python3 -c 'import json,sys; print(json.load(sys.stdin)["channels"]["Stable"]["version"])'; }
# cft_download_url VERSION PLATFORM_KEY (win64 | mac-arm64 | mac-x64 | linux64 | linux-arm64)
cft_download_url() { echo "https://storage.googleapis.com/chrome-for-testing-public/$1/$2/chrome-$2.zip"; }
# download URL DEST — curl honours HTTPS_PROXY/NO_PROXY from the environment
download() {
  mkdir -p "$(dirname "$2")"
  curl -fL --retry 3 --retry-delay 2 --progress-bar -o "$2.part" "$1" && mv "$2.part" "$2"
}

# --- profile preferences (Chromium JSON files) ---
# prefs_tool check|apply PROFILE_DIR   — prints "OK|DRIFT name detail" lines in check mode
prefs_tool() {
  python3 - "$1" "$2" "$PLAYWRIGHT_MCP_PROFILE_NAME" "$PLAYWRIGHT_MCP_THEME_RGB" <<'PY'
import json, pathlib, struct, sys
mode, profile, name, rgb = sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3], sys.argv[4]
r, g, b = [int(x) for x in rgb.split(",")]
argb = (255 << 24) | (r << 16) | (g << 8) | b
color = struct.unpack('i', struct.pack('I', argb))[0]
prefs_p = profile / "Default" / "Preferences"
state_p = profile / "Local State"
def load(p):
    try: return json.loads(p.read_text(encoding="utf-8"))
    except FileNotFoundError: return {}
prefs, state = load(prefs_p), load(state_p)
# Chrome drops preferences that equal their default; 5 (new tab page) is the default, so absent == 5.
want = {
  "profile-name":  (prefs.get("profile", {}).get("name"), name),
  "startup":       (prefs.get("session", {}).get("restore_on_startup", 5), 5),
  "theme":         (prefs.get("browser", {}).get("theme", {}).get("user_color2"), color),
}
if mode == "check":
    if not prefs_p.exists():
        print("MISSING profile-prefs no Preferences yet (start the browser once)"); sys.exit(0)
    for k, (have, exp) in want.items():
        print(("OK" if have == exp else "DRIFT"), k, f"{have!r} (want {exp!r})" if have != exp else "")
    sys.exit(0)
# apply
prefs.setdefault("profile", {}).update({"name": name, "using_default_name": False})
prefs.setdefault("session", {})["restore_on_startup"] = 5
theme = prefs.setdefault("browser", {}).setdefault("theme", {})
theme.update({"user_color2": color, "user_color": color, "color_variant2": 1, "color_variant": 1, "follows_system_colors": False})
prefs.setdefault("extensions", {})["theme"] = {"id": "user_color_theme_id"}
prefs_p.parent.mkdir(parents=True, exist_ok=True)
prefs_p.write_text(json.dumps(prefs, separators=(",", ":")), encoding="utf-8")
cache = state.setdefault("profile", {}).setdefault("info_cache", {}).setdefault("Default", {})
cache.update({"name": name, "is_using_default_name": False})
state_p.write_text(json.dumps(state, separators=(",", ":")), encoding="utf-8")
print("prefs written")
PY
}

# extension_installed PROFILE_DIR ID
extension_installed() { [ -d "$1/Default/Extensions/$2" ]; }

# --- status.json ---
status_write() { # KEY=VALUE ... (values are JSON literals or strings)
  mkdir -p "$SBM_STATUS_DIR"
  python3 - "$SBM_STATUS_JSON" "$@" <<'PY'
import json, sys, time, pathlib
p = pathlib.Path(sys.argv[1]); d = {}
try: d = json.loads(p.read_text())
except Exception: pass
for kv in sys.argv[2:]:
    k, _, v = kv.partition("=")
    try: d[k] = json.loads(v)
    except Exception: d[k] = v
d["updatedAt"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
p.write_text(json.dumps(d, indent=2))
PY
}
# status_get KEY[.SUBKEY]
status_get() {
  python3 - "$SBM_STATUS_JSON" "$1" <<'PY' 2>/dev/null
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
for k in sys.argv[2].split("."):
    d = d.get(k, "") if isinstance(d, dict) else ""
print(json.dumps(d) if isinstance(d, (dict, list)) else d)
PY
}

# --- agent client config (Claude Code) ---
claude_mcp_configured() {
  command -v claude >/dev/null 2>&1 || return 2
  python3 - "$HOME/.claude.json" "$PLAYWRIGHT_MCP_SERVER_NAME" "$PLAYWRIGHT_MCP_URL" <<'PY'
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: sys.exit(1)
s = d.get("mcpServers", {}).get(sys.argv[2])
sys.exit(0 if s and s.get("url","").rstrip("/") == sys.argv[3].rstrip("/") else 1)
PY
}
claude_mcp_install() {
  claude mcp add --scope user --transport http "$PLAYWRIGHT_MCP_SERVER_NAME" "$PLAYWRIGHT_MCP_URL" >/dev/null
}

#!/usr/bin/env bash
# Configure Claude Code (CLI + VS Code extension) to use an API key,
# optionally against a custom Anthropic-compatible base URL.
#
# Usage:
#   ./setup-claude-key.sh                                  # interactive prompts
#   ./setup-claude-key.sh -k sk-ant-...                    # Anthropic key
#   ./setup-claude-key.sh -k mykey -u https://my.proxy/   # own AI service
#   ./setup-claude-key.sh -k mykey -u https://... --bearer
#   ./setup-claude-key.sh --uninstall
#
# Supports Linux and macOS. On Windows use setup-claude-key.ps1.

set -euo pipefail

KEY=""
BASE_URL=""
AUTH_MODE="api-key"   # api-key -> ANTHROPIC_API_KEY (x-api-key header)
                      # bearer  -> ANTHROPIC_AUTH_TOKEN (Authorization: Bearer)
NO_SHELL_RC=0
LAUNCH=""
UNINSTALL=0

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
STATE_FILE="$HOME/.claude.json"
[ -n "${CLAUDE_CONFIG_DIR:-}" ] && STATE_FILE="$CLAUDE_CONFIG_DIR/.claude.json"

MARK_BEGIN="# >>> claude-api-key-setup >>>"
MARK_END="# <<< claude-api-key-setup <<<"

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
  cat <<EOF

Options:
  -k, --key KEY        API key / token (prompted if omitted)
  -u, --url URL        Custom API base URL (omit for api.anthropic.com)
      --bearer         Send key as ANTHROPIC_AUTH_TOKEN (Bearer) instead of
                       ANTHROPIC_API_KEY. Many proxies / gateways need this.
      --no-shell-rc    Don't touch ~/.bashrc / ~/.zshrc
      --launch         Launch 'claude' when done (no prompt)
      --no-launch      Don't launch 'claude' when done (no prompt)
      --uninstall      Remove everything this script added
  -h, --help           Show this help
EOF
}

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m ✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m !\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31m ✗\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    -k|--key)      KEY="${2:-}"; shift 2 ;;
    -u|--url)      BASE_URL="${2:-}"; shift 2 ;;
    --bearer)      AUTH_MODE="bearer"; shift ;;
    --no-shell-rc) NO_SHELL_RC=1; shift ;;
    --launch)      LAUNCH=1; shift ;;
    --no-launch)   LAUNCH=0; shift ;;
    --uninstall)   UNINSTALL=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
done

# ---------------------------------------------------------------------------
# JSON editing helper: python3, falling back to node. Secrets are passed via
# environment variables, never on the command line (keeps them out of `ps`).
# ---------------------------------------------------------------------------
run_json_edit() {
  # $1 = python source, $2 = equivalent node source
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "$1"
  elif command -v node >/dev/null 2>&1; then
    node -e "$2"
  else
    die "Need python3 or node to edit JSON config files. Install one, or follow MANUAL_SETUP.md."
  fi
}

PY_HELPERS='
import json, os, sys
def load(p):
    try:
        with open(p) as f:
            t = f.read().strip()
            return json.loads(t) if t else {}
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError as e:
        sys.exit("Invalid JSON in %s: %s" % (p, e))
def save(p, d):
    tmp = p + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f, indent=2); f.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, p)
'
JS_HELPERS='
const fs = require("fs");
function load(p) {
  if (!fs.existsSync(p)) return {};
  const t = fs.readFileSync(p, "utf8").trim();
  if (!t) return {};
  try { return JSON.parse(t); } catch (e) { console.error(`Invalid JSON in ${p}: ${e.message}`); process.exit(1); }
}
function save(p, d) {
  const tmp = p + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(d, null, 2) + "\n", { mode: 0o600 });
  fs.renameSync(tmp, p);
}
'

backup() {
  [ -f "$1" ] || return 0
  cp -p "$1" "$1.bak.$(date +%Y%m%d%H%M%S)"
}

# Strip our marked block from a shell rc file.
strip_rc_block() {
  local rc="$1"
  [ -f "$rc" ] || return 0
  grep -qF "$MARK_BEGIN" "$rc" || return 0
  local tmp; tmp="$(mktemp)"
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    !skip' "$rc" > "$tmp"
  cat "$tmp" > "$rc"   # preserve original file perms/ownership
  rm -f "$tmp"
}

shell_rc_files() {
  local files=("$HOME/.bashrc")
  [ -f "$HOME/.zshrc" ] || [ "$(basename "${SHELL:-}")" = "zsh" ] && files+=("$HOME/.zshrc")
  # macOS login shells read .bash_profile, not .bashrc
  [ "$(uname)" = "Darwin" ] && [ -f "$HOME/.bash_profile" ] && files+=("$HOME/.bash_profile")
  printf '%s\n' "${files[@]}"
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
if [ "$UNINSTALL" = 1 ]; then
  info "Removing Claude API key configuration"
  while IFS= read -r rc; do
    strip_rc_block "$rc" && ok "Cleaned $rc"
  done < <(shell_rc_files)

  if [ -f "$SETTINGS_FILE" ]; then
    backup "$SETTINGS_FILE"
    SETTINGS_FILE="$SETTINGS_FILE" run_json_edit "$PY_HELPERS
p = os.environ['SETTINGS_FILE']; d = load(p)
env = d.get('env', {})
for k in ('ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_BASE_URL'):
    env.pop(k, None)
if env: d['env'] = env
else: d.pop('env', None)
save(p, d)" "$JS_HELPERS
const p = process.env.SETTINGS_FILE, d = load(p), env = d.env || {};
for (const k of ['ANTHROPIC_API_KEY','ANTHROPIC_AUTH_TOKEN','ANTHROPIC_BASE_URL']) delete env[k];
if (Object.keys(env).length) d.env = env; else delete d.env;
save(p, d);"
    ok "Removed keys from $SETTINGS_FILE"
  fi
  warn "Open a new terminal (or run: unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL)"
  exit 0
fi

# ---------------------------------------------------------------------------
# Gather input
# ---------------------------------------------------------------------------
if [ -z "$KEY" ]; then
  [ -t 0 ] || die "No key given. Use -k KEY or run interactively."
  read -r -s -p "Enter your Claude API key (input hidden): " KEY; echo
  if [ -z "$BASE_URL" ]; then
    read -r -p "Custom API base URL (leave empty for Anthropic default): " BASE_URL
  fi
  if [ -n "$BASE_URL" ] && [ "$AUTH_MODE" = "api-key" ]; then
    read -r -p "Does your service expect 'Authorization: Bearer' auth? [y/N]: " ans
    case "$ans" in [yY]*) AUTH_MODE="bearer" ;; esac
  fi
fi

KEY="$(printf '%s' "$KEY" | tr -d '[:space:]')"
BASE_URL="$(printf '%s' "$BASE_URL" | tr -d '[:space:]')"
BASE_URL="${BASE_URL%/}"

[ -n "$KEY" ] || die "API key is empty."
[ "${#KEY}" -ge 20 ] || warn "Key is shorter than 20 characters; is it complete?"
if [ -n "$BASE_URL" ]; then
  case "$BASE_URL" in
    http://*|https://*) ;;
    *) die "Base URL must start with http:// or https://" ;;
  esac
elif [ "${KEY#sk-ant-}" = "$KEY" ]; then
  warn "Key doesn't start with 'sk-ant-'. If it's for another service, pass -u URL."
fi

if [ "$AUTH_MODE" = "bearer" ]; then
  KEY_VAR="ANTHROPIC_AUTH_TOKEN"; OTHER_VAR="ANTHROPIC_API_KEY"
else
  KEY_VAR="ANTHROPIC_API_KEY";    OTHER_VAR="ANTHROPIC_AUTH_TOKEN"
fi

mkdir -p "$CLAUDE_DIR"

# ---------------------------------------------------------------------------
# 1. Shell rc files (so `claude` in a terminal sees the key)
# ---------------------------------------------------------------------------
shell_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

if [ "$NO_SHELL_RC" = 0 ]; then
  info "Updating shell startup files"
  while IFS= read -r rc; do
    touch "$rc"
    strip_rc_block "$rc"
    {
      echo "$MARK_BEGIN"
      echo "export $KEY_VAR=$(shell_quote "$KEY")"
      echo "unset $OTHER_VAR"
      if [ -n "$BASE_URL" ]; then
        echo "export ANTHROPIC_BASE_URL=$(shell_quote "$BASE_URL")"
      else
        echo "unset ANTHROPIC_BASE_URL"
      fi
      echo "$MARK_END"
    } >> "$rc"
    ok "$rc"
  done < <(shell_rc_files)
fi

# ---------------------------------------------------------------------------
# 2. ~/.claude/settings.json "env" block (used by CLI *and* VS Code extension,
#    even when VS Code is launched from the desktop and never reads .bashrc)
# ---------------------------------------------------------------------------
info "Writing $SETTINGS_FILE"
backup "$SETTINGS_FILE"
SETTINGS_FILE="$SETTINGS_FILE" CK_KEY="$KEY" CK_URL="$BASE_URL" \
CK_VAR="$KEY_VAR" CK_OTHER="$OTHER_VAR" run_json_edit "$PY_HELPERS
p = os.environ['SETTINGS_FILE']; d = load(p)
env = d.get('env') or {}
env[os.environ['CK_VAR']] = os.environ['CK_KEY']
env.pop(os.environ['CK_OTHER'], None)
if os.environ['CK_URL']: env['ANTHROPIC_BASE_URL'] = os.environ['CK_URL']
else: env.pop('ANTHROPIC_BASE_URL', None)
d['env'] = env
save(p, d)" "$JS_HELPERS
const e = process.env, p = e.SETTINGS_FILE, d = load(p), env = d.env || {};
env[e.CK_VAR] = e.CK_KEY;
delete env[e.CK_OTHER];
if (e.CK_URL) env.ANTHROPIC_BASE_URL = e.CK_URL; else delete env.ANTHROPIC_BASE_URL;
d.env = env;
save(p, d);"
ok "env.$KEY_VAR set${BASE_URL:+, env.ANTHROPIC_BASE_URL=$BASE_URL}"

# ---------------------------------------------------------------------------
# 3. ~/.claude.json: pre-approve the key (skips the "Detected a custom API
#    key... use this key?" prompt) and mark onboarding complete.
#    Claude Code identifies approved keys by their last 20 characters.
# ---------------------------------------------------------------------------
info "Pre-approving key in $STATE_FILE"
backup "$STATE_FILE"
STATE_FILE="$STATE_FILE" CK_KEY="$KEY" run_json_edit "$PY_HELPERS
p = os.environ['STATE_FILE']; d = load(p)
tail = os.environ['CK_KEY'][-20:]
r = d.get('customApiKeyResponses') or {}
approved = [x for x in r.get('approved', []) if x != tail] + [tail]
r['approved'] = approved
r['rejected'] = [x for x in r.get('rejected', []) if x != tail]
d['customApiKeyResponses'] = r
d['hasCompletedOnboarding'] = True
save(p, d)" "$JS_HELPERS
const p = process.env.STATE_FILE, d = load(p), tail = process.env.CK_KEY.slice(-20);
const r = d.customApiKeyResponses || {};
r.approved = (r.approved || []).filter(x => x !== tail).concat([tail]);
r.rejected = (r.rejected || []).filter(x => x !== tail);
d.customApiKeyResponses = r;
d.hasCompletedOnboarding = true;
save(p, d);"
ok "Key approved (…${KEY: -4}), onboarding marked complete"

# ---------------------------------------------------------------------------
# 4. Load into this process & finish
# ---------------------------------------------------------------------------
export "$KEY_VAR=$KEY"; unset "$OTHER_VAR"
if [ -n "$BASE_URL" ]; then export ANTHROPIC_BASE_URL="$BASE_URL"; else unset ANTHROPIC_BASE_URL; fi

echo
ok "Setup complete."
cat <<EOF

Next steps:
  • Reload your shell:   source ~/.bashrc     (or open a new terminal)
  • VS Code:             fully quit and reopen VS Code so the Claude Code
                         extension picks up ~/.claude/settings.json
  • Check status:        run 'claude' then type /status

EOF

if ! command -v claude >/dev/null 2>&1; then
  warn "'claude' not found on PATH. Install it: curl -fsSL https://claude.ai/install.sh | bash"
  exit 0
fi

if [ -z "$LAUNCH" ] && [ -t 0 ]; then
  read -r -p "Launch claude now to confirm it works? [Y/n]: " ans
  case "$ans" in [nN]*) LAUNCH=0 ;; *) LAUNCH=1 ;; esac
fi
[ "$LAUNCH" = 1 ] && exec claude
exit 0

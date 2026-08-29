#!/bin/bash
# Claude Code SessionStart bootstrap — canonical copy lives in
# cr-calleja-software/claude-toolkit at bootstrap/session-start.sh.
#
# WHY THIS EXISTS
# In Claude Code on the web, a repo's `.claude/settings.json` is only half
# honoured: `enabledPlugins` resolves, but `extraKnownMarketplaces` is ignored,
# so a marketplace declared there is never fetched and any plugin from it fails
# to load — silently. This hook makes the declaration real by registering each
# marketplace and installing each enabled plugin at session start.
#
# It is deliberately repo-agnostic: everything it acts on is read from the
# consuming repo's own `.claude/settings.json`, so this file is byte-identical
# in every repo and never needs editing. Add a marketplace or a plugin to
# settings.json and the next session picks it up.
#
# It also keeps things current: a marketplace this repo declares is refreshed
# each session, and a plugin from one of those marketplaces is updated when the
# marketplace publishes a newer version. Without that a machine stays pinned to
# whatever version it first installed, forever — and would not even see a newer
# one, because `claude plugin update` reads the cached marketplace clone.
# Marketplaces this repo does not declare (the official one) are left alone;
# Claude Code manages those, and refreshing them would add latency to every
# session start for no benefit here.
#
# It runs everywhere — web and local alike. Local machines drift into the same
# broken state (removing a marketplace takes its plugin installs with it, and
# re-adding the marketplace does not restore them), and a session that silently
# lacks its commands is the same problem wherever it happens. Set
# CLAUDE_BOOTSTRAP_SKIP=1 to opt out for a session — useful while developing the
# toolkit against a local-path marketplace registration.
#
# INSTALL (per consuming repo)
#   1. cp bootstrap/session-start.sh <repo>/.claude/hooks/session-start.sh
#   2. chmod +x <repo>/.claude/hooks/session-start.sh
#   3. register it in <repo>/.claude/settings.json:
#        "hooks": {"SessionStart": [{"hooks": [{"type": "command",
#          "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/session-start.sh"}]}]}
#
# It never fails a session: every failure path warns on stderr and exits 0.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SETTINGS="${PROJECT_DIR}/.claude/settings.json"

log()  { echo "claude-bootstrap: $*"; }
warn() { echo "claude-bootstrap: $*" >&2; }

[ -z "${CLAUDE_BOOTSTRAP_SKIP:-}" ] || exit 0
[ -f "$SETTINGS" ] || exit 0

command -v claude >/dev/null 2>&1 || { warn "claude CLI not on PATH; skipping"; exit 0; }
command -v python3 >/dev/null 2>&1 || { warn "python3 not available; cannot read settings.json, skipping"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
claude plugin marketplace list --json >"$tmp/marketplaces.json" 2>/dev/null || echo '[]' >"$tmp/marketplaces.json"
claude plugin list --json            >"$tmp/plugins.json"      2>/dev/null || echo '[]' >"$tmp/plugins.json"

# Diff what settings.json declares against what is already present, and print
# one tab-separated action per line. Nothing to do prints nothing.
#
# The planner is written out and then run, rather than piped into python3 from a
# heredoc inside $(...). bash 3.2 — still /bin/bash on macOS — mis-parses a
# heredoc inside command substitution and reads an apostrophe in the body as an
# opening quote, failing the whole script with "unexpected EOF".
cat >"$tmp/plan.py" <<'PY'
import json, sys

def load(path, fallback):
    try:
        with open(path) as fh:
            return json.load(fh)
    except Exception:
        return fallback

settings   = load(sys.argv[1], {})
registered = load(sys.argv[2], [])
installed  = load(sys.argv[3], [])

def field(entries, key):
    return {e[key] for e in entries
            if isinstance(e, dict) and isinstance(e.get(key), str)} \
           if isinstance(entries, list) else set()

known_marketplaces = field(registered, "name")
known_plugins      = field(installed, "id")

declared = settings.get("extraKnownMarketplaces") or {}

for name, entry in declared.items():
    if name in known_marketplaces:
        # Already registered: pull the catalogue so a newer plugin version is
        # visible to `claude plugin update` below.
        print("refresh\t%s\t" % name)
        continue
    source = entry.get("source") or {}
    # A marketplace is declared as a github repo, a URL, or a local path.
    ref = source.get("repo") or source.get("url") or source.get("path")
    if ref:
        print("marketplace\t%s\t%s" % (name, ref))
    else:
        print("skip\t%s\tunrecognised marketplace source" % name)

enabled_plugins = settings.get("enabledPlugins") or {}

def marketplace_of(plugin_id):
    return plugin_id.split("@", 1)[1] if "@" in plugin_id else ""

for plugin_id, enabled in enabled_plugins.items():
    if not enabled:
        continue
    marketplace = marketplace_of(plugin_id)
    if plugin_id not in known_plugins:
        print("plugin\t%s\t" % plugin_id)
    elif marketplace in declared:
        # Installed already, and from a marketplace this repo declares, so
        # keeping it current is the job of this hook.
        print("update\t%s\t" % plugin_id)
    elif marketplace not in known_marketplaces:
        print("warn\t%s\tenabled but its marketplace %s is neither declared in "
              "extraKnownMarketplaces nor registered, so it cannot be resolved"
              % (plugin_id, marketplace or "?"))

# Drift the other way: something installed from a marketplace this repo declares
# but no longer named in enabledPlugins is out of reach for this hook entirely -
# it will never be updated and will not be reinstalled if it goes missing. The
# usual cause is a plugin CLI command rewriting the tracked settings.json.
for plugin_id in sorted(known_plugins):
    if marketplace_of(plugin_id) in declared and plugin_id not in enabled_plugins:
        print("warn\t%s\tinstalled from a marketplace this repo declares but "
              "absent from enabledPlugins in settings.json, so it is not managed "
              "here - check git diff on that file" % plugin_id)
PY

plan="$(python3 "$tmp/plan.py" "$SETTINGS" "$tmp/marketplaces.json" "$tmp/plugins.json")" \
  || { warn "could not read $SETTINGS; skipping"; exit 0; }

if [ -n "${CLAUDE_BOOTSTRAP_DEBUG:-}" ]; then
  log "settings: $SETTINGS"
  if [ -n "$plan" ]; then
    log "plan:"
    printf '%s\n' "$plan" | sed 's/^/  /'
  else
    log "plan: nothing to do"
  fi
fi

[ -n "$plan" ] || exit 0

while IFS=$'\t' read -r action name ref; do
  [ -n "${action:-}" ] || continue
  case "$action" in
    marketplace)
      if claude plugin marketplace add "$ref" >/dev/null 2>&1; then
        log "registered marketplace $name ($ref)"
      else
        warn "could not register marketplace $name ($ref); its plugins will not load"
      fi
      ;;
    refresh)
      # Routine, so it is silent unless it fails.
      claude plugin marketplace update "$name" >/dev/null 2>&1 \
        || warn "could not refresh marketplace $name; plugin updates may be missed"
      ;;
    plugin)
      if claude plugin install --yes "$name" >/dev/null 2>&1; then
        log "installed plugin $name"
      else
        warn "could not install plugin $name; its commands and skills will not load"
      fi
      ;;
    update)
      # Quiet when already current; only a real version change is worth a line.
      if out="$(claude plugin update "$name" 2>&1)"; then
        case "$out" in
          *"updated from"*) log "updated plugin $name — restart to apply" ;;
        esac
      else
        warn "could not update plugin $name; it stays at the installed version"
      fi
      ;;
    skip|warn)
      warn "$name: $ref"
      ;;
  esac
done <<< "$plan"

exit 0

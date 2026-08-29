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
plan="$(python3 - "$SETTINGS" "$tmp/marketplaces.json" "$tmp/plugins.json" <<'PY'
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

for name, entry in (settings.get("extraKnownMarketplaces") or {}).items():
    if name in known_marketplaces:
        continue
    source = entry.get("source") or {}
    # A marketplace is declared as a github repo, a URL, or a local path.
    ref = source.get("repo") or source.get("url") or source.get("path")
    if ref:
        print("marketplace\t%s\t%s" % (name, ref))
    else:
        print("skip\t%s\tunrecognised marketplace source" % name)

for plugin_id, enabled in (settings.get("enabledPlugins") or {}).items():
    if enabled and plugin_id not in known_plugins:
        print("plugin\t%s\t" % plugin_id)
PY
)" || { warn "could not read $SETTINGS; skipping"; exit 0; }

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
    plugin)
      if claude plugin install --yes "$name" >/dev/null 2>&1; then
        log "installed plugin $name"
      else
        warn "could not install plugin $name; its commands and skills will not load"
      fi
      ;;
    skip)
      warn "$name: $ref"
      ;;
  esac
done <<< "$plan"

exit 0

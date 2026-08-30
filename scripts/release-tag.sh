#!/bin/bash
# Tag a merged plugin release from main.
#
# WHY THIS EXISTS
# Merging to main is the release — consumers install from the default branch and
# never see a tag. Tagging is therefore the step nothing depends on, which is
# exactly why it gets skipped: 0.3.1 shipped and its tag was missed outright, and
# nothing anywhere surfaced that. This script makes the flow in CLAUDE.md one
# command, and `--check` reports drift so a missed tag is findable rather than
# invisible — deliberately by asking the remote, never by trusting a note here.
#
# It refuses rather than guesses. Every failure path explains what to do instead:
#
#   - not on main, or main behind origin  → a tag cut here points at a commit
#     that is not what consumers install
#   - dirty tree                          → the tag would not describe the tree
#   - tag already on the remote           → never move a published tag; cut a new
#     patch version so anyone who read the old tag still sees what it pointed at
#
# USAGE
#   scripts/release-tag.sh [--check] [--yes] [<plugin-dir>]
#
#   --check   report whether the version on main is already tagged, then exit.
#             Read-only: no fetch of tags into refs, no tag, no push.
#   --yes     skip the confirmation prompt (for non-interactive use)
#   <plugin-dir>  defaults to plugins/cr
#
# Held to the same bash 3.2 floor as bootstrap/session-start.sh — macOS ships 3.2
# as /bin/bash and these repos are developed on Macs. No bash 4+ syntax, and no
# heredoc inside $(...).
set -uo pipefail

PLUGIN_DIR="plugins/cr"
CHECK_ONLY=""
ASSUME_YES=""

die()  { echo "release-tag: $*" >&2; exit 1; }
note() { echo "release-tag: $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    # Print the header block, stopping at the first non-comment line, so editing
    # the header can never leak code into --help or truncate the usage notes.
    -h|--help) awk 'NR>1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    -*) die "unknown option $1 (try --help)" ;;
    *)  PLUGIN_DIR="$1" ;;
  esac
  shift
done

command -v claude  >/dev/null 2>&1 || die "the claude CLI is not on PATH"
command -v python3 >/dev/null 2>&1 || die "python3 is not available; cannot read the plugin manifest"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "not inside a git repository"
cd "$REPO_ROOT" || die "could not enter $REPO_ROOT"

MANIFEST="${PLUGIN_DIR}/.claude-plugin/plugin.json"
[ -f "$MANIFEST" ] || die "no plugin manifest at $MANIFEST"

# One python call, two lines out — name then version.
META="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["name"]); print(d["version"])' "$MANIFEST" 2>/dev/null)" \
  || die "could not read name/version from $MANIFEST"

NAME="$(printf '%s\n' "$META" | sed -n 1p)"
VERSION="$(printf '%s\n' "$META" | sed -n 2p)"
[ -n "$NAME" ] && [ -n "$VERSION" ] || die "name or version missing from $MANIFEST"

TAG="${NAME}--v${VERSION}"

# Does the remote already carry this tag? ls-remote queries the remote directly
# and writes nothing locally, so this stays safe under --check.
remote_has_tag() {
  git ls-remote --tags origin "refs/tags/$1" 2>/dev/null | grep -q .
}

if [ -n "$CHECK_ONLY" ]; then
  if remote_has_tag "$TAG"; then
    note "$TAG is on the remote — $PLUGIN_DIR $VERSION is tagged"
    exit 0
  fi
  note "$TAG is NOT on the remote — $PLUGIN_DIR $VERSION is untagged"
  note "if $VERSION is merged to main, run: scripts/release-tag.sh $PLUGIN_DIR"
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ "$BRANCH" = "main" ] \
  || die "on branch '$BRANCH', not main — a tag cut here would point at a pre-merge commit that is not what consumers install. git checkout main && git pull, then re-run"

[ -z "$(git status --porcelain 2>/dev/null)" ] \
  || die "working tree is dirty — commit or stash first, so the tag describes the tree it names"

git fetch --quiet origin main 2>/dev/null \
  || die "could not fetch origin/main; check the network and re-run"

LOCAL="$(git rev-parse HEAD 2>/dev/null)"
REMOTE="$(git rev-parse FETCH_HEAD 2>/dev/null)"
if [ "$LOCAL" != "$REMOTE" ]; then
  if git merge-base --is-ancestor "$LOCAL" "$REMOTE" 2>/dev/null; then
    die "local main is behind origin/main — git pull first, or the tag misses the commit you mean to release"
  fi
  die "local main has diverged from origin/main — reconcile before tagging"
fi

if remote_has_tag "$TAG"; then
  die "$TAG is already on the remote. Never move a published tag — anyone who read it should still see what it pointed at. Bump a new patch version, merge that, then tag it"
fi

note "plugin:  $PLUGIN_DIR"
note "version: $VERSION"
note "tag:     $TAG"
note "commit:  $(git rev-parse --short HEAD) $(git log -1 --pretty=%s)"
echo

claude plugin tag "$PLUGIN_DIR" --dry-run || die "dry run failed; not tagging"
echo

if [ -z "$ASSUME_YES" ]; then
  printf 'release-tag: create and push %s? [y/N] ' "$TAG"
  read -r reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) note "aborted; nothing was pushed"; exit 1 ;;
  esac
fi

claude plugin tag "$PLUGIN_DIR" --push || die "tagging failed; nothing was pushed"

if remote_has_tag "$TAG"; then
  note "$TAG is on the remote"
  exit 0
fi
die "$TAG did not appear on the remote — check 'git ls-remote --tags origin' and push it by hand if needed"

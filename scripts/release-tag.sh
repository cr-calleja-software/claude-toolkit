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
# .github/workflows/release-tag.yml runs it on every push to main, so the tag now
# lands without anyone remembering: --check first, then the tagging path only when
# --check reports the released version untagged. Running it by hand is unchanged,
# and stays the way to tag a release the workflow could not.
#
# TAG FORMAT
# Tags are v<version> — v0.4.0. `claude plugin tag` can only produce its own
# {name}--v{version} form with no way to override it, so this script runs that
# command for its manifest check only and creates the tag itself. The two tags
# already on the remote, cr--v0.3.0 and cr--v0.3.1, keep the old name; the
# format changes from 0.4.0 onwards rather than rewriting published history.
#
# Because the plugin name is no longer in the tag, it moves to the annotation
# message (`cr <version>`). A second plugin in this repo would collide on
# v<version> and would need the prefix back.
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
#   scripts/release-tag.sh [--check] [--yes] [--no-cli-check] [<plugin-dir>]
#
#   --check   report whether the version on main is already tagged, then exit.
#             Reads the version from origin/main, not the working tree — on a
#             branch here the tree is always bumped past what is released.
#             Creates nothing: fetches main with --no-tags, never tags or pushes,
#             and needs only git and python3, not the claude CLI.
#   --yes     skip the confirmation prompt (for non-interactive use). It never
#             skips a safety check — those refuse regardless.
#   --no-cli-check
#             do not require the claude CLI, and skip its `plugin tag --dry-run`.
#             The built-in manifest check still runs — it runs on every tagging
#             path, so no route to a tag is left without one. For CI runners,
#             which have no claude CLI; from a terminal you have one, so do not
#             pass this.
#   <plugin-dir>  defaults to plugins/cr; giving two is an error
#
# EXIT CODES
#   0  tagged (--check), or the tag was created and pushed
#   2  --check only: the version on main is untagged — the signal, not an error
#   1  something went wrong, or the user declined at the prompt
#
# 2 exists so a CI job or pre-flight hook can tell an untagged release from a
# broken run: a missing tag and an unreachable remote must not look alike.
#
# Held to the same bash 3.2 floor as bootstrap/session-start.sh — macOS ships 3.2
# as /bin/bash and these repos are developed on Macs. No bash 4+ syntax, and no
# heredoc inside $(...).
set -uo pipefail

PLUGIN_DIR="plugins/cr"
CHECK_ONLY=""
ASSUME_YES=""
NO_CLI_CHECK=""

die()  { echo "release-tag: $*" >&2; exit 1; }
note() { echo "release-tag: $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --no-cli-check) NO_CLI_CHECK=1 ;;
    # Print the header block, stopping at the first non-comment line, so editing
    # the header can never leak code into --help or truncate the usage notes.
    -h|--help) awk 'NR>1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    -*) die "unknown option $1 (try --help)" ;;
    *)  [ -z "${PLUGIN_DIR_SET:-}" ] || die "only one plugin directory may be given"
        PLUGIN_DIR="$1"; PLUGIN_DIR_SET=1 ;;
  esac
  shift
done

command -v python3 >/dev/null 2>&1 || die "python3 is not available; cannot read the plugin manifest"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "not inside a git repository"
cd "$REPO_ROOT" || die "could not enter $REPO_ROOT"

MANIFEST="${PLUGIN_DIR}/.claude-plugin/plugin.json"
MARKETPLACE=".claude-plugin/marketplace.json"

# Name then version, one per line. Takes a path, or - for stdin.
read_meta() {
  python3 -c 'import json,sys; d=json.load(sys.stdin if sys.argv[1] == "-" else open(sys.argv[1])); print(d["name"]); print(d["version"])' "$1"
}

# Which tag, if any, does the remote already carry for this version? Prints its
# name, or nothing.
#
# Both naming schemes count. Releases before the rename are cr--v<version>, and
# calling one of those untagged would be exactly the wrong answer from the tool
# whose job is knowing. It also keeps the tagging path from publishing a second
# tag for a version that already has one under its old name.
#
# A transport failure must never read as "absent": this is the one thing the
# script exists to be trustworthy about.
#
# It returns 1 rather than calling die, because every caller invokes it inside
# $(...) — and there die would only exit the substitution's subshell, leaving the
# parent to carry on with an empty result that reads as "no tag". The exit status
# is the one channel a command substitution propagates, so callers must use
# `FOUND="$(remote_tag_for_version)" || exit 1`: the `||` binds to the
# assignment, whose status is the substitution's.
#
# Empty output with status 0 means "reached the remote, no tag there". Status 1
# means "could not tell" — never the same thing.
remote_tag_for_version() {
  local out
  out="$(git ls-remote --tags origin "refs/tags/v${VERSION}" "refs/tags/${NAME}--v${VERSION}" 2>&1)" || {
    echo "release-tag: could not reach origin to check tags: $out" >&2
    return 1
  }
  printf '%s\n' "$out" \
    | sed -n 's|.*[[:space:]]refs/tags/||p' \
    | sed 's|\^{}$||' \
    | sort -u \
    | sed -n 1p
}

# Does the catalogue actually carry this plugin, at the directory whose version we
# are about to name? A tag cut while plugin.json and the marketplace entry
# disagree names a release consumers cannot resolve.
#
# `claude plugin tag --dry-run` is the richer answer and stays the default, but it
# needs the claude CLI, which a CI runner has not got. This is the part of it that
# has to hold before a tag is created, in git and python3 alone, so the tagging
# path can run somewhere the CLI does not.
#
# The program is `python3 -c` with a single-quoted, apostrophe-free body rather
# than a heredoc — the bash 3.2 rule at the foot of this header, kept even where
# no $(...) is in sight so reintroducing one later cannot be fatal. It reports by
# exit status, so callers use it as a plain command, never inside $(...).
manifest_check() {
  python3 -c '
import json, os, sys

mkt, man, pdir = sys.argv[1], sys.argv[2], sys.argv[3]

def die(msg):
    sys.stderr.write("release-tag: " + msg + "\n")
    raise SystemExit(1)

def load(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except Exception as err:
        die("could not read " + path + ": " + str(err))

market = load(mkt)
plugin = load(man)

name = plugin.get("name")
version = plugin.get("version")

entries = [e for e in (market.get("plugins") or [])
           if isinstance(e, dict) and e.get("name") == name]
if not entries:
    die(mkt + " has no entry named " + repr(name) + " -- the plugin is not in the catalogue this repo publishes")
if len(entries) > 1:
    die(mkt + " has " + str(len(entries)) + " entries named " + repr(name))

entry = entries[0]
source = entry.get("source")
if not isinstance(source, str):
    die("the " + repr(name) + " marketplace entry has no string source")
if os.path.realpath(source) != os.path.realpath(pdir):
    die("the " + repr(name) + " marketplace entry points at " + source + ", not " + pdir)

# Entries carry no version today. If one ever does, it has to agree.
declared = entry.get("version")
if declared is not None and declared != version:
    die("the " + repr(name) + " marketplace entry says version " + repr(declared) + ", plugin.json says " + repr(version))
' "$MARKETPLACE" "$MANIFEST" "$PLUGIN_DIR"
}

# --check answers "is the released version tagged?", so it reads the version from
# origin/main — not the working tree, which on any branch here has already been
# bumped past what is released. Exit 0 tagged, 2 untagged, 1 anything went wrong,
# so a caller can tell a real signal from a broken run.
if [ -n "$CHECK_ONLY" ]; then
  git fetch --quiet --no-tags origin main 2>/dev/null \
    || die "could not fetch origin/main; --check reports on main and cannot answer offline"

  META="$(git show "FETCH_HEAD:${MANIFEST}" 2>/dev/null | read_meta -)" \
    || die "could not read $MANIFEST from origin/main"

  NAME="$(printf '%s\n' "$META" | sed -n 1p)"
  VERSION="$(printf '%s\n' "$META" | sed -n 2p)"
  [ -n "$NAME" ] && [ -n "$VERSION" ] || die "name or version missing from $MANIFEST on origin/main"
  TAG="v${VERSION}"

  FOUND="$(remote_tag_for_version)" || exit 1
  if [ -n "$FOUND" ]; then
    note "$FOUND is on the remote — $PLUGIN_DIR $VERSION (on main) is tagged"
    exit 0
  fi
  note "no tag on the remote for $PLUGIN_DIR $VERSION (on main) — expected $TAG"
  note "to tag it: git checkout main && git pull && scripts/release-tag.sh $PLUGIN_DIR"
  exit 2
fi

[ -n "$NO_CLI_CHECK" ] || command -v claude >/dev/null 2>&1 \
  || die "the claude CLI is not on PATH. Install it, or pass --no-cli-check to tag without it — the built-in manifest check runs either way (that is what CI does)"

[ -f "$MANIFEST" ] || die "no plugin manifest at $MANIFEST"

META="$(read_meta "$MANIFEST" 2>/dev/null)" \
  || die "could not read name/version from $MANIFEST"

NAME="$(printf '%s\n' "$META" | sed -n 1p)"
VERSION="$(printf '%s\n' "$META" | sed -n 2p)"
[ -n "$NAME" ] && [ -n "$VERSION" ] || die "name or version missing from $MANIFEST"

TAG="v${VERSION}"

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
  die "local main is ahead of or has diverged from origin/main — push or reconcile before tagging, or the tag names a commit consumers cannot install"
fi

FOUND="$(remote_tag_for_version)" || exit 1
if [ -n "$FOUND" ]; then
  die "$VERSION is already tagged on the remote as $FOUND. Never move or duplicate a published tag — anyone who read it should still see what it pointed at. Bump a new patch version, merge that, then tag it"
fi

note "plugin:  $PLUGIN_DIR"
note "version: $VERSION"
note "tag:     $TAG"
note "commit:  $(git rev-parse --short HEAD) $(git log -1 --pretty=%s)"
echo

# Unconditional: every path to a tag passes through this, --no-cli-check included.
manifest_check || die "manifest check failed; not tagging"
note "manifest check passed (the $NAME entry in $MARKETPLACE resolves to $PLUGIN_DIR)"

# The CLI's tag command, as a dry run, is the fuller check layered on top — it
# validates both manifests, not just the one relationship above. Its output names
# a {name}--v{version} tag we do not use, so surface it only on failure. This is
# the only check --no-cli-check waives, and it is waived because a runner has no
# claude CLI, never to get past a failing one.
if [ -n "$NO_CLI_CHECK" ]; then
  note "skipped the claude CLI manifest check (--no-cli-check)"
elif ! CLI_CHECK="$(claude plugin tag "$PLUGIN_DIR" --dry-run 2>&1)"; then
  printf '%s\n' "$CLI_CHECK" >&2
  die "manifest check failed; not tagging"
else
  note "claude CLI manifest check passed (plugin.json agrees with the marketplace entry)"
fi

git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 \
  && die "$TAG already exists locally but not on the remote — delete it with 'git tag -d $TAG' if it was a mistake, then re-run"

if [ -z "$ASSUME_YES" ]; then
  printf 'release-tag: create and push %s? [y/N] ' "$TAG"
  read -r reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) note "aborted; nothing was pushed"; exit 1 ;;
  esac
fi

git tag -a "$TAG" -m "${NAME} ${VERSION}" \
  || die "could not create tag $TAG"

if ! git push origin "refs/tags/$TAG"; then
  git tag -d "$TAG" >/dev/null 2>&1
  die "push failed; removed the local tag so a re-run starts clean"
fi

PUSHED="$(remote_tag_for_version)" || exit 1
if [ -n "$PUSHED" ]; then
  note "$TAG is on the remote"
  exit 0
fi
die "$TAG did not appear on the remote — check 'git ls-remote --tags origin' and push it by hand if needed"

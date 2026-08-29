# Working in claude-toolkit

This repo is a Claude Code **plugin marketplace**, not an application. Its
consumers are other repos (`good-news`, `festa-tracker`, `lanca-mt`) that
install the `cr` plugin and get slash commands and skills from it. A change
here ships to all of them, so the rules below are stricter than they would be
in a normal repo.

Read the README for what the plugin contains and the `.claude/project.md`
contract. This file covers the rules that apply to **every change**.

## Versioning is mandatory

**Every change under `plugins/cr/` bumps `version` in
`plugins/cr/.claude-plugin/plugin.json`, in the same commit as the change.**

Never leave the bump for a reviewer or a follow-up commit — an unbumped change
is indistinguishable, to a consuming repo, from no change at all. Bump exactly
once per PR: if you already bumped in an earlier commit on the same branch,
edit that number rather than bumping again.

Pick the part to increment from what the change does to a repo that is already
using the plugin today, with a `.claude/project.md` it wrote for the current
contract.

### MAJOR — an existing consumer breaks or silently misbehaves

They must change something on their side to keep working:

- Removing or renaming a field or section in the `.claude/project.md` contract
- Making a previously optional field required
- Changing what an existing field *means* (e.g. `reviewers[0]` stops being the
  lead), so an unchanged `project.md` now produces wrong behaviour
- Removing or renaming a command or skill — the `/cr:<name>` someone types
  disappears
- Renaming the plugin itself, which changes the `cr:` prefix on every command

Silent misbehaviour is the worst case here, and it is what makes these MAJOR
rather than MINOR: a command that errors is annoying, a command that quietly
files an issue against the wrong board is a bug the consumer may not notice.
When a MAJOR lands, update every consuming repo's `.claude/project.md` in the
same PR round, and say so in the PR body.

### MINOR — new capability, existing consumers unaffected

- A new command, skill, or hook
- A new **optional** `project.md` field or section (optional means: a repo that
  omits it behaves exactly as before)
- An existing command gains a step or capability that needs no `project.md`
  change
- Deliberately broadening or narrowing a skill's `description` so it triggers
  in new situations — the trigger surface is the skill's interface

### PATCH — behaviour is unchanged in intent

- Wording, formatting, and typo fixes in a command or skill body
- Clarifying an instruction that was ambiguous but already meant this
- Fixing a bug so a command does what it was always documented to do
- Editing a `description` for accuracy without meaning to change when it fires

If you cannot decide between two levels, take the higher one. An over-bump
costs nothing; an under-bump means a consumer keeps a stale plugin and nobody
finds out until a command misbehaves.

## The marketplace has its own version

`.claude-plugin/marketplace.json` versions the **catalogue**, not the plugins
in it. Bump it only when the catalogue itself changes, independently of any
plugin's version:

- MAJOR — a plugin is removed or renamed (existing installs break)
- MINOR — a plugin is added
- PATCH — marketplace metadata: description, owner, an entry's `source` path

A plugin version bump alone does **not** touch `marketplace.json` — entries
carry no version, so there is nothing there to update.

## What bumps nothing

- `README.md`, this file, and anything else at the repo root
- `bootstrap/session-start.sh`

`bootstrap/` is not part of the plugin: each consuming repo holds its own
copied version at `.claude/hooks/session-start.sh`, so a change here does not
reach them through a plugin update. When you change it, say so explicitly in
the PR body and list the repos that need to re-copy the file — a version bump
cannot do that job for you.

## Editing bootstrap/session-start.sh

This file is copied into every consuming repo and runs at the start of every
session there, so a mistake in it breaks people who did not touch it. Three
invariants:

**1. It must parse under bash 3.2.** macOS still ships bash 3.2 as
`/bin/bash`, and these repos are developed on Macs, so 3.2 is the floor
regardless of what a Linux CI box has. Concretely:

- **Never put a heredoc inside `$(...)`.** bash 3.2 mis-parses it and reads an
  apostrophe in the heredoc body as an opening quote, killing the whole script
  with ``unexpected EOF while looking for matching `'``. This has happened once
  already, from a single word in a Python comment. The planner is written to a
  file and then run for exactly this reason.
- **Keep the planner body free of apostrophes** — belt and braces, so
  reintroducing the pattern cannot be fatal.
- **No bash 4+ syntax**: associative arrays (`declare -A`), `mapfile`,
  `readarray`, `${var^^}` / `${var,,}`, `&>>`, or `;;&` in a `case`.

**`bash -n` on Linux proves nothing here** — bash 5 parses the broken construct
happily. Check it the way it actually fails:

```bash
bash -n bootstrap/session-start.sh          # necessary, not sufficient
grep -n '\$(.*<<' bootstrap/session-start.sh   # must print nothing
/bin/bash -n bootstrap/session-start.sh     # on a Mac, the authoritative check
```

**2. It must never write to a consuming repo's `.claude/settings.json`.** That
file is committed; a session-start hook dirtying it puts changes in a diff that
the author did not make. Read it, never write it — and install plugins at the
default user scope, never `--scope project`, because that scope writes there.
Check with `git status` in a consuming repo after a run.

**3. It must never fail a session.** Every failure path warns on stderr and
exits 0. A missing tool, an unreachable marketplace, or an unparseable
settings.json degrades to a warning, never a broken session start.

When the behaviour changes, say so in the PR and name the repos that need to
re-copy the file — no version bump carries it to them.

## Before you commit

```bash
claude plugin validate .claude-plugin/marketplace.json --strict
claude plugin validate plugins/cr --strict
claude plugin tag plugins/cr --dry-run   # confirms plugin.json and the
                                         # marketplace entry agree on the version
```

All three must pass, plus the bash 3.2 checks above if you touched
`bootstrap/`. Then test against a real consuming repo — `cd` into one
with a `.claude/project.md` and the plugin enabled, start a new Claude Code
session, and actually run the command you changed. Command and skill edits are
picked up next session automatically via a local-path marketplace; if you
changed `plugin.json` or `marketplace.json`, run
`claude plugin marketplace update claude-toolkit` first.

## Releasing

**Merging to `main` is the release.** A marketplace installed from a GitHub repo
tracks that repo's default branch — the marketplace entry pins no ref, and an
install records the commit it resolved from `main`. Consumers get `main`'s HEAD,
never a tag. Tags here are a record and a rollback reference, not the
distribution mechanism; nothing waits on one.

Tag after the merge, from `main`, never from a PR branch — a tag cut on the
branch would point at a pre-merge commit that is not what consumers install.

```bash
git checkout main && git pull
claude plugin tag plugins/cr --dry-run     # confirm the version that merged
claude plugin tag plugins/cr --push        # creates and pushes cr--v<version>
git ls-remote --tags origin                # confirm it landed
```

The tag name is `cr--v<version>`, derived from `plugin.json`; `--push` sends it
to `origin`. Use `-m "cr %s"` to set the annotation message (`%s` expands to the
version) — the default already reads `cr <version>`, so pass it only if you want
different wording.

`--force` skips the dirty-tree and tag-already-exists checks. Use it only to
re-tag a mistake you have not pushed. Never move a tag that is already on the
remote: cut a new patch version instead, so anyone who read the old tag still
sees what it pointed at.

The catalogue has no tag of its own — `claude plugin tag` is per plugin, so a
`marketplace.json` version lives only in the manifest.

### Rolling back

A tag cannot roll consumers back, because they install from `main`. Revert the
commit on `main` (through a PR, like any other change) and bump a new patch
version on the way out — the revert is what consumers pick up, and the new
version is how they can tell they picked it up. Then tag that.

### After a release

- **Any repo with the bootstrap hook** — nothing to do, web or local: the hook
  refreshes the marketplace and updates the plugin at session start. As with any
  plugin install the new version loads from the next session, so the first
  session after a release can still be on the old one.
- **A repo without the hook** — `claude plugin update cr@claude-toolkit`, then
  restart Claude Code.

Say the new version in the PR body either way, so anyone on a stale machine can
tell what they should be seeing.

## Branch and PR discipline

Never push to `main`. Branch, open a PR, same as the consuming repos. State the
version bump and its level in the PR body, and for a MAJOR, list what each
consuming repo has to change.

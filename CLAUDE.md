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

## Before you commit

```bash
claude plugin validate .claude-plugin/marketplace.json --strict
claude plugin validate plugins/cr --strict
claude plugin tag plugins/cr --dry-run   # confirms plugin.json and the
                                         # marketplace entry agree on the version
```

All three must pass. Then test against a real consuming repo — `cd` into one
with a `.claude/project.md` and the plugin enabled, start a new Claude Code
session, and actually run the command you changed. Command and skill edits are
picked up next session automatically via a local-path marketplace; if you
changed `plugin.json` or `marketplace.json`, run
`claude plugin marketplace update claude-toolkit` first.

## How consumers pick up a new version

- **Claude Code on the web** — every session starts in a fresh container and
  installs from the marketplace, so cloud sessions get the newest version with
  no action needed.
- **Local machines** — pinned to whatever is installed until someone runs
  `claude plugin update cr@claude-toolkit` (a restart applies it). Mention the
  new version in the PR body so people know there is something to pull.

## Branch and PR discipline

Never push to `main`. Branch, open a PR, same as the consuming repos. State the
version bump and its level in the PR body, and for a MAJOR, list what each
consuming repo has to change.

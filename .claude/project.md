---
owner: cr-calleja-software
repo: claude-toolkit
context_doc: CLAUDE.md
reviewers: [ryancalleja, ccalleja]
project_board:
  number: 6
  owner: cr-calleja-software
  url: https://github.com/orgs/cr-calleja-software/projects/6
---

## Scope

This repo is a Claude Code **plugin marketplace**, not an application. It ships
the `cr` plugin — slash commands, the `seo-audit` skill, and a session hook — to
`festa-tracker`, `good-news` and `lanca-mt`. A change here reaches all of them
on their next session, so the bar is higher than in a normal repo.

In scope: the commands and skill under `plugins/cr/`, the `.claude/project.md`
contract they read, `bootstrap/session-start.sh` that makes the plugin reachable,
and `scripts/` tooling for releasing.

Out of scope — say so and propose a separate issue:

- Anything that only serves one consuming repo. Commands and skills are generic
  by design; project-specific facts belong in that repo's `project.md`.
- Adding a command or skill without a consuming repo that needs it now.
- Changing what `claude plugin` itself does. Where the CLI is inflexible (its
  tag naming, for one) the answer is to work around it in `scripts/`, not to
  wait on it.

## Review checklist

Versioning first — `CLAUDE.md` has the full rules and the level table; these are
the ways a diff gets it wrong:

- A change under `plugins/cr/` with no version bump in the same commit
- An under-bump: a `project.md` contract field removed, renamed or redefined, or
  a command renamed, shipped as anything below MAJOR
- `marketplace.json` bumped for a plugin-only change, or not bumped when a
  plugin is added, removed or renamed
- A second bump on a branch that already has one — edit the number instead

Prompt files are the product here, so they fail in ways ordinary code doesn't:

- **A worked example contradicting a prose rule beside it.** Commands and skills
  contain templates the agent is told to follow exactly; where an example and a
  rule disagree, the example wins. Check every example against the rules within a
  screen of it. This has been the single most common defect in this repo.
- **A hardcoded count or list that duplicates something derivable** — "all three
  readers", "sections 1, 5 and 8". It goes stale the next time one is added, and
  silently. Name where the information lives instead of copying it.
- An instruction added in one place but not the place that causes it to be read
  — e.g. a new `project.md` section named in a checklist item but not in the
  command's "read `project.md` first" line
- A rule restated from `CLAUDE.md` rather than pointed at, giving two copies to
  keep in sync
- Body text drifting from the house voice: imperative, short bullets, no
  preamble, no comment that only restates what the line does

Shell scripts (`bootstrap/`, `scripts/`) must hold to the bash 3.2 floor and the
invariants in `CLAUDE.md` — no bash 4+ syntax, no heredoc inside `$(...)`, and
for `bootstrap/session-start.sh` specifically: never write to a consuming repo's
`settings.json`, never fail a session. Also:

- A `die`-style helper called inside `$(...)`, where its exit only ends the
  subshell and the caller reads an empty result as a real answer
- A guard whose failure is indistinguishable from the condition it guards against
- `bootstrap/session-start.sh` changed without the PR listing the repos that must
  re-copy it — no version bump carries that

## How to test

1. `git fetch origin <branch-name> && git checkout <branch-name>`
2. Run the checks under **Before you commit** in `CLAUDE.md` — the two
   `claude plugin validate --strict` runs, `claude plugin tag --dry-run`, plus
   the bash 3.2 and `ls-remote` shim checks if a shell script changed. That
   section is the canonical list; it is not repeated here so it cannot drift.
3. Then use it: from a consuming repo with the plugin enabled, start a fresh
   Claude Code session and actually run the command or skill you changed. A
   prompt only proves itself in use — reading the diff is not the same test.

## Stack notes

- No application code. Markdown command/skill bodies, two JSON manifests, and
  bash. `python3` is the only scripting dependency (`bootstrap/`, `scripts/`).
- Layout: `plugins/cr/` ships to consumers; `.claude-plugin/marketplace.json` is
  the catalogue; `bootstrap/session-start.sh` is copied into each consuming repo
  by hand; `scripts/` and the root docs ship to nobody.
- Releasing is merging to `main` — the marketplace tracks the default branch, so
  consumers get `main`'s HEAD and never a tag. `scripts/release-tag.sh` cuts the
  tag afterwards; `--check` says whether the version on `main` has one.
- `/cr:ship-issue`'s board steps 3.5 and 7.5 are skipped here: project 6 has no
  `project_id`/`field_id`/`options` recorded above, so cards are added but not
  moved between statuses.

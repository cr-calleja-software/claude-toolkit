# claude-toolkit

Shared Claude Code commands + skills for cr-calleja-software projects, distributed
as a plugin marketplace so `festa-tracker`, `good-news`, `lanca-mt` (and future
repos) stop copy-pasting `.claude/commands/*.md`.

## Install (per machine, one-time)

Requires the `claude` CLI. Register this repo as a marketplace:

```bash
claude plugin marketplace add /Users/clintcalleja/Development/Personal/claude-toolkit
```

This writes the marketplace registration into your **user-level**
`~/.claude/settings.json` — do it once per machine, not once per project. If
you ever move or rename this repo, re-run the same command with the new path
(or `claude plugin marketplace remove claude-toolkit` first if the old path no
longer exists).

Confirm it registered:

```bash
claude plugin marketplace list   # should list "claude-toolkit — Directory (<path>)"
```

## Set up a project to use this toolkit

Run these from inside the **consuming** repo (e.g. `good-news`), not this one.

1. **Write `.claude/project.md`** at that repo's root — see the contract
   below. Every command in this plugin reads it; nothing works without it.
2. **Enable the plugin** for that project:
   ```bash
   claude plugin install personal-projects@claude-toolkit --scope project
   ```
   `--scope project` writes `"enabledPlugins": {"personal-projects@claude-toolkit": true}`
   into that repo's `.claude/settings.json` (committed, same pattern as an
   existing `frontend-design@claude-plugins-official` entry if there is one).
   Equivalent to editing that file by hand if you'd rather not use the CLI.
3. **Remove the project's old local copies**, if it has any — the plugin now
   serves them:
   ```bash
   git rm .claude/commands/create-issue.md .claude/commands/ship-issue.md \
          .claude/commands/code-review.md .claude/commands/frontend-design-audit.md
   git rm -r .claude/skills/seo-audit   # only if present
   ```
4. **Start a new Claude Code session** in that repo (plugins load at session
   start) and sanity-check with `/create-issue` or `/code-review` — it should
   read the `.claude/project.md` you just wrote rather than erroring or
   falling back to generic behaviour.
5. Commit `.claude/project.md` and the `.claude/settings.json` change on a
   branch and open a PR, same as any other change to that repo.

## What's in `plugins/personal-projects`

- `commands/create-issue.md` — draft + file a GitHub issue
- `commands/ship-issue.md` — implement an issue end-to-end (branch → PR → review request)
- `commands/code-review.md` — review the local diff or a PR
- `commands/frontend-design-audit.md` — UI/UX audit of frontend changes
- `skills/seo-audit/SKILL.md` — read-only SEO/LLM-discoverability audit

All five are **generic** — no repo name, org, project-board ID, or product
checklist is hardcoded. Each one starts by reading `.claude/project.md` in the
consuming repo.

## The `.claude/project.md` contract

Every consuming project needs this one file at its repo root. YAML frontmatter
for flat facts, markdown sections for the prose blocks that used to be
duplicated verbatim across repos.

```yaml
---
owner: cr-calleja-software        # GitHub org/user
repo: good-news                   # repo name
context_doc: AGENTS.md            # file (or [list]) to read for stack/data-model/conventions
reviewers: [ryancalleja, ccalleja] # exactly two — the PR-author/counterpart pair; reviewers[0] is the default/lead
project_board:                    # omit this whole key if there's no board
  number: 5
  owner: cr-calleja-software       # org login used with `gh project item-add --owner`
  url: https://github.com/orgs/cr-calleja-software/projects/5/views/1
  project_id: PVT_kwDOEV0uKc4Beepu           # optional — only if you want /ship-issue to move the card between statuses
  field_id: PVTSSF_lADOEV0uKc4BeepuzhY4izk   # optional, required alongside project_id
  options: {in_progress: 47fc9ee4, in_review: df73e18b}  # optional, required alongside field_id
---

## Scope
<what's in scope right now (current phase/milestone), what's explicitly out, and
any open product questions that should block silent assumptions>

## Review checklist
<project-specific bullets /code-review checks for, beyond the generic dimensions>

## Design checklist
<project-specific bullets /frontend-design-audit checks for>

## How to test
<boilerplate steps /ship-issue puts at the top of a PR's "How to test" section>

## Stack notes
<optional — stack facts/file pointers /create-issue and /ship-issue can lean on>
```

If `project_board.project_id`/`field_id`/`options` are omitted, `/ship-issue`
skips moving the card between statuses (Steps 3.5/7.5) and only relies on
`/create-issue` having added it to the board in the first place.

## Contributing

This plugin is generic **on purpose** — the moment a command needs a fact
that's true for one repo but not another (an org name, a checklist bullet, a
board ID), that fact belongs in the consuming repo's `.claude/project.md`,
not in the command file here. Before editing a command, check whether what
you're adding is actually generic or actually project-specific.

**Editing an existing command or skill**
1. Edit the file under `plugins/personal-projects/commands/` or `skills/`.
2. Validate the manifests still pass:
   ```bash
   claude plugin validate .claude-plugin/marketplace.json --strict
   claude plugin validate plugins/personal-projects --strict
   ```
3. Bump `version` in `plugins/personal-projects/.claude-plugin/plugin.json` —
   patch for wording/prompt tweaks, minor for a new command/skill or a new
   optional `project.md` field, major for a breaking change to the
   `project.md` contract (one that would silently misbehave against an
   existing project.md written for the old contract).
4. **Test against a real consuming repo before merging**: `cd` into
   `good-news` (or any repo with `.claude/project.md` and the plugin
   enabled), start a new Claude Code session, and actually run the command
   you changed. Command/skill file edits are picked up on the next session
   automatically (local-path marketplace, no reinstall needed); if you
   changed `marketplace.json` or `plugin.json` (new plugin, rename, version
   bump), run `claude plugin marketplace update claude-toolkit` first, then
   start a new session.
5. Commit on a branch and open a PR — same discipline as the consuming repos:
   no direct pushes to `main`.

**Adding a new command or skill**
- Add the file under `commands/` or `skills/<name>/SKILL.md`.
- If it needs project-specific facts, document the new `project.md`
  field/section it expects in this README's contract section above, and
  update each consuming repo's `.claude/project.md` accordingly (a command
  that silently no-ops or guesses when a field is missing is worse than one
  that says "add `<field>` to project.md" and stops).
- Follow the existing commands' shape: frontmatter `description`, an opening
  paragraph, a `## Usage` block, then `## Instructions` that starts by
  reading `.claude/project.md`.

**Onboarding a new consuming repo** — see "Set up a project to use this
toolkit" above. This repo itself doesn't need any change for a new consumer;
all the work happens in the new repo.

## Status

- [x] Plugin scaffolded from `good-news`'s command files (most recently updated
      across the three source repos as of 2026-08-08), folding in two things
      `festa-tracker`/`lanca-mt` had that `good-news` didn't: robust `gh` CLI
      failure handling in the project-board step, and the `seo-audit` →
      `/create-issue` cross-reference.
- [x] Wrote `.claude/project.md` for `festa-tracker`, `good-news`, `lanca-mt`
- [x] `claude plugin marketplace add` this repo locally
- [x] Enabled the plugin in each project's `.claude/settings.json` (project
      scope, `--scope project`), deleted their local
      `.claude/commands/*.md` + `.claude/skills/seo-audit`
      — committed on a `chore/add-claude-project-md` branch in each repo,
      not yet pushed
- [ ] Decide: push this repo to GitHub, or keep it local-only for now

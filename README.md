# claude-toolkit

Shared Claude Code commands + skills for cr-calleja-software projects, distributed
as a plugin marketplace so `festa-tracker`, `good-news`, `lanca-mt` (and future
repos) stop copy-pasting `.claude/commands/*.md`.

The repo is **public**. Nothing repo-specific lives here — every command and
skill reads the consuming repo's `.claude/project.md` instead — so publishing it
exposes no project detail, and keeping it that way is a contributing rule.

## Install (per machine, one-time)

Requires the `claude` CLI. The
[`cr-calleja-software/claude-toolkit`](https://github.com/cr-calleja-software/claude-toolkit)
repo is public, so there is no access to arrange first. Register it as a
marketplace:

```bash
claude plugin marketplace add https://github.com/cr-calleja-software/claude-toolkit
```

The `owner/repo` shorthand — `claude plugin marketplace add
cr-calleja-software/claude-toolkit` — is equivalent. The full URL is used
throughout this README so the swap commands below stay copy-pasteable.

This writes the marketplace registration into your **user-level**
`~/.claude/settings.json` — do it once per machine, not once per project.

**If you're actively developing this toolkit** (editing commands/skills),
register it from a local clone instead, so edits are picked up on the next
Claude Code session without needing to push/pull first:

```bash
claude plugin marketplace remove claude-toolkit
claude plugin marketplace add /path/to/your/local/claude-toolkit
```

⚠️ **`claude plugin marketplace remove` edits the settings of whichever repo
you run it in.** If that repo's `.claude/settings.json` is committed — every
consuming repo's is — it strips the `extraKnownMarketplaces` block and the
plugin's `enabledPlugins` line out of the tracked file. Run the swap from
outside a consuming repo, or `git checkout -- .claude/settings.json` afterwards
and check `git status` before committing anything.

While developing this way, set `CLAUDE_BOOTSTRAP_SKIP=1` so the bootstrap hook
in a consuming repo does not re-register the GitHub marketplace behind you and
update the plugin out from under your local clone.

Switch back when you are done:

```bash
claude plugin marketplace remove claude-toolkit
claude plugin marketplace add https://github.com/cr-calleja-software/claude-toolkit
```

Confirm it registered:

```bash
claude plugin marketplace list   # should list "claude-toolkit"
```

## Set up a project to use this toolkit

Run these from inside the **consuming** repo (e.g. `good-news`), not this one.

1. **Write `.claude/project.md`** at that repo's root — see the contract
   below. Every command in this plugin reads it; nothing works without it.
2. **Enable the plugin** for that project by adding it to that repo's
   committed `.claude/settings.json` by hand:
   ```json
   "enabledPlugins": {"cr@claude-toolkit": true}
   ```
   (same pattern as an existing `frontend-design@claude-plugins-official` entry
   if there is one), then install the plugin itself at the default **user**
   scope:
   ```bash
   claude plugin install cr@claude-toolkit
   ```
   The two halves are separate on purpose: `enabledPlugins` is what activates
   the plugin for the repo and belongs in git; the install is machine-local
   state and does not. Once the bootstrap hook from step 3 is in place you can
   skip the install entirely — the hook does it from what `settings.json`
   declares.

   **Do not use `--scope project`.** It writes the enablement for you, but the
   matching `claude plugin uninstall --scope project` (and
   `claude plugin marketplace remove`) then *rewrites that committed file* —
   stripping the `enabledPlugins` line and the `extraKnownMarketplaces` block
   and reordering what remains. It also leaves a second install record
   alongside any user-scope one, and `claude plugin update` only updates one
   scope, so the other silently goes stale.
3. **Install the bootstrap hook** — required for Claude Code on the web, and
   it repairs local sessions too. See "Claude Code on the web" below for why:
   ```bash
   mkdir -p .claude/hooks
   cp /path/to/claude-toolkit/bootstrap/session-start.sh .claude/hooks/session-start.sh
   chmod +x .claude/hooks/session-start.sh
   ```
   Then register it in that repo's `.claude/settings.json`:
   ```json
   "hooks": {"SessionStart": [{"hooks": [{"type": "command",
     "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/session-start.sh"}]}]}
   ```
   Copy the file as-is — it is repo-agnostic and identical in every repo.
4. **Remove the project's old local copies**, if it has any — the plugin now
   serves them:
   ```bash
   git rm .claude/commands/create-issue.md .claude/commands/ship-issue.md \
          .claude/commands/code-review.md .claude/commands/frontend-design-audit.md
   git rm -r .claude/skills/seo-audit   # only if present
   ```
5. **Start a new Claude Code session** in that repo (plugins load at session
   start) and sanity-check with `/cr:create-issue` or `/cr:code-review` — it
   should read the `.claude/project.md` you just wrote rather than erroring
   or falling back to generic behaviour.
6. Commit `.claude/project.md`, `.claude/hooks/session-start.sh` and the
   `.claude/settings.json` change on a branch and open a PR, same as any other
   change to that repo. Check `git diff` on `settings.json` first — plugin CLI
   commands rewrite that file, so it can carry changes you did not make.

## Claude Code on the web

Web sessions honour only half of a repo's `.claude/settings.json`:
`enabledPlugins` resolves, but **`extraKnownMarketplaces` is ignored**. The
`claude-toolkit` marketplace is therefore never fetched, `cr@claude-toolkit`
cannot resolve, and the `/cr:` commands and the seo-audit skill go missing —
with no error, which is what makes it confusing to diagnose. Plugins from
marketplaces Claude Code already knows (`frontend-design@claude-plugins-official`)
keep working, which is the tell.

`bootstrap/session-start.sh` closes that gap. At session start it reads the
consuming repo's own `.claude/settings.json`, registers every marketplace under
`extraKnownMarketplaces` that isn't registered yet, and installs every enabled
plugin that isn't installed yet.

Because it is driven entirely by that file, the script is **byte-identical in
every consuming repo** — copy it once and never edit it. Adding a marketplace or
a plugin to `settings.json` is enough; the next session picks it up. It is also
idempotent and never fails a session — every failure path warns on stderr and
exits 0.

It also keeps plugins current. A marketplace this repo declares is refreshed
each session, and a plugin from one of those marketplaces is updated when the
marketplace publishes a newer version — without that a machine stays pinned to
whatever version it first installed, and would not even see a newer one, since
`claude plugin update` reads the cached marketplace clone. Marketplaces the repo
does not declare (the official one) are left alone; Claude Code manages those,
and refreshing them would slow every session start for no benefit. A cold start
does no refresh or update work at all — everything is a fresh add and install.

A plugin can be installed more than once — once at user scope, and once per
project whose `settings.json` enables it — and `claude plugin update` only ever
updates one scope at a time. The hook updates every scope it finds a plugin in,
so the copies cannot drift apart.

When something is out of its reach it says so rather than going quiet. A plugin
enabled in `settings.json` whose marketplace is neither declared nor registered
cannot be resolved, and a plugin installed from a declared marketplace but no
longer named in `enabledPlugins` will never be updated — the usual cause of the
latter is a plugin CLI command rewriting the tracked file. Both now warn.
`CLAUDE_BOOTSTRAP_DEBUG=1` prints the settings file it read and the plan it
derived, including when that plan is empty.

It runs **locally as well as on the web**. Local machines drift into the same
broken state by a different route: `claude plugin marketplace remove` takes its
plugins' installs with it, and re-adding the marketplace does not restore them,
leaving `enabledPlugins` pointing at a plugin that is registered but not
installed — so the commands silently vanish. The hook converges any session on
whatever `settings.json` declares. Set `CLAUDE_BOOTSTRAP_SKIP=1` to opt out for
a session, which is what you want while developing this toolkit against a
local-path marketplace registration.

Why it can't live in this plugin: a hook shipped by the `cr` plugin only runs
once the plugin is installed, which is the very thing the bootstrap does. Some
entry point has to be self-contained in the consuming repo. Everything *after*
bootstrap can and should live here instead — see
`plugins/cr/hooks/hooks.json`.

## What's in `plugins/cr`

- `commands/create-issue.md` → invoked as `/cr:create-issue` — draft + file a GitHub issue
- `commands/ship-issue.md` → invoked as `/cr:ship-issue` — implement an issue end-to-end (branch → PR → review request)
- `commands/code-review.md` → invoked as `/cr:code-review` — review the local diff or a PR
- `commands/frontend-design-audit.md` → invoked as `/cr:frontend-design-audit` — UI/UX audit of frontend changes
- `skills/seo-audit/SKILL.md` — read-only SEO/LLM-discoverability audit, surfaced automatically (not slash-invoked)
- `hooks/hooks.json` + `hooks-handlers/session-start.sh` — ships with the
  plugin, so it runs in every repo that installs it with no per-repo copy.
  Currently warns at session start when `.claude/project.md` is missing, rather
  than letting a command fail halfway through. Shared session setup belongs
  here; contrast `bootstrap/session-start.sh`, which each repo must copy in.

All five commands and skills are **generic** — no repo name, org, project-board ID, or product
checklist is hardcoded. Each one starts by reading `.claude/project.md` in the
consuming repo.

Note the `cr:` prefix on the commands: Claude Code always namespaces
plugin-provided slash commands as `<plugin-name>:<command>` to avoid
collisions with other plugins (there's already an unrelated `code-review`
plugin in the official marketplace) — it's mandatory, not something we
opted into, and the only way to change it is renaming the plugin itself
(the `name` field in `plugin.json`).

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
  project_id: PVT_kwDOEV0uKc4Beepu           # optional — only if you want /cr:ship-issue to move the card between statuses
  field_id: PVTSSF_lADOEV0uKc4BeepuzhY4izk   # optional, required alongside project_id
  options: {in_progress: 47fc9ee4, in_review: df73e18b}  # optional, required alongside field_id
---

## Scope
<what's in scope right now (current phase/milestone), what's explicitly out, and
any open product questions that should block silent assumptions>

## Review checklist
<project-specific bullets /cr:code-review checks for, beyond the generic dimensions>

## Design checklist
<project-specific bullets /cr:frontend-design-audit checks for>

## How to test
<boilerplate steps /cr:ship-issue puts at the top of a PR's "How to test" section>

## Stack notes
<optional — stack facts/file pointers /cr:create-issue and /cr:ship-issue can lean on>
```

If `project_board.project_id`/`field_id`/`options` are omitted, `/cr:ship-issue`
skips moving the card between statuses (Steps 3.5/7.5) and only relies on
`/cr:create-issue` having added it to the board in the first place.

## Contributing

This plugin is generic **on purpose** — the moment a command needs a fact
that's true for one repo but not another (an org name, a checklist bullet, a
board ID), that fact belongs in the consuming repo's `.claude/project.md`,
not in the command file here. Before editing a command, check whether what
you're adding is actually generic or actually project-specific.

Since the repo is public, that rule doubles as a privacy rule: no client names,
credentials, internal URLs, or unreleased product detail in a command, skill, or
example. The project-board ids in the `project.md` contract above are
illustrative — real ones belong in the consuming repo, which is where every
project-specific fact goes anyway.

**Editing an existing command or skill**
1. Edit the file under `plugins/cr/commands/` or `skills/`.
2. Validate the manifests still pass:
   ```bash
   claude plugin validate .claude-plugin/marketplace.json --strict
   claude plugin validate plugins/cr --strict
   claude plugin tag plugins/cr --dry-run
   ```
3. **Bump `version` in `plugins/cr/.claude-plugin/plugin.json`, in the same
   commit** — see [Versioning](#versioning) below. This is not optional: an
   unbumped change is indistinguishable, to a consuming repo, from no change.
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

### Versioning

Every change under `plugins/cr/` bumps the plugin version in the same commit.
Pick the level from what the change does to a repo already using the plugin,
with a `.claude/project.md` written for the current contract:

| Level | When | Examples |
| --- | --- | --- |
| **MAJOR** | An existing consumer breaks or silently misbehaves without a change on their side | Removing/renaming a `project.md` field; making an optional field required; changing what a field means; removing or renaming a command; renaming the plugin |
| **MINOR** | New capability, existing consumers unaffected | A new command, skill or hook; a new *optional* `project.md` field; deliberately changing a skill's trigger surface |
| **PATCH** | Behaviour unchanged in intent | Wording and typo fixes; clarifying an ambiguous instruction; fixing a command to do what it already documented |

Undecided between two levels? Take the higher one — an over-bump costs nothing,
an under-bump leaves consumers on a stale plugin until something misbehaves.

`.claude-plugin/marketplace.json` versions the **catalogue** separately: bump it
when a plugin is added (minor), removed or renamed (major), or when marketplace
metadata changes (patch). A plugin version bump alone does not touch it.

Repo-root docs and `bootstrap/session-start.sh` bump nothing — but a bootstrap
change does not reach consumers through a plugin update either, since each repo
holds its own copy, so call out in the PR which repos need to re-copy it.

`CLAUDE.md` holds the full rules with the reasoning behind them, and is what an
agent working in this repo reads automatically.

### Releasing

**Merging to `main` is the release** — a marketplace installed from a GitHub
repo tracks the default branch, so consumers get `main`'s HEAD and never a tag.
Tags are a record and a rollback reference; nothing waits on one.

Tag from `main` after the merge, never from a PR branch:

```bash
git checkout main && git pull
claude plugin tag plugins/cr --dry-run     # confirm the version that merged
claude plugin tag plugins/cr --push        # creates and pushes cr--v<version>
```

Web sessions pick the new version up on their next session with no action.
Local machines need `claude plugin update cr@claude-toolkit` and a restart, so
name the new version in the PR body. Rolling back means reverting on `main` and
bumping a patch — a tag can't do it. See `CLAUDE.md` for the full flow.

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
      `/cr:create-issue` cross-reference.
- [x] Wrote `.claude/project.md` for `festa-tracker`, `good-news`, `lanca-mt`
- [x] Renamed the plugin `personal-projects` → `cr` (shorter `/cr:` invocation
      prefix)
- [x] Enabled the plugin in each project's `.claude/settings.json` (project
      scope, `--scope project`), deleted their local
      `.claude/commands/*.md` + `.claude/skills/seo-audit`
      — committed on a `chore/add-claude-project-md` branch in each repo,
      PRs open
- [x] Pushed to GitHub — `cr-calleja-software/claude-toolkit`, now **public**
- [ ] Pick a license — the repo is public but has no `LICENSE` file, so it is
      "all rights reserved" by default and nobody outside the org can reuse it

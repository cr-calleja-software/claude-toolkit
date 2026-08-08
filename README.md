# claude-toolkit

Shared Claude Code commands + skills for cr-calleja-software projects, distributed
as a plugin marketplace so `festa-tracker`, `good-news`, `lanca-mt` (and future
repos) stop copy-pasting `.claude/commands/*.md`.

## Install (per machine, one-time)

```
claude plugin marketplace add /Users/clintcalleja/Development/Personal/claude-toolkit
```

## Enable (per project)

Add to the project's `.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "personal-projects@claude-toolkit": true
  }
}
```

Then delete that project's local `.claude/commands/*.md` and
`.claude/skills/seo-audit` — the plugin serves them instead.

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

## Status

- [x] Plugin scaffolded from `good-news`'s command files (most recently updated
      across the three source repos as of 2026-08-08), folding in two things
      `festa-tracker`/`lanca-mt` had that `good-news` didn't: robust `gh` CLI
      failure handling in the project-board step, and the `seo-audit` →
      `/create-issue` cross-reference.
- [ ] Write `.claude/project.md` for `festa-tracker`, `good-news`, `lanca-mt`
- [ ] `claude plugin marketplace add` this repo locally
- [ ] Enable the plugin in each project's `.claude/settings.json`, delete their
      local `.claude/commands/*.md` + `.claude/skills/seo-audit`
- [ ] Decide: push this repo to GitHub, or keep it local-only for now

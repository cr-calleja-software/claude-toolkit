---
description: Full SDLC automation — read a GitHub issue, implement it, commit, push, open a PR, request review
---

# ship-issue

Full SDLC automation: read a GitHub issue, implement the change, commit, push, open a PR, and request a review.

> **Prerequisite:** requires the GitHub MCP server (`mcp__github__*` tools) to be configured. If it is not connected, these steps will fail.
>
> **Config:** this command reads `.claude/project.md` at the repo root for everything project-specific (`owner`, `repo`, `context_doc`, `reviewers`, `project_board`, scope, and conventions). If that file is missing, stop and tell the user it needs to exist before this command can run.

## Usage

```
/cr:ship-issue <issue-url-or-number>
```

**Examples:**
- `/cr:ship-issue 12`
- `/cr:ship-issue https://github.com/<owner>/<repo>/issues/12`

---

## Instructions

You are executing the full development lifecycle for GitHub issue: **$ARGUMENTS**

Read `.claude/project.md` first — `owner`/`repo` from its frontmatter drive every `mcp__github__*` call below; its `## Scope`, `## Review checklist`, `## Design checklist`, and `## How to test` sections drive the steps that follow.

Follow every step in order. Do not skip steps.

### Step 1 — Read the issue

Use `mcp__github__issue_read` with `owner`/`repo` from `project.md`, and the issue number extracted from the argument.

Capture:
- Issue **number**
- Issue **title**
- Issue **body** (full description, acceptance criteria, notes)
- Any **labels**

Print a one-line summary: `Issue #N — <title>`

### Step 2 — Understand the scope

Read `context_doc` from `project.md` (one file or a list) to confirm the requested change is within the scope described under `## Scope`. If it clearly needs something explicitly out of scope, say so and stop. Do not implement out-of-scope work.

If the issue touches an open product question listed under `## Scope` and the issue body doesn't already resolve it, stop and ask rather than guessing a product decision.

### Step 3 — Create a branch

Derive the branch name. No fixed prefix convention is required, but **always include the issue number** so the branch is traceable:
- Include the issue number, e.g. `issue-{number}-{slugified-title}` (a `feature/` or `fix/` prefix is fine but not required)
- Slugify the title: lowercase, spaces → hyphens, strip special characters, max 50 chars total

Run:
```bash
git fetch origin main
git checkout -b <branch-name> origin/main
```

### Step 3.5 — Move the board card to "In progress"

Only if `project.md`'s `project_board` section has `project_id`, `field_id`, and an `in_progress` option id — some projects only add issues to the board (handled by `/cr:create-issue`) without tracking per-column status. Skip this step entirely if those fields aren't present.

Best-effort — don't block the rest of the flow if this fails (e.g. the issue was never added to the board, or `gh` isn't authenticated):

```bash
ITEM_ID=$(gh project item-list <project_board.number> --owner <project_board.owner> --format json --limit 100 \
  | jq -r --arg url "<issue-url>" '.items[] | select(.content.url == $url) | .id')
if [ -n "$ITEM_ID" ]; then
  gh project item-edit --id "$ITEM_ID" \
    --project-id <project_board.project_id> \
    --field-id <project_board.field_id> \
    --single-select-option-id <project_board.options.in_progress>
fi
```

### Step 4 — Implement the change

Read all relevant files before editing. Follow the conventions in `context_doc` and `project.md`'s `## Stack notes`:
- Match the project's language/type-safety conventions (e.g. no `any` without a written reason)
- Match the project's styling approach — never hardcode a value the design system/theme already carries
- Server-render by default; use client-side interactivity only where it's needed
- Keep components small and single-purpose
- No comments unless the WHY is non-obvious
- Mobile-first, matching whatever baseline viewport `project.md` specifies
- Treat any prototype/reference-only markup called out in `context_doc` as design reference — never copy it into real app code

Do the smallest implementation that fully satisfies the issue's acceptance criteria. Do not add unrequested features.

### Step 4.5 — Frontend design audit (frontend changes only)

If **any** of the changed files are frontend files (components, pages, or style-heavy files), run the `/cr:frontend-design-audit` command on the local diff **before committing**:

```
/cr:frontend-design-audit --fix
```

This will:
1. Audit the changes across visual hierarchy, typography, colour/contrast, responsiveness, accessibility, and copy — including the project-specific checks under `project.md`'s `## Design checklist`
2. Apply all critical (🔴) and high-priority (🟠) fixes automatically
3. Print a summary of what was changed

If the skill surfaces 🟡 medium or 🟢 low priority issues, list them in the PR body under a `## Design notes` section so the reviewer is aware. Do not block the commit on these.

Skip this step entirely if the issue is backend-only (schema/migrations, server-side logic with no UI impact).

### Step 5 — Commit

Stage only the files you changed (never `git add -A` blindly — avoid committing `.env*` or generated files that don't belong in the repo):

```bash
git add <specific files>
git commit -m "$(cat <<'EOF'
<type>(scope): <short description>

Closes #<issue-number>

<optional body — only if the why is not obvious from the title>
EOF
)"
```

Commit type: `feat` for features, `fix` for bugs, `refactor`, `chore`, `docs`, `test`.

### Step 6 — Push

```bash
git push -u origin <branch-name>
```

Retry up to 4 times with exponential backoff (2s, 4s, 8s, 16s) if the push fails due to a network error.

### Step 7 — Create a pull request

Use `mcp__github__create_pull_request` with:
- `owner`/`repo`: from `project.md`
- `title`: `<type>(scope): <short description> (#<issue-number>)`
- `body`: (see template below)
- `head`: the branch you just pushed
- `base`: `main`

PR body template:
```markdown
## Summary
Closes #<issue-number>

<2-3 bullet points summarising what changed and why>

## How to test
<the boilerplate steps from project.md's "## How to test" section, adjusted for whether this change actually touches the parts they're conditional on>
<then specific, issue-tailored steps — the exact route(s)/screen(s) to visit and the exact action(s) to take to see the change, one per distinct piece of user-facing or behavioral change, derived from the issue's acceptance criteria — don't leave this generic>

## Test plan
- [ ] <key thing to verify manually>
- [ ] <the acceptance-bar checklist items from project.md's "## Review checklist" / "## Design checklist" that apply to this change>
```

A reviewer should be able to follow **How to test** without reading the diff first.

### Step 7.5 — Move the board card to "In review"

Same conditions and best-effort pattern as Step 3.5, this time setting the option to `project_board.options.in_review`. Skip if Step 3.5 was skipped.

### Step 8 — Request a review

After the PR is created, request a review from the other maintainer, using `project.md`'s `reviewers` list (exactly two entries expected).

**Reviewer selection rule** — determine the current author from `git config user.email`, not the display name:
- If the author matches `reviewers[0]` → request review from `reviewers[1]`
- If the author matches `reviewers[1]` → request review from `reviewers[0]`
- If it matches neither → request from `reviewers[0]` (project lead) by default

To add the reviewer, call the GitHub review-request endpoint
(`POST /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers` with
`{ "reviewers": ["<username>"] }`) via the available GitHub MCP tool. If no MCP
tool exposes that endpoint, fall back to running
`gh pr edit <pr-number> --add-reviewer <username>`, and if that also fails, append
`cc @<reviewer>` to the PR body. Do **not** use `mcp__github__pull_request_review_write`
for this — that submits a review (approve / request changes), it does not request one.

### Step 9 — Report back

Print a short summary:
```
✓ Branch:  <branch-name>
✓ Commit:  <short sha>
✓ PR:      <pr-url>
✓ Review requested from: <reviewer>
✓ Board:   moved to "In review"  |  n/a (no board status tracking configured)
```

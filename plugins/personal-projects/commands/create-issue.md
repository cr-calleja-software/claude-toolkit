---
description: Turn a rough thought into a well-scoped GitHub issue that /ship-issue can implement
---

# create-issue

Turn a rough thought into a well-scoped GitHub issue that an agent can pick up and run `/ship-issue` against successfully.

> **Prerequisite:** requires the GitHub MCP server (`mcp__github__*` tools) to be configured. If it is not connected, run `/mcp` → authenticate **github** first, or these steps will fail.
>
> **Config:** this command reads `.claude/project.md` at the repo root for everything project-specific (`owner`, `repo`, project board, scope, checklists). If that file is missing, stop and tell the user it needs to exist before this command can run.

## Usage

```
/create-issue <rough description of what you want>
```

**Examples:**
- `/create-issue submitters should be able to preview their story before the final post step`
- `/create-issue map pins overlap when a lot of stories are clustered in one city`
- `/create-issue` (no args — I'll ask you what the issue is about)

---

## Instructions

You are drafting a GitHub issue from the user's request: **$ARGUMENTS**

Read `.claude/project.md` first. It has YAML frontmatter (`owner`, `repo`, `context_doc`, `reviewers`, `project_board`) and markdown sections (`## Scope`, `## Review checklist`, `## Design checklist`, `## How to test`, `## Stack notes`). Use `owner`/`repo` from its frontmatter in every `mcp__github__*` call below — do not hardcode them.

The goal is an issue with **exactly the right amount of detail** — enough that an agent running `/ship-issue` can implement it correctly without guessing, but not so much that it over-specifies the solution or invents requirements the user never asked for. Match the level of detail to the size of the change.

### Step 1 — Understand the request

Read `context_doc` from `project.md`'s frontmatter (one file or a list — if a list, read all of them) to ground yourself in the project: mission, stack, conventions, data model, and scope.

If `$ARGUMENTS` is empty or too vague to act on, ask the user what they want the issue to cover. Otherwise, restate what you understood in one line so the user can catch a misread early.

### Step 2 — Check scope, then ask only what you need

Confirm the request fits the current scope described under `## Scope` in `project.md`. If it's clearly out of scope, say so and ask whether to (a) reframe it into something in-scope or (b) create it anyway as a backlog item. Don't silently create out-of-scope work.

If `## Scope` lists open product questions and the request touches one of them, flag that a decision is needed rather than assuming an answer.

Then ask clarifying questions — but **only** for things you genuinely can't infer and that would change the implementation. Good things to clarify:
- The user-facing behaviour when it's ambiguous (what exactly happens, on which screen)
- Edge cases that materially change the work (empty states, missing data, unusual input)
- Whether something is a bug (restore intended behaviour) vs an enhancement (new behaviour)

Don't interrogate. If the request is small and clear, skip straight to drafting. Prefer proposing a sensible default and letting the user correct it over asking open-ended questions.

### Step 3 — Draft the issue

Produce a title and body. **Show the full draft to the user in chat — do not create it yet.**

**Title:** short, imperative, specific. e.g. `Add story preview step before posting`, not `Submit flow improvements`.

**Body:** use the template below, but **scale it to the change**. A one-line CSS fix does not need a Background section and eight acceptance criteria; a new feature does. Drop any section that would just be filler. Never pad with invented requirements.

```markdown
## <one-line summary of the goal>

**Goal:** <what the user should be able to do, and why — the outcome, not the implementation>

### Background
<only if context helps the implementer — link the relevant screen/feature, the current behaviour, why this matters. Omit for trivial changes.>

### Requirements
<the concrete, in-scope work. Pull relevant stack facts and file/module pointers from `project.md`'s `## Stack notes` and `context_doc` where it helps.
Describe WHAT is needed; suggest an approach only where it removes ambiguity, and mark it as a suggestion so the implementer can choose.>

### Acceptance criteria
- [ ] <observable, testable outcomes — what "done" looks like from the user's side>
- [ ] <any project-wide acceptance bars from `project.md`'s `## Review checklist` / `## Design checklist` that apply to this change — e.g. mobile layout, design tokens, no regressions on key surfaces>

### Out of scope
<explicitly fence off adjacent work so the implementer doesn't sprawl>

### Notes for the implementing agent
<stack reminders or gotchas specific to this issue, from `project.md`. Keep short. Omit if nothing non-obvious.>
```

Guidance on detail level:
- **Bug fix:** Goal + steps to reproduce / current vs expected + acceptance criteria. Usually no Requirements section.
- **Small enhancement:** Goal + a short Requirements list + acceptance criteria.
- **Feature:** the full template.

### Step 4 — Propose labels

Suggest labels based on the request, and confirm with the user (or let them adjust):
- `bug` — restoring broken/intended behaviour
- `enhancement` — new or improved behaviour
- Any project-specific label scheme (phase/priority) mentioned in `project.md`

Only apply labels that exist in the repo. Check with `mcp__github__list_issues` output or `mcp__github__get_label` if unsure; if a desired label doesn't exist, mention it rather than failing the whole creation.

### Step 5 — Get explicit confirmation

Show the user the final **title, body, and labels** together and ask for a clear go-ahead. Creating a GitHub issue posts to a shared repo, so wait for an explicit "yes / create it" before proceeding. If the user requests changes, revise and re-confirm.

### Step 6 — Create the issue

Call `mcp__github__issue_write` with:
- `method`: `create`
- `owner`: from `project.md`
- `repo`: from `project.md`
- `title`: the approved title
- `body`: the approved body
- `labels`: the approved labels

Capture the returned **issue number** and **URL**.

### Step 7 — Add to the Project board

If `project.md`'s `project_board` section is present, add the new issue to it. The GitHub MCP does not expose Project tools, so use the `gh` CLI:

```bash
gh project item-add <project_board.number> --owner <project_board.owner> --url <issue-url>
```

Handle the likely failure modes honestly — do not claim the board was updated if it wasn't:
- If `gh` is **not installed** (`command not found`): tell the user, and that they can install it with `brew install gh` then `gh auth login`, or add the issue to the board manually. Don't block — the issue is already created.
- If `gh` is installed but **not authenticated**: tell the user to run `gh auth login`.
- If it fails with **missing scopes** (`read:project` / `project`): the token needs the project scope. Tell the user to run `gh auth refresh -s project` (this writes to the board, so the `project` scope is required, not just `read:project`).
- If the command **succeeds**: confirm the issue is on the board, at whatever default status new items land on (commonly "Backlog"). Leave it there — triage/prioritisation happens on the board, not in this command.

If `project.md` has no `project_board` section, skip this step.

### Step 8 — Report back

Print a short summary:
```
✓ Issue:   #<number> — <title>
✓ URL:     <issue-url>
✓ Labels:  <labels, or "none">
✓ Board:   added to <project name/number>, status: <status>  |  not added (<reason>)  |  n/a (no board configured)
```

Then offer the natural next step: `Run /ship-issue <number> to implement it.`

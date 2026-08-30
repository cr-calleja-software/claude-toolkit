---
description: Thorough code review of the current branch diff against main, or a PR
---

# code-review

Thorough code review of the current branch diff against `main`. Checks correctness, security, type safety, mobile layout, and project conventions. Optionally posts findings as inline PR comments.

> **Prerequisite:** the `--pr` and `--comment` flags require the GitHub MCP server (`mcp__github__*` tools) to be configured. The default local-diff review needs only `git`.
>
> **Config:** this command reads `.claude/project.md` at the repo root for `owner`/`repo` and the project-specific `## Review checklist`. If that file is missing, stop and tell the user it needs to exist before this command can run.

## Usage

```
/cr:code-review [--pr <number>] [--fix] [--comment]
```

- `--pr <number>` — review a specific open PR instead of the local diff
- `--fix` — apply safe fixes directly to the working tree after reviewing
- `--comment` — post findings as inline GitHub PR review comments (requires `--pr`)

---

## Instructions

You are performing a code review. Arguments: **$ARGUMENTS**

Read `.claude/project.md` first for `owner`/`repo` and the `## Review checklist` section — its bullets are project-specific findings to check for in addition to the generic checklist below.

Parse flags from the arguments:
- If `--pr <N>` is present, fetch that PR's diff via `mcp__github__pull_request_read` (`owner`/`repo` from `project.md`, `pullNumber: N`). Also fetch the file list.
- Otherwise, run `git diff main...HEAD` and `git diff --name-only main...HEAD` to get the local diff.

---

### Review checklist

Go through every changed file. For each finding, note: **file**, **line**, **severity** (🔴 bug / 🟡 warning / 🔵 suggestion), and a clear one-sentence explanation.

#### 1. Correctness
- Logic errors, off-by-one, wrong conditions
- Async/await misuse, missing `await`, unhandled promise rejections
- Data shape mismatches between the project's data model (see `context_doc`) and what components/route handlers consume
- Filter/sort functions that mutate the original array
- Anything called out under `project.md`'s `## Review checklist`

#### 2. Type safety
- Any use of `any` (or the language's equivalent escape hatch) without a written reason — propose a proper type
- Non-null assertions without justification
- Implicit `any` from untyped function parameters
- Return types missing on exported functions

#### 3. Security & data protection
- User-supplied input rendered without sanitisation (XSS)
- `dangerouslySetInnerHTML` or equivalent raw-HTML injection
- Secrets or connection strings committed (API keys, DB URLs — belong in `.env.local`/host env vars, never the repo)
- Raw SQL built from user input instead of a parameterised query/ORM (SQL injection)
- Any data-privacy rule from `project.md`'s `## Review checklist` (e.g. PII minimisation, location/precision limits, content visibility rules)
- `eval` or `new Function`

#### 4. Framework / stack conventions
- Client-side rendering used where server-side would work (and vice versa where interactivity is actually needed)
- Pages that should be server-rendered for SEO/shareability accidentally pushed client-side
- Missing per-page metadata / Open Graph tags where the project expects them
- Missing or wrong `key` props in lists
- `useEffect` (or equivalent) with a missing or incorrect dependency array
- Data fetching in a component render body instead of the project's intended data-fetching layer
- Images not using the framework's optimised image component

#### 5. Styling / mobile-first / design system
- Hardcoded colours, fonts, or spacing/radius values that duplicate a token already defined in the project's design system
- Desktop-only styles without a mobile baseline
- Layout that would break at the project's mobile-width baseline
- Any UI-state rule from `project.md`'s `## Design checklist` (e.g. mutually-exclusive selection states, empty-state requirements)

#### 6. Project conventions
- Out-of-scope features introduced early (check `project.md`'s `## Scope`)
- Reference-only/prototype markup copied into real app code instead of used as design reference only
- File/component naming convention violations (per `context_doc`)
- Styling approach violations (e.g. CSS modules/styled-components used when the project mandates a single styling system)
- Comments that just describe what the code does (remove them)

#### 7. Performance / data layer
- Expensive operations (sort, filter, map) repeated on every render — should be memoised or moved server-side
- Querying the database/data source directly inside a UI component instead of going through the project's defined data/query layer
- N+1 queries (e.g. fetching related records per item in a loop instead of one joined/batched query)
- Selecting whole rows/objects when only a subset of fields is needed

#### 8. Discoverability

Applies when the diff touches the public surface — adds, removes or renames a
route, or changes what the site offers. Skip for pure refactors and internal
logic.

Only the route-scoped checks are gated this way. Metadata, Open Graph and
server-rendering apply to *every* diff and stay in section 4 — a refactor that
drops an `export const metadata` or pushes a page client-side adds no route, so
gating those here would stop them firing exactly when they are needed.

- A new public route missing from the project's sitemap
- `llms.txt` (or equivalent) not updated when the set of public routes changed, or when its prose no longer describes what the site offers
- Missing canonical URL on a new page
- A new entity page emitting no schema.org structured data where its siblings do
- A hardcoded value in a discoverability file that is derivable from data (an item count, a season, a date range) and will silently go stale
- **A hand-maintained file duplicating something already generated** — e.g. a static `llms.txt` listing routes that the sitemap derives from data. Two hand-maintained lists of the same facts drift, and nothing compares them; flag it even when both are currently correct
- Anything called out under `project.md`'s `## Discoverability checklist` — the surfaces only that repo can name. Skip if the section is absent

---

### Output format

If `--comment` flag is present AND a PR number was provided: post each finding as an inline PR review comment using `mcp__github__add_comment_to_pending_review` or `mcp__github__pull_request_review_write`, then submit the review.

Otherwise, output a Markdown report:

```markdown
## Code review — <branch or PR title>

### 🔴 Bugs (must fix before merge)
- `path/to/file.tsx:42` — <finding>

### 🟡 Warnings (should fix)
- `path/to/file.tsx:17` — <finding>

### 🔵 Suggestions (optional improvements)
- `path/to/file.tsx:88` — <finding>

### ✅ Looks good
- <brief note on what was done well, if anything>
```

If `--fix` flag is present: after printing the report, apply all 🔴 bug fixes and clearly 🟡 warnings that have an unambiguous fix to the working tree. Do not apply 🔵 suggestions without asking. Print a summary of what was changed.

If there are zero findings, output: `✅ No issues found.`

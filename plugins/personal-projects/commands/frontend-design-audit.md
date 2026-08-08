---
description: UI/UX design audit for frontend changes, with project-specific checks from project.md
---

# frontend-design-audit

UI/UX design audit for any frontend change. Run this **automatically after implementing any frontend code** (new pages, components, layout changes). Produces a structured audit report and — if issues are found — applies fixes before committing.

> **When to invoke:** Any time frontend code is written or modified (components, pages, styling, layout). Also available on demand as `/frontend-design-audit`.
>
> **Config:** this command reads `.claude/project.md` at the repo root for `owner`/`repo` and the project-specific `## Design checklist`. If that file is missing, stop and tell the user it needs to exist before this command can run.

## Usage

```
/frontend-design-audit [--fix] [--pr <number>]
```

- `--fix` — apply recommended fixes to the working tree after auditing
- `--pr <number>` — audit a specific PR's frontend changes instead of the local diff

---

## Instructions

You are an expert UI/UX designer and auditor with deep knowledge of interface design principles, accessibility standards (WCAG 2.1), visual hierarchy, responsive design, and conversion optimisation. Arguments: **$ARGUMENTS**

Read `.claude/project.md` first for `owner`/`repo` and the `## Design checklist` section — its bullets are project-specific findings to check for in addition to the generic dimensions below.

Parse flags from the arguments:
- If `--pr <N>` is present, fetch that PR's diff via `mcp__github__pull_request_read` (`owner`/`repo` from `project.md`, `pullNumber: N`). Read the changed frontend files in full.
- Otherwise, run `git diff main...HEAD -- '*.tsx' '*.ts' '*.css'` (adjust extensions to the project's stack) and read the changed component and page files in full.

If `project.md` or `context_doc` points at a design-system reference (tokens file, style guide, prototype), skim it before auditing so findings are judged against the actual chosen design direction, not generic taste.

Evaluate the interface across the following dimensions. Assess **both mobile (~390px viewport, or whatever mobile baseline `project.md` specifies) and desktop (~1440px viewport)** for each dimension.

---

### Audit Dimensions

#### 1. Visual Hierarchy & Layout
- Is the information architecture clear? Does the eye land in the right place?
- Are spacing, sizing, and grouping used intentionally, mapped to the project's design tokens?
- Are there layout inconsistencies across breakpoints?

#### 2. Typography
- Is the type scale logical and consistent with the project's chosen type pairing?
- Are font weights, sizes, and line heights appropriate for readability?
- Are there orphaned lines, overflow issues, or illegible text at any viewport size?

#### 3. Colour & Contrast
- Do all text/background combinations meet WCAG AA (4.5:1 for body text, 3:1 for large text)?
- Is colour used consistently with clear intent, per the project's palette?
- Are interactive elements distinguishable without relying solely on colour?

#### 4. Components & Consistency
- Are buttons, cards, and other components used consistently with the project's shared component classes/primitives, rather than one-off styles?
- Are states (hover, focus, active, disabled, error) defined and visible?
- Are there redundant or conflicting component patterns?

#### 5. Responsiveness & Mobile Experience
- Does the layout adapt cleanly from the project's mobile baseline upward?
- Are touch targets a minimum of 44×44px?
- Is content readable without horizontal scrolling or zooming?
- Are any elements clipped, overlapping, or broken at mobile widths?
- Are responsive utility classes used correctly and not as a substitute for a mobile-first base?

#### 6. Accessibility
- Are interactive elements keyboard navigable with visible focus states?
- Are images given meaningful `alt` text (or `alt=""` if decorative)?
- Are form fields associated with labels via `htmlFor`/`id` or equivalent?
- Is heading hierarchy logical (H1 → H2 → H3 — no skipped levels)?
- Are ARIA attributes used correctly when native semantics fall short?

#### 7. Performance Indicators (visual / code)
- Are there signs of layout shift, unloaded images, or render-blocking patterns?
- Are animations or transitions excessive, distracting, or missing `prefers-reduced-motion` support?
- Are expensive operations (sort, filter, map) inside render that should be server-side or memoised?

#### 8. Copy & Microcopy
- Is the language clear and consistent with the project's intended tone?
- Are error messages, empty states, and CTAs specific and helpful?
- Is there unnecessary jargon or filler text?

#### 9. Trust & Conversion (if applicable)
- Are CTAs prominent and unambiguous?
- Is the value proposition immediately clear above the fold?
- Are there friction points in any user flows visible on the changed pages?

---

### Project-specific checks

Pull these from `project.md`'s `## Design checklist` section — e.g. mutually-exclusive selection states, content-visibility/precision rules, empty-state tone, specific component treatments. Check every bullet listed there against the changed files.

---

### Output Format

Produce a structured **UI Audit Report**:

```markdown
## UI Audit — <page or component name>

### Summary
2–3 sentence overview of the current state.

### Critical Issues 🔴
Must-fix items that break usability, accessibility, or functionality.
- **Issue:** <description>
  **Where:** <component/section + desktop/mobile>
  **Fix:** <specific recommendation>

### High Priority Issues 🟠
Significant UX or visual problems to address soon.

### Medium Priority Issues 🟡
Meaningful improvements but not urgent.

### Low Priority / Polish 🟢
Nice-to-have refinements and minor inconsistencies.

### Positive Observations ✅
What is working well.

### Recommended Next Actions
1. <most impactful action — specific task statement>
2. ...
3. ...
```

Every finding must reference a **specific element, component, or class** from the actual code — no generic advice.

---

### After the report

If `--fix` flag is present: apply all 🔴 critical fixes and unambiguous 🟠 high-priority fixes to the working tree using the Edit tool. Print a summary of what was changed. Do not apply 🟡 / 🟢 fixes without asking.

If no `--fix` flag: present the report and ask the user whether to apply the fixes before proceeding.

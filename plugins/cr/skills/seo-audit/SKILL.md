---
name: seo-audit
description: >-
  Read-only audit of a project's on-site SEO and AI/LLM discoverability. Scans
  the Next.js codebase for metadata, crawlability (sitemap/robots), schema.org
  structured data, indexable surface, and LLM-readability, then reports the
  current state and a prioritised list of improvements. Use this whenever the
  user asks to audit, review, check, or improve SEO, search ranking, Google
  discoverability, link previews, structured data, sitemaps, or how findable the
  site is by search engines or AI assistants (ChatGPT, Perplexity, AI Overviews)
  — even if they just say "how's our SEO" or "can people find us". Does not edit
  code or open issues; it reports and recommends.
---

# SEO & LLM Discoverability Audit

This skill audits a Next.js app for how discoverable it is by search engines
and AI assistants, then hands back a prioritised list of fixes.

The point is repeatability: instead of re-deriving the SEO checklist by hand each
time, run this to get a consistent state-of-play and a ranked set of next steps.
It is the natural companion to `/cr:create-issue` — audit first, then file the
high-impact gaps.

## Config

Read `.claude/project.md` at the repo root first. Its frontmatter gives the
production origin/deploy target if noted under `## Stack notes`, and its
`context_doc` points at the file(s) describing the data model — needed to know
what structured-data types and per-entity pages this app should have (e.g. an
`Article`/`Event`/`Product` type per record, driven from the project's data
source). If `project.md` is missing, stop and tell the user it needs to exist
before this skill can run.

Also read its **optional** `## Discoverability checklist`, if present — the
surfaces only that repo can name (which files list its public routes, which
pages need structured data, which generated artefacts must stay in sync). This
is the same section `/cr:code-review`'s section 8 and `/cr:ship-issue`'s Step 4.6
read; here it applies to the whole project rather than one diff. The section
being absent is **not** the missing-file case above and never blocks the audit —
see *Notes*.

## Ground rules

**This skill is read-only.** Audit and recommend only. Do not edit app code, do
not create files, do not open GitHub issues. The deliverable is a report in the
chat. If the user wants to act on a finding, point them at `/cr:create-issue`.

Keep it grounded in what's actually in the repo. Every finding must cite the real
file (or its absence) — `app/layout.tsx:23`, "no `app/sitemap.ts`", etc. Don't
report generic SEO advice that isn't tied to this codebase's current state.

## How to run the audit

Work through the six areas below. For each, inspect the relevant files and decide
the status: ✅ present and correct / ⚠️ present but needs improvement / ❌ missing.
Favour the dedicated search/read tools (Glob, Grep, Read) — this is a fast scan,
not a build.

Bullets from `project.md`'s `## Discoverability checklist` cut **across** these
areas rather than belonging to one. Most will land in *2. Crawlability* or
*5. AI/LLM discoverability*, but a repo is free to write one about structured
data or metadata, so check each against the area it actually concerns. Every one
of them is in scope for this audit — unlike the per-diff gate in
`/cr:ship-issue`, a whole-project audit has no reason to skip any.

### 1. Metadata

The foundation for search snippets and social link previews.

- `app/layout.tsx` — root `metadata`: `metadataBase` (must resolve to the real
  production origin, not `localhost` — check the actual deploy target from
  `project.md`, not just a `VERCEL_*` fallback if the project deploys elsewhere),
  `title`, `description`, `keywords`, `openGraph`, `twitter`.
- Per-route `generateMetadata` / exported `metadata` in dynamic routes — does
  each entity page get a unique title/description drawn from its own content, or
  do pages inherit the root's generic metadata?
- OpenGraph image: static fallback, or generated per-entity where that matters
  for shareability?
- `app/manifest.ts` — name, icons, theme colour.

### 2. Crawlability

Whether search engines can find and traverse the site.

- `app/sitemap.ts` (or `public/sitemap.xml`) — exists? Does it enumerate every
  indexable route, including dynamic entity pages? If the entity count is
  unbounded/user-generated, this must be generated from the data source, not
  hand-maintained.
- `app/robots.ts` (or `public/robots.txt`) — exists? Allows crawlers and points
  to the sitemap URL? Any content that must never be indexed (removed/flagged/
  draft records, per `project.md`) — confirm it's actually excluded, not just
  hidden client-side.
- Canonical URLs — set per route, absolute, on the production origin?

### 3. Structured data (schema.org JSON-LD)

This is the highest-leverage area for both Google rich results and LLM parsing.

- Search for any `application/ld+json` script or JSON-LD helper (`grep -ri
'ld+json\|jsonld\|@context' app components lib`).
- Expected type(s) depend on the project's data model (`context_doc`) — e.g.
  `Article`/`SocialMediaPosting` for user content, `Event` for scheduled
  events, `Product` for listings — plus site-level `WebSite`/`Organization`.
- For any JSON-LD found, check required fields are present and dates are ISO 8601.
- If the data model has a privacy/precision rule (e.g. location precision
  tiers, PII minimisation — check `project.md`'s `## Review checklist`),
  confirm structured data never exposes more than what was chosen/collected.

### 4. Indexable surface

How many things this site can actually rank for.

- Count distinct indexable routes (static + dynamic).
- Compare against the data source — how many entities _could_ have their own
  page but don't? If the dataset grows over time, check the sitemap/route
  generation actually scales with it rather than being capped or paginated in
  a way that hides older entities from crawlers.
- Internal linking — do list/feed views link to detail pages so crawlers (and
  users) can reach them?

### 5. AI/LLM discoverability

What makes ChatGPT, Perplexity, and AI Overviews able to cite the site.

- Structured data quality (covered above) is the biggest factor.
- `public/llms.txt` — present? (An emerging convention for guiding LLM crawlers.)
- Semantic HTML and descriptive headings — is content in real
  `<h1>/<h2>`, `<article>`, `<time>` etc., or is it div soup that's hard to parse?
- Is key content server-rendered (in the initial HTML) rather than requiring
  client JS? Server components are good here.

### 6. Performance & mobile signals (lightweight)

These influence ranking but only need a quick pass — don't profile.

- Mobile-first: does the app render sensibly at the project's mobile baseline?
- Images: optimised-image-component usage, explicit dimensions, lazy loading.
- Obvious render-blocking or oversized assets.

## Report format

Output exactly this structure so successive audits are comparable:

```
# SEO & LLM Discoverability Audit — <project name>
_<date> · branch <branch>_

## State of play
For each of the six areas, a short subsection with ✅/⚠️/❌ lines, each citing a
real file or its absence. Example:
### Metadata
- ✅ Root title + description + OG image (`app/layout.tsx:28`)
- ❌ Entity pages have no per-entity `generateMetadata` — all share the root
  title/description (`app/<entity>/[id]/page.tsx`)
### Crawlability
- ❌ `/contact` is listed in `llms.txt` but missing from `app/sitemap.ts`
  — **project rule**

## Prioritised improvements
A ranked table — highest impact first. Impact = effect on traffic/discoverability
weighed against effort.

| # | Improvement | Impact | Effort | Why |
|---|-------------|--------|--------|-----|
| 1 | ... | High | Med | ... |
| 2 | Add `/contact` to `app/sitemap.ts` — **project rule** | High | Low | ... |

## Suggested next step
One line, e.g. "File the high-impact items with /cr:create-issue."
```

Tag any finding that comes from `project.md`'s `## Discoverability checklist`
with **project rule**, so a reader can tell what this repo has declared from what
the skill checks everywhere. Both are real findings; they carry different weight.

Use High / Medium / Low for both Impact and Effort. Order the table by impact,
then by lowest effort. Keep the "Why" to one line — concrete, tied to this app.
A **project rule** is a stated policy rather than advice, so rank it at least as
high as an equivalent generic finding, say in "Why" that the project asked for
it, and tag the row as well as the *State of play* line — the table is the half
someone acts on, and it should be scannable without reading every "Why".

## Notes

- Don't invent gaps to pad the list. If an area is genuinely solid, say so with ✅
  and move on — a short honest audit beats a long speculative one.
- **A missing `## Discoverability checklist` is never itself a finding.** The
  section is optional; when it is absent, audit exactly as described above and
  say nothing about it. Do not suggest adding one — that is the user's call, not
  an SEO gap.
- If you find an existing tracking issue/epic for a gap, note it next to the
  finding so the user doesn't double-file.

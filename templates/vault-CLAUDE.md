# Second Brain — Schema & Operating Rules

## Purpose

This is a persistent, LLM-maintained personal knowledge base. The LLM curates the structured wiki (entities, concepts, sources, index, log). The human supplies sources, asks questions, directs analysis, and writes durable notes and decisions. This document governs every session.

---

## Directory Structure

```
/
├── CLAUDE.md              ← this file (schema + rules)
├── raw/
│   ├── sources/           ← immutable source documents (articles, papers, notes, transcripts)
│   └── assets/            ← images, PDFs, attachments referenced by sources
├── wiki/
│   ├── entities/          ← one page per person, place, organization, product (LLM-owned)
│   ├── concepts/          ← one page per idea, theory, framework, theme (LLM-owned)
│   ├── sources/           ← one summary page per ingested source (LLM-owned)
│   ├── queries/           ← saved answers, analyses, comparisons (LLM-owned; human may add)
│   ├── notes/             ← human-authored: ADRs, lab notes, hypotheses, observations
│   └── meta/              ← index.md, log.md, and other housekeeping pages (LLM-owned)
```

**Rules:**

- `raw/` is read-only. Never modify or delete source files.
- `wiki/entities/`, `wiki/concepts/`, `wiki/sources/`, and `wiki/meta/` are LLM-owned. The human reads; the LLM writes.
- `wiki/notes/` is human-authored. The LLM may read and cross-link from other pages but must not edit note content. The LLM may suggest edits in chat.
- `wiki/queries/` is primarily LLM-owned, but the human may add or edit query pages.
- Every wiki page must have YAML frontmatter (see Page Format below).

---

## Page Format

Every wiki page must start with YAML frontmatter:

```yaml
---
title: "Page Title"
type: entity | concept | source | query | note | meta
kind: decision | observation | hypothesis | lab-note   # for notes only
tags: [tag1, tag2]
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources: [source-slug-1, source-slug-2]                # omit for notes and meta
archived: true | false                                  # optional, default false
---
```

Body conventions:

- Use `## Sections` for major divisions.
- Cross-reference other wiki pages with `[[PageName]]` (Obsidian wikilink syntax).
- Cite raw sources inline as `[Source Title](../sources/filename.md)`.
- Mark uncertain or contested claims with `> **[UNCERTAIN]**` blockquotes.
- Mark contradictions with `> **[CONTRADICTION with [[OtherPage]]]**`.
- When a page receives a significant update (new contradicting source, major reinterpretation), append a `## History` section at the bottom with the date and a one-line note of what changed. Do not silently overwrite reasoning.

---

## Operations

### 1. Ingest (full)

**Trigger:** Human drops a file in `raw/sources/` and says "ingest [filename]" (or pastes text directly). Use for substantive sources: papers, long articles, transcripts, decision-shaping reading.

**Steps the LLM must follow:**

1. Read the source fully.
2. Briefly discuss 3-5 key takeaways with the human. Ask if anything should be emphasized or deprioritized.
3. Create `wiki/sources/<slug>.md` — a structured summary with: Overview, Key Claims, Notable Entities, Key Concepts, Open Questions.
4. For each entity mentioned: update or create `wiki/entities/<name>.md`.
5. For each concept mentioned: update or create `wiki/concepts/<name>.md`.
6. Update `wiki/meta/index.md` — add the new source and any new entity/concept pages.
7. Append an entry to `wiki/meta/log.md`.
8. Report: how many pages were created vs. updated, any contradictions found.

**Never skip steps 6 and 7.**

### 1b. Quick Ingest

**Trigger:** Human says "quick-ingest [filename]" or pastes a short clipping and says "drop this in raw". Use for short clippings, casual notes, or material whose entities and concepts will be propagated later.

**Steps:**

1. Read the source.
2. Create `wiki/sources/<slug>.md` with at minimum: Overview (2-3 sentences) and Key Claims (bullets).
3. Add the source to `wiki/meta/index.md` under Sources.
4. Append an entry to `wiki/meta/log.md` tagged `quick-ingest`.
5. Do **not** propagate to entities/concepts yet. Note in the log that entities/concepts are deferred.

**Promotion:** Quick-ingests are promoted to full ingests when the human says "promote [slug]" or when a Lint pass identifies them as candidates. Heavy sources (see 1c) are promoted via Deep Ingest instead.

### 1c. Deep Ingest (promoção profunda)

**Trigger:** Human says "deep-ingest [slug]". Default for transcripts longer than ~5,000 lines or ~100 messages, and whenever a Query/Synthesize/Lint pass reveals that a heavy source's summary missed substantive content (e.g., a whole sub-architecture).

**Rationale:** a fixed-budget summary of a very long thread silently drops entire sub-projects. Deep Ingest trades prose for a structured inventory whose job is **findability** — every decision, parameter, bug, and artifact must be reachable through the graph. `raw/` remains the ground truth; the wiki must make it findable.

**Steps the LLM must follow:**

1. Read the **full raw transcript in chunks** — never work from the existing summary page. Accumulate extraction notes outside the wiki while reading.
2. Rewrite `wiki/sources/<slug>.md` as a structured inventory with these sections:
    - **Overview** (expanded, with thread arc/phases)
    - **Decisions** — what was decided, what was rejected, and why
    - **Parameters & values** — table: components, pins, frequencies, versions, thresholds
    - **Bugs & fixes** — found, root cause, resolution
    - **Artifacts** — firmware versions, schematics, scripts, documents produced in the thread
    - **Open threads** — questions or work the conversation left unfinished
    - **Notable Entities / Key Concepts** (as in full ingest)
3. **Reconcile against the existing graph:** check every extracted fact against entity, concept, and synthesis pages; fix divergences with `## History` entries (this is how wrong claims like a mis-identified chip get caught).
4. Propagate any new entities/concepts discovered.
5. Update `wiki/meta/index.md`; append to `wiki/meta/log.md` tagged `deep-ingest`.
6. Update the source page footer: deep-ingest supersedes quick-ingest status.

**Never skip step 3** — reconciliation is the point of the operation.

### 2. Query

**Trigger:** Human asks a question not directly answered in one page.

**Steps:**

1. Read `wiki/meta/index.md` to find relevant pages.
2. Read those pages.
3. Synthesize an answer with citations (`[[PageName]]`).
4. Ask: "Should I file this as a query page?" If yes, write `wiki/queries/<slug>.md`.
5. If the answer reveals a gap or contradiction, note it and suggest a follow-up source.

### 3. Lint

**Trigger:** Human says "lint the wiki" or "health check".

**Steps the LLM must follow:**

1. Read all pages in `wiki/`.
2. Report:
    - **Orphans:** pages with no inbound links.
    - **Stubs:** pages with fewer than 3 sentences of content.
    - **Contradictions:** flag any `[CONTRADICTION]` markers for human review.
    - **Stale claims:** cross-reference source dates; flag claims from sources >1 year old that newer sources challenge.
    - **Missing pages:** entities or concepts mentioned but lacking their own page.
    - **Missing cross-references:** pages that should link to each other but don't.
    - **Promotion candidates:** quick-ingest sources whose entities/concepts haven't been propagated.
    - **Archival candidates:** query pages older than 6 months with no inbound links — propose marking `archived: true` or absorbing into a concept page.
3. Propose a prioritized fix list.

### 4. Synthesize

**Trigger:** Human says "synthesize [topic]" or "write an overview of [topic]".

**Steps:**

1. Read all relevant entity, concept, source, and note pages.
2. Write a synthesis page in `wiki/queries/` with a thesis, supporting evidence, and open questions.
3. Update index.md.
4. Log the synthesis in log.md.

### 5. Note (human-initiated)

**Trigger:** Human writes a page in `wiki/notes/` directly, or says "log this decision/observation/hypothesis".

**LLM's role:**

- Does **not** modify note content.
- May cross-link the note from relevant entity/concept pages.
- Adds the note to `wiki/meta/index.md` under Notes.
- Appends an entry to `wiki/meta/log.md`.

### 6. Challenge (red-team)

**Trigger:** Human says "challenge this", "red-team this", "stress-test this decision", or asks to pressure-test a claim/plan that is in — or implied by — the vault. Also worth offering **proactively** when a claim is *non-trivial* — it asserts a property the record cannot self-verify (optimality, safety, "this scales", a causal claim), spans domains, rests on context not written down, or is costly/irreversible to act on (a fabrication order, a design freeze). (Non-trivial trigger adapted from `addyosmani/agent-skills` doubt-driven-development.)

**Steps:**

1. **Extract** the claim: restate it in 2–3 lines plus its *contract* (what must hold for it to be true), and strip the reasoning that produced it — hand the adversarial pass only the claim + contract, uncontaminated by the rationalizations that built it.
2. Search the vault for counter-evidence (spawn parallel **fresh-context** subagents if the surface is large, briefed to *disprove*, not confirm): `[UNCERTAIN]`/`[CONTRADICTION]` markers, `## History` reversals, past decisions in `wiki/notes/` and `wiki/queries/`, and sources whose claims undercut the premises.
3. Produce a **Red-Team** analysis: **Position** (restate) · **Counter-evidence** (cite `[[Page]]` + dates/quotes) · **Blind spots** (what the record suggests is being ignored) · **Verdict** (consistent with the vault's history, or caution warranted).
4. Do **not** be agreeable — the point is to pressure-test. Cite specific pages. If nothing contradicts, say so honestly, but only after searching thoroughly (see anti-fabrication in Quality Rules).
5. Offer to file the analysis as `wiki/queries/YYYY-MM-DD-redteam-<topic>.md`. Append an entry to `wiki/meta/log.md`.

### 7. Connect (cross-pollinate)

**Trigger:** Human says "connect [A] and [B]", "cross-pollinate", "bridge these domains", or "find an unexpected link" between two topics/concepts/entities.

**Steps:**

1. For each of the two domains, build a local cluster from `[[wikilinks]]`, shared tags, and shared entities.
2. Find the bridge: shared links/tags/entities between the clusters — trace the graph path and explain each hop; if none exists, find the closest conceptual or structural overlap.
3. Generate: **structural analogy** (how a pattern in A maps to B) · **transfer opportunities** (what works in A that could apply to B) · **collision ideas** (concepts that only exist at the intersection).
4. Present 3–5 concrete, actionable connections — not vague analogies. If a connection is obvious, dig deeper.
5. Offer to save the strongest as a `wiki/concepts/` or `wiki/queries/` page linking both source domains. Append an entry to `wiki/meta/log.md`.

### 8. Emerge (surface patterns)

**Trigger:** Human says "what's emerging", "surface themes", "find patterns", or asks what the recent material adds up to (optionally over a timeframe or a named scope).

**Steps:**

1. Determine scope — a timeframe (via `wiki/meta/log.md` dates) or a set of sources/queries/notes.
2. Read the in-scope pages; extract recurring topics, repeated blockers/open questions, and directional trends.
3. Identify: **recurring themes** (appearing 3+ times without being named as a theme) · **unnamed conclusions** the pages imply but never state outright · **emerging directions** the material points toward.
4. Present a **Pattern Report**: each pattern = evidence (cited `[[Pages]]`) · interpretation · suggested action.
5. Surface what has not been named yet — do not restate the known. Offer to file as a synthesis in `wiki/queries/`. Append an entry to `wiki/meta/log.md`.

---

## Index Format (`wiki/meta/index.md`)

Organized by category. Each entry: `- [[PageName]] — one-line summary`.

Categories: Sources | Entities | Concepts | Queries | Notes | Meta

The LLM reads the index when running a query, synthesis, or lint — **not** on every session start.

---

## Log Format (`wiki/meta/log.md`)

Append-only. Each entry:

```
## [YYYY-MM-DD] <operation> | <title>
- What was done (bullet list, max 5 lines)
```

Parseable with: `grep "^## \[" wiki/meta/log.md`

---

## Naming Conventions

|Item|Convention|Example|
|---|---|---|
|Source slug|kebab-case of title|`vannevar-bush-memex-1945.md`|
|Entity page|TitleCase|`VannevarBush.md`|
|Concept page|TitleCase|`AssociativeIndexing.md`|
|Query page|`YYYY-MM-DD-kebab-title.md`|`2026-06-02-memex-vs-rag.md`|
|Note page|`YYYY-MM-DD-kebab-title.md`|`2026-06-03-fram-wear-leveling-decision.md`|

---

## Session Start Protocol

The LLM reads this CLAUDE.md at the start of every session.

The LLM does **not** automatically read `index.md` or `log.md` on every session — that is expensive and unnecessary for most interactions. Those files are read on demand:

- When the human asks "status", "where are we", or "what's the state of the wiki".
- When the operation requires it (Query, Synthesize, Lint).
- When the human's request implies the LLM should know what already exists.

When the human explicitly asks for status, the LLM greets with: current wiki stats (page counts by type), last operation logged, and a suggested next action.

---

## Quality Rules

- Never invent facts. If uncertain, mark with `[UNCERTAIN]`.
- Never delete content from source pages in `raw/`. Only append or update wiki pages.
- Every claim in the wiki must be traceable to at least one source page or human-authored note.
- Cross-reference liberally. A page with no outbound links is a failure.
- Keep entity and concept pages current — when a new source contradicts an old claim, update the page, note the contradiction inline, and append a `## History` entry.
- Do not silently overwrite reasoning. Significant rewrites must leave a History trail.
- If you are unsure whether to create a new page or update an existing one, prefer updating.
- Do not edit content inside `wiki/notes/`. Suggest changes in chat instead.

---

## Archival Policy

- Pages may set `archived: true` in frontmatter to retire them without deletion.
- Archived pages are excluded from Lint orphan/stub reports and from primary index listings (they remain searchable).
- Lint proposes archival for query pages older than 6 months with no inbound links.
- The human approves archival; the LLM does not archive autonomously.

---

## Human's Role

- Curate and supply sources.
- Ask questions and direct analysis.
- Decide what to emphasize or deprioritize during ingest.
- Write notes (`wiki/notes/`) — decisions, lab observations, hypotheses.
- Review Lint reports and approve fixes and archivals.
- The human does NOT write entity, concept, source, or meta pages — those are LLM-maintained.

---

_Template — an LLM-maintained Obsidian "second brain" schema (raw/ + wiki/, with the
Ingest / Query / Lint / Synthesize / Note operations and the "thinking" ops
Challenge / Connect / Emerge). Operations 6–8 are adapted from the thinking-tools in
`eugeniughelbur/obsidian-second-brain`; the §6 EXTRACT / non-trivial trigger is mined from
`addyosmani/agent-skills` (doubt-driven-development). Adapt the naming examples and tags to
your own domain — the vault starts empty. Keep a version + changelog here as you evolve it._
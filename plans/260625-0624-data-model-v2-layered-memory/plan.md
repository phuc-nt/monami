---
title: Data Model v2 — Layered Memory + Curriculum-in-Firestore
description: >-
  Replace the single 800-char memory blob with layered memory (durable
  code-merged facts about the child + soft model summary + split-out done_topics);
  move curriculum to Firestore with JSON fallback. Backward-compatible, no
  migration script, privacy unchanged (stays within the disclosed "conversation
  summaries"). Session journal + usage analytics CUT for privacy reasons.
status: completed
priority: P2
created: 2026-06-25T00:00:00.000Z
blockedBy: []
blocks: []
---

# Data Model v2 — Layered Memory + Curriculum-in-Firestore

## Overview

Today memory is ONE 800-char text blob (`memory.summary`) the model rewrites each
session → old facts get overwritten, no long-term accumulation. Curriculum is
static JSON in the repo (adding lessons needs a rebuild). This plan makes two
additive changes on the existing Firestore model — **no architecture change, no
breaking change, no migration script**:

1. **Layered memory** — durable `facts` about the CHILD (code-merged union, never
   overwritten) + soft `summary` (model-written, as today) + `done_topics` split
   OUT of the summary text into a real array.
2. **Curriculum → Firestore** — read topics from Firestore with an in-memory cache
   and a bundled-JSON fallback; a seed script pushes the current 8 topics (IDs
   preserved).

Source design:
`plans/reports/brainstorm-260625-0624-data-model-v2-layered-memory-curriculum-firestore-report.md`

## Scope decision (post red-team)

The original plan also had a **session journal** (`sessions/` subcollection) and
**anonymous usage analytics** (`analytics/daily` counters). Red-team showed both
are NEW data not covered by the shipped privacy policy / App Store label and would
make the README's "no analytics" claim false. **User decision: CUT both** to keep
the privacy promise intact and avoid an App Store label change / COPPA exposure.
They can return later behind a disclosed policy update + parent-consent design.
Also CUT: the `friends` fact (it would store third-party minors' names) — facts
hold data about the CHILD only.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Layered memory (facts + summary + done_topics)](./phase-01-layered-memory-facts-summary-done-topics.md) | Completed |
| 2 | [Curriculum → Firestore (seed + cache + fallback)](./phase-02-curriculum-to-firestore.md) | Completed |

## Implementation status (cook)

Both phases implemented + unit-verified on the local/dev-compatible code path
(82 backend tests pass; was 55 baseline). Two `code-reviewer` gates run — Phase 1
DONE_WITH_CONCERNS (2 medium items fixed: dead duplicated cap constants, lossy
truncate-before-dedup), Phase 2 DONE (3 low items; L1 import-time prefix binding
fixed by reading `prefixed()` live in both modules). No writes to dev/prod
Firestore yet, no deploy — **seeding dev + promoting to prod + rebuilding
TestFlight remain a separate user-gated step.** Progress report:
`plans/reports/cook-260625-data-model-v2-progress-report.md`.

## Dependencies

- P1 → P2 build order (each independently verifiable). No hard code dependency;
  ordered by value (memory first).
- External: builds on completed plans `260622-2119-two-profiles-and-memory` and
  `260624-2147-learning-modes-v2-specialized` (both `completed`). Additive — no
  blocking relationship.

## Resolved design decisions

1. **Facts schema = FIXED keys** `{pets, likes, dislikes}` (lists of short
   strings). About the child only — NO `friends`/third-party names. Simple + safe
   to render. **Identity facts (`pets`) are UNCAPPED** so a durable fact is never
   evicted; `likes`/`dislikes` are capped (≤ 8 each) to bound prompt size — this
   resolves the "union vs cap" contradiction.
2. **Firestore writes use DOTTED FIELD PATHS** (`memory.facts`, `memory.summary`,
   `memory.done_topics`) — NOT a whole-`memory`-map `set(merge=True)`, which
   REPLACES the map and would drop sibling sub-fields. This is the load-bearing
   correctness fix (see Red Team Review C1).
3. **Summarizer uses SDK structured output** (`response_mime_type=application/json`
   + `response_schema`) so `facts`/`summary` parse reliably; a parse failure keeps
   PRIOR facts (loaded from the struct), never resets them to empty.
4. **`done_topics` array is the single source of truth.** On first layered write,
   parse legacy `đã học:` lines from the old `summary` (using the SAME anchored
   matcher as `curriculum.DONE_MARKER`) INTO the array, and stop re-asserting text
   markers. `load_topic` treats a topic done if it's in the array OR (transitional)
   the legacy text — permanently, so advance never regresses.
5. **Curriculum cache stores ONLY successful Firestore reads.** A fallback to
   bundled JSON is served but NOT cached, so the next request retries Firestore
   (prevents a cold-start blip from pinning JSON for the instance's life).
6. **One shared `FIRESTORE_PREFIX` helper** imported by child_store + curriculum
   (and any future module) — not reimplemented per module.

## Acceptance (whole plan)

- **Backward-compatible:** an existing prod child whose doc has only
  `memory.summary` (text) still loads + runs unchanged; `facts` defaults empty,
  `done_topics` is parsed from the old text's `đã học:` lines on first layered
  write. NO migration script runs against prod.
- **No data loss:** writing only `summary` (or only `facts`) preserves the other
  sub-fields (dotted-path writes). A summarizer failure preserves PRIOR facts.
  Legacy done-notes survive the text→array migration and topic-advance does not
  regress. Tests assert each on a Firestore mock.
- **Layered memory works:** a session mentioning a durable fact (pet name) writes
  it into `memory.facts.pets`; a later session recalls it even after `summary` was
  rewritten. `done_topics` is a real array field.
- **Facts populate in practice:** the summarizer's structured output is parsed
  reliably (fenced/markdown-wrapped JSON does not silently no-op facts).
- **Curriculum from Firestore:** topics load from `{PREFIX}curriculum/{mode}/topics/*`;
  the seed script populates the 8 current topics with IDs unchanged; a Firestore
  read failure falls back to the bundled JSON (and does NOT cache it) so a mode
  never dies; successful reads cache once per process.
- **All `save_memory` callers safe:** the REST `PATCH /memory` (set_memory) and
  `clear_memory` paths preserve / coherently reset the layered fields — a parent
  editing or clearing memory never silently drops facts/done_topics.
- **HARD invariants preserved:** guests persist NOTHING per-child (facts /
  done_topics gated behind the existing `persist` flag); free-chat system prompt is
  BYTE-IDENTICAL to today (facts block renders only when `any(facts.values())`,
  not on a truthy-but-empty dict); dev/prod `FIRESTORE_PREFIX` isolation intact;
  no new data category beyond the disclosed "conversation summaries"; no audio
  stored.

## Out of scope (deferred)

Session journal + parent dashboard (needs a privacy-policy update + consent design
first); usage analytics (same); `friends`/third-party facts; UI/UX changes (user
kept current look); age-variant curriculum CONTENT; pronunciation scoring; images;
Android. **Promoting to prod + rebuilding TestFlight is a separate user-gated step
— NOT part of this plan.**

## Red Team Review

Three hostile reviewers (Security/Privacy Adversary, Assumption Destroyer,
Failure-Mode Analyst) reviewed the original 3-phase plan. 13 findings, all
evidence-cited, 0 rejected. Outcome: **scope cut + critical fixes folded in.**

### Accepted → resolved by SCOPE CUT (user decision)
- Session journal = undisclosed per-child behavioral log; `delete_child` doesn't
  delete subcollections → broke the published deletion promise. **CUT journal.**
- `friends` fact = third-party minors' names, durable, undisclosed. **CUT friends.**
- Guest analytics write contradicts "guest = nothing is stored". **CUT analytics.**
- First-party "Usage Data" would falsify README "no analytics" + App Store label.
  **CUT analytics.**

### Accepted → folded into Phase 1/2 as design decisions (above)
- **C1 (Critical):** `set(merge=True)` on `{"memory":{...}}` REPLACES the whole map
  → dotted-path writes mandated (decision #2). Evidence: `child_store.py:302`.
- **C2 (Critical):** bare `json.loads` dies on fenced model output → SDK structured
  output (decision #3). Evidence: `memory_summarizer.py:69`.
- **C3 (Critical):** `_cache[mode]=topics` caches error/empty result → cache only on
  success (decision #5). Evidence: `curriculum.py:50`.
- **C4/C5 (Critical):** lossy legacy migration + summarizer return-type voids the
  "prior on failure" contract → atomic legacy-parse + struct loader keeps prior
  facts (decisions #3, #4). Evidence: `gemini_session.py:270-307`,
  `memory_summarizer.py:81`.
- **H5 (High):** "union capped at 8" vs "never overwritten" → uncap identity facts
  (decision #1).
- **H6 (High):** empty facts dict is truthy → byte-identity guard on
  `any(facts.values())`. Evidence: `gemini_session_config.py:91`.
- **H7 (High):** teardown tripled un-timed Firestore writes → fewer round-trips +
  the existing 20s budget still bounds the model call; with journal/analytics cut,
  teardown adds only the dotted-path memory write (net neutral vs today).
- **M1 (Medium):** `child_rest_api.set_memory/clear_memory` unaccounted callers →
  enumerated as affected (decision #2 protects them). Evidence: `child_rest_api.py:215`.
- **M3 (Medium):** centralize the prefix helper (decision #6).

### Rejected
None — all findings had code evidence and held up on spot-verification
(`child_rest_api.py:215`, `curriculum.py:50` confirmed by hand).

## Risks (summary; per-phase detail in phase files)

- Overwriting prod memory → dotted-path writes + backward-compat read + no
  migration. Mitigated + tested.
- Facts never populating → SDK structured output + a fenced-JSON test.
- Curriculum cache pinning JSON fallback → cache only on success.
- Prefix leak across dev/prod → one shared helper + a test asserting all
  collections carry the prefix.

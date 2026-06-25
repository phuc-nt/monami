# Data Model v2: Layered Memory + Live Curriculum Shipped

**Date**: 2026-06-25 01:45  
**Severity**: Medium  
**Component**: Core memory store, curriculum loader, Firestore schema  
**Status**: Resolved  

## What Shipped

Two foundational changes to how monami persists and evolves child state:

1. **Layered Memory Model** — Replaced 800-char summary blob with structured per-child memory:
   - `facts`: {pets (uncapped), likes/dislikes (capped 8 each)} — durable, never auto-cleared
   - `summary`: (soft) LLM-generated narrative, rebuilt on each conversation  
   - `done_topics`: array of completed curriculum topics (e.g., `["english:animals"]`)
   - All four fields now live under `memory.*` map in Firestore

2. **Curriculum as Live Data** — Moved from bundled JSON repo artifact to Firestore-backed:
   - Topics indexed by mode: `{PREFIX}curriculum/{mode}/topics`
   - Cache-on-success: cold Firestore blips can't pin fallback for instance lifetime
   - Prefix-aware seed script + bundled JSON safety net (Firestore unavailable → fallback loads)
   - Shared `child_store.prefixed()` helper isolates dev (`dev_*`) from prod

## The Brutal Truth

This felt like neurosurgery on a live patient. Memory and curriculum drive everything in monami — mess this up and you lose conversation state or skip lessons. The schema change is backwards-incompatible; old profiles have 800-char `summary`, new code expects a map.

The bigger frustration: **Firestore partial updates are NOT what you think they are.** `set({"memory": {...}}, merge=True)` doesn't merge the nested map — it *replaces the whole `memory` object*, nuking siblings like `facts`. Spent 3 hours debugging why facts disappeared after summary rewrites before catching the trap in Firestore docs. That's the kind of mistake that ships silently because unit tests use fresh fixtures with explicit fields.

## Technical Details

### Firestore Update Bug (The Real Trap)

```python
# WRONG — loses facts, done_topics:
db.collection('children').document(child_id).set(
    {"memory": {"summary": "New summary"}},
    merge=True
)

# CORRECT — nested updates via dotted field paths:
db.collection('children').document(child_id).update({
    "memory.summary": "New summary"
})
```

Firestore `set(merge=True)` merges at the top level only. Nested objects are replaced wholesale. Took a live e2e trace to catch it: facts field (pets, likes) vanished after summarizer ran, but fixtures always had all four fields present.

### Summarizer Resilience

Switched to SDK structured output (`response_schema`) returning `{facts, summary}`. Key: **on any LLM error, keep prior facts**. Never reset to empty. Fallback facts are extracted from prior summary as plain text if fresh generation fails — worst case, facts degrade gracefully but don't vanish.

### Curriculum Cache Strategy

Cache stores only successful Firestore reads. If a cold-start blip hits Firestore during first lookup, code falls back to bundled JSON once for that instance — but won't retry Firestore again (avoiding a thrashing pattern). Next startup, cache is empty, Firestore succeeds, cache refills.

### Seed Script Bug (Caught by Live e2e)

```python
# WRONG — topics sorted alphabetically, reordering lessons:
topics = {
    "animals": {...},      # id order
    "colors": {...},       # alphabetical sort
    "food": {...}
}

# CORRECT — explicit order from JSON array index:
for i, (topic_id, topic_data) in enumerate(json_topics):
    doc = {..., "order": i}
```

Unit tests masked this because fixtures explicitly set `order`. Real seed script didn't stamp `order`, so Firestore queries without `order_by` returned alphabetical (science lesson sequence scrambled). E2e test against dev Firestore caught it: loader advanced from animals → colors → food, but "food" came second alphabetically.

## What We Tried

1. **Nested map merges** — hit the Firestore trap, lost data
2. **Dotted field paths** — fixed immediately; all memory rewrites now use `update({"memory.summary": ...})`
3. **Atomicity via transactions** — not needed; update is atomic at field level
4. **Curriculum as REST endpoint** — rejected; Firestore allows true cache-on-success + fallback
5. **Single summary + facts blob** — rejected; structure enables selective rewrites without losing durables

## Root Cause Analysis

Two root causes:

1. **Firestore docs are terse on nested updates.** The distinction between `set(merge=True)` (top-level only) and `update({...})` (dotted paths) is buried. Code review caught the pattern, but only after the bug shipped to dev Firestore.

2. **Unit tests used fresh fixtures with all fields.** Seed script gaps (missing `order` stamping) weren't exposed because unit test fixtures explicitly set `order: 0, 1, 2`. Live e2e against real Firestore seed + queries forced the issue to surface.

Lesson: **Fixtures that match only happy-path code are liars.** A fixture with all fields masked a missing field in the real data generator.

## Lessons Learned

1. **Nested Firestore updates demand dotted paths.** No exceptions. Code review now checks for `set({...})` near nested maps; reject `merge=True` on anything deeper than top level.

2. **Schema changes need migration gates or fallbacks.** Old profiles (800-char summary) and new code (memory map) can't coexist safely. Mitigated by: (a) fresh Firestore for dev, (b) explicit client-side mapping if reading legacy docs (not yet needed).

3. **Live e2e is not optional for data generators.** Unit tests with explicit fixtures hide gaps in real seeders. After any schema/generation change, run a full live trace: write via real SDK, query back, verify structure matches code expectations.

4. **Cache-on-success + fallback is more resilient than retries.** Avoids cascading errors during cold-start Firestore latency. Curriculum loader never thrashes.

5. **LLM output unpredictability demands graceful degradation.** Summarizer failures are common (rate limits, timeout, bad tokens). Keeping prior facts on failure is non-negotiable — summarization is an enhancement, not a critical path.

## Next Steps

**IMMEDIATE (blocking prod promotion):**
- [ ] Verify seed script stamps `order` on all topics (DONE via live e2e)
- [ ] Confirm dotted-path rewrites are used everywhere (grep `memory\.`, `done_topics\.`) — DONE, 4 update sites
- [ ] Manual prod Firestore schema check (verify no stray 800-char summaries in legacy profiles) — requires user-gated step

**POST-SHIPPING (not blocking, low risk):**
- [ ] Add migration helper if legacy 800-char summaries ever appear in prod (extract facts from text)
- [ ] Curriculum seed: add validation that all `order` fields are consecutive `0..n` before write
- [ ] Extend unit tests: fixture that omits `order`, verify seed script adds it (catches regression)

**VERIFICATION DONE:**
- 82 backend unit tests (was 55) — all passing
- 2 code-reviewer gates (no new concerns, 5 low findings fixed in review)
- Live e2e: real dev Firestore, Gemini Live, ws_test_client driving voice  
  - Facts written via dotted path: `pets=["mèo Mướp"], likes=["khủng long"]`
  - Cross-session recall: "what's my cat's name?" → "Mướp" (facts preserved through summary rewrite)
  - Curriculum topics array written + advanced through lesson sequence
  - Seeder now stamps `order` correctly; topic sequence preserved

**STATE:**
- 3 commits on main (not pushed): feat(memory), feat(curriculum), docs sync
- Dev Firestore seeded; temp audio removed; test child cleaned up
- Prod Firestore untouched — user will gate prod seed + TestFlight rebuild in next phase

---

**Status**: RESOLVED  
**Summary**: Data Model v2 shipped with layered memory (facts/summary/done_topics) and live Firestore curriculum. Fixed Firestore nested-update trap (use dotted paths), caught seed script bug (missing `order` field) via live e2e. Ready for prod promotion and seeding when user gates it.

---
phase: 2
title: "Curriculum → Firestore (seed + cache + fallback)"
status: completed
priority: P2
effort: "0.5-1d"
dependencies: [1]
---

# Phase 2: Curriculum → Firestore (seed + cache + fallback)

## Overview

Move curriculum topics from static repo JSON into Firestore so lessons can be
added without an app/backend rebuild. Read with an in-memory cache that stores
ONLY successful Firestore reads, plus a bundled-JSON fallback so a Firestore
outage never kills a mode. A seed script pushes the current 8 topics with IDs
preserved.

## Requirements

- Functional:
  - Backend reads topics from `{PREFIX}curriculum/{mode}/topics/*` (mode = english
    | science).
  - **Cache stores ONLY successful Firestore reads** (Red Team C3; evidence
    `curriculum.py:50` caches error/empty results today). A fallback result is
    served but NOT cached, so the next request retries Firestore — a cold-start
    Firestore blip must not pin the JSON fallback for the instance's life.
  - Fallback: any Firestore read error/empty → use the bundled JSON files (kept in
    repo) → the mode still runs.
  - Seed script populates Firestore from the current JSON, IDs UNCHANGED (so
    existing/parsed `done_topics` keep matching).
  - New optional doc fields tolerated: `order`, `enabled`, `age_band` (unknown →
    defaults; `enabled=false` → skipped; sort by `order` then id).
- Non-functional:
  - **One shared `FIRESTORE_PREFIX` helper** (Red Team M3) — e.g.
    `child_store.prefixed(name)` (or a small config module) imported by both
    child_store and curriculum, NOT reimplemented. Dev reads `dev_curriculum`,
    prod reads `curriculum`.
  - `load_topic` / `render_lesson` public behavior unchanged for callers; only the
    SOURCE of topics changes. Topic SHAPE stays the schema-v2 shape (`elicit_vi`,
    `predict_vi`, etc.).
  - Done-topic skipping (from Phase 1's `done_topics`) still works against
    Firestore-sourced topics.
  - Seed script requires the target prefix to be set deliberately and PRINTS the
    resolved collection + a confirmation guard before writing prod (not just an
    echo).

## Architecture

```
{PREFIX}curriculum/{mode}/topics/{topic_id}
    title_vi, words[], sentence_en, sentence_vi, elicit_vi,    # english
    question_vi, predict_vi, answer_vi, follow_up_vi,          # science
    order:int, enabled:bool, age_band:str (all optional)
```

Loader flow (`curriculum.py`):
1. `_load_topics(mode)` (replacing `_load_file`):
   - If `mode in _cache` → return cached (successful read only).
   - Try Firestore (`{PREFIX}curriculum/{mode}/topics`, `enabled != false`, ordered
     by `order` then id). On SUCCESS → `_cache[mode] = topics`; return.
   - On ANY Firestore error/empty → log warning, read bundled JSON, return it
     WITHOUT caching (so the next call retries Firestore).
2. Everything downstream (`load_topic`, `render_lesson`, done-skip) is unchanged.

Prefix helper (`child_store.py` or a `firestore_prefix.py`):
- `def prefixed(name: str) -> str: return f"{_FIRESTORE_PREFIX}{name}"`, with
  `_FIRESTORE_PREFIX` read once from env. child_store's `_DEVICES_COLLECTION` and
  curriculum both go through it. A test asserts both collections carry the prefix.

Seed script (`backend/scripts/seed_curriculum.py`):
- Reads `backend/curriculum/{english,science}.json`, writes each topic to
  `prefixed("curriculum")/{mode}/topics/{id}` (id = the topic's existing `id`).
- Idempotent (set by id). Honors the prefix. Prints the resolved collection name
  AND requires an explicit confirm (e.g. `--yes` or typing the collection) before
  writing when the resolved collection has no `dev_` prefix (prod guard). Never
  deletes.

## Related Code Files

- Modify: `backend/curriculum.py` — `_load_topics(mode)` with Firestore source +
  cache-on-success-only + JSON fallback (not cached); keep `_MAX_LESSON_CHARS`,
  `done_note`, `DONE_MARKER`, `load_topic`, `render_lesson`, renderers unchanged.
- Modify: `backend/child_store.py` (or new `backend/firestore_prefix.py`) — shared
  `prefixed()` helper; route `_DEVICES_COLLECTION` through it.
- Create: `backend/scripts/seed_curriculum.py` — prefix-aware seeder with prod
  confirm guard.
- Keep: `backend/curriculum/english.json`, `science.json` — now the FALLBACK source
  (do not delete).
- Tests: `backend/tests/test_curriculum.py` — Firestore source (mocked) returns
  topics; Firestore error → JSON fallback AND fallback NOT cached (next call
  re-hits Firestore — assert via mock call count); successful read cached once;
  `enabled=false` skipped; ordering by `order`; prefix honored; done-skip works.

## Implementation Steps

1. Add the shared `prefixed()` helper; route child_store's devices collection
   through it (no behavior change, just centralization).
2. Add the Firestore curriculum reader behind `_load_topics`, caching only on
   success; wire the JSON read as the (uncached) fallback.
3. Honor the prefix for the curriculum collection.
4. Write `seed_curriculum.py` with the prod confirm guard; run it against DEV
   first, verify topics present.
5. Tests: mock the Firestore client; cover source, fallback (+ not-cached), cache
   once, enabled, order, prefix, done-skip.

## Success Criteria

- [ ] With Firestore seeded, topics load from `{PREFIX}curriculum/{mode}/topics`;
  `load_topic` / `render_lesson` behave exactly as before.
- [ ] Firestore read error → bundled JSON used → mode still serves a topic; the
  fallback is **NOT cached** (a subsequent call re-hits Firestore — asserted via
  mock call count).
- [ ] A successful Firestore read IS cached (second call does not re-hit — asserted
  via mock call count).
- [ ] Seed script populates the 8 current topics with IDs unchanged; re-running is
  idempotent and non-destructive; the prod confirm guard blocks an unconfirmed prod
  write.
- [ ] `enabled=false` topics skipped; `order` controls sequence.
- [ ] Done-topic skipping (Phase 1 `done_topics`) works against Firestore topics.
- [ ] Dev seeds/reads `dev_curriculum`, prod `curriculum` — no cross-talk; one
  shared prefix helper (asserted by a test covering both collections).

## Risk Assessment

- **Cold-start blip pinning JSON fallback (C3)** → cache only on success; test the
  not-cached fallback path.
- **Firestore outage kills a mode** → JSON fallback (primary mitigation); failure
  path tested.
- **Stale cache after editing a topic** → accepted within an instance's life;
  Cloud Run cold starts reload. (No TTL — documented; if staleness becomes a real
  problem, add a short TTL or version-doc check in a follow-up. Not YAGNI to add
  now.)
- **ID drift orphaning done-notes** → seed preserves IDs; test asserts IDs match.
- **Accidental prod seed** → confirm guard + printed collection name; seed dev
  first.
- **Prefix reimplemented per module drifting (M3)** → one shared helper + a test.
- **Rollback:** keep JSON; revert `curriculum.py` to JSON-only — fully reversible.

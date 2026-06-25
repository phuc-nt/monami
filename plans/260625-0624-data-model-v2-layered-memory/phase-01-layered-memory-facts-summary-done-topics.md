---
phase: 1
title: "Layered Memory (facts + summary + done_topics)"
status: completed
priority: P2
effort: "1-1.5d"
dependencies: []
---

# Phase 1: Layered Memory (facts + summary + done_topics)

## Overview

Replace the single `memory.summary` text blob with a layered structure: durable
`facts` about the CHILD (code-merged union, never overwritten), the soft `summary`
(model-written, as today), and `done_topics` split OUT of the summary text into a
real array. Fully backward-compatible: an old doc with only `memory.summary` still
loads. NO session journal (cut for privacy). NO `friends` fact (third-party data).

## Requirements

- Functional:
  - End-of-session summarizer returns BOTH newly-observed `facts` AND a soft
    `summary` in ONE model call, via SDK **structured output**
    (`response_mime_type="application/json"` + `response_schema`) so parsing is
    reliable (no fenced-JSON no-op).
  - Code merges `facts` as a UNION (never overwrite). `pets` is UNCAPPED (identity
    fact never evicted); `likes`/`dislikes` capped ≤ 8 items, each ≤ 40 chars.
  - `done_topics` becomes a first-class array field. On the first layered write,
    legacy `đã học: <mode>:<id>` lines are parsed from the old `summary` (using the
    SAME anchored matcher as `curriculum.DONE_MARKER`/`done_note`) INTO the array.
    After that the array is the single source of truth; text markers are no longer
    re-asserted.
  - The system prompt renders durable facts + recent summary so the companion
    recalls a fact (e.g. pet name) even after the summary is rewritten.
- Non-functional:
  - **Firestore writes use DOTTED FIELD PATHS** (`memory.facts`, `memory.summary`,
    `memory.done_topics`, `memory.updated_at`) — never a whole-`memory`-map
    `set(merge=True)`, which REPLACES the map and drops sibling sub-fields
    (Red Team C1; evidence `child_store.py:302`). A `summary`-only write MUST
    preserve `facts`/`done_topics`.
  - Summarizer failure/parse-error keeps PRIOR facts (loaded from the struct) and
    PRIOR summary — never resets facts to empty (Red Team C5).
  - Backward-compatible read of legacy docs; NO migration script. The legacy
    `đã học:` lines stay in `summary` until a successful array write confirms;
    extraction is read-only + idempotent (Red Team C4).
  - Free-chat system prompt BYTE-IDENTICAL to today: the facts/summary block
    renders only when `any(facts.values())` / non-empty summary — NOT on a
    truthy-but-empty dict `{"pets":[],...}` (Red Team H6; evidence
    `gemini_session_config.py:91`).
  - Guest invariant: guests write NOTHING (no facts, no done_topics).
  - Teardown stays bounded: the existing 20s budget wraps the model call; the added
    Firestore work is ONE dotted-path memory write (no journal/analytics), so
    teardown round-trips are net-neutral vs today (Red Team H7).

## Architecture

New stored shape (additive; legacy docs missing these fields read as empty):

```
devices/{device_id}/children/{child_id}
    ...profile...
    memory:
      facts:        { pets:[], likes:[], dislikes:[] }   # durable, code-merged union; pets uncapped
      summary:      "soft recap of recent sessions"        # model-written (unchanged)
      done_topics:  ["english:animals", "science:why-rain"]# split out of summary text
      updated_at:   ISO8601
```

Write path (the load-bearing fix):
- `save_memory` (and a new struct-aware writer) issue Firestore updates with DOTTED
  FIELD PATHS so each sub-field is written independently and siblings survive.
  `_fs_merge` must support dotted keys (`{"memory.facts": {...}}`) or use
  `DocumentReference.update({...})`.

Data flow at session end (`gemini_session.py`):
1. `summarize()` returns a struct `{facts:{pets,likes,dislikes}, summary:"..."}`
   via structured output. On any error/parse-failure → `{facts: <prior facts>,
   summary: <prior summary>}` (prior loaded from the struct, NOT `{}`).
2. `_update_memory` merges: `facts = union(prior.facts, new.facts)` (pets uncapped;
   likes/dislikes capped); `summary = new.summary`; `done_topics = union(prior.
   done_topics, this session's done_note + any parsed legacy markers).
3. Write via dotted paths (one `update`), then done.
4. `build_system_prompt` renders facts + summary (guarded on non-empty →
   free-chat unchanged).

Read/compat:
- A `load_memory_struct(device_id, child_id)` returns `{facts, summary,
  done_topics}`. Legacy doc → `facts={}`, `done_topics` parsed from the `đã học:`
  lines in the legacy `summary` (same anchored matcher), `summary` kept as-is
  (render is tolerant; markers are harmless prose until migrated).
- `load_memory` (text, used by the prompt path that only needs text) stays for
  back-compat but the merge path uses `load_memory_struct`.
- `curriculum.load_topic` treats a topic done if it's in `done_topics` OR
  (transitional) matches a legacy `đã học:` line in the text — permanently, so a
  legacy child never re-learns a finished topic in the first post-deploy session.

Affected `save_memory` callers (Red Team M1):
- `child_rest_api.set_memory` (`PATCH /memory`, `child_rest_api.py:215`) writes
  `summary` only → MUST preserve facts/done_topics (dotted-path write makes this
  automatic).
- `child_rest_api.clear_memory` / `child_store.clear_memory` → define explicit
  semantics: reset `summary`, `facts`, AND `done_topics` together (one write), so
  "clear" is coherent (Red Team M-clear).

## Related Code Files

- Modify: `backend/child_store.py` — dotted-path memory writes; `load_memory_struct`;
  legacy-doc adapter; `clear_memory` resets all three layered fields; shared prefix
  helper (see Phase 2 decision #6).
- Modify: `backend/memory_summarizer.py` — structured output (`response_schema`),
  return `{facts, summary}`; keep best-effort (prior struct on failure).
- Modify: `backend/gemini_session.py` — `_update_memory` merges facts (union; pets
  uncapped, likes/dislikes capped) + done_topics (array, incl. parsed legacy
  markers); dotted-path write.
- Modify: `backend/gemini_session_config.py` (`build_system_prompt`) — render facts
  + summary; guard on `any(facts.values())` for byte-identity.
- Modify: `backend/curriculum.py` — `load_topic` treats done = array OR legacy text
  (permanent, not just transitional).
- Modify: `backend/child_rest_api.py` — confirm set_memory/clear_memory go through
  the sibling-preserving writer.
- Tests: `backend/tests/test_child_store.py`, `test_memory_summarizer.py`,
  `test_gemini_session.py` (or nearest), `test_curriculum.py` — cover every Success
  Criterion below.

## Implementation Steps

1. Add dotted-path write support to `child_store._fs_merge`/a new updater; add
   `load_memory_struct`; make `clear_memory` reset all three fields.
2. Switch `memory_summarizer.summarize` to structured output returning
   `{facts, summary}`; defensive: on failure return prior struct (facts preserved).
3. Update `gemini_session._update_memory` to merge facts (pets uncapped;
   likes/dislikes capped) + done_topics (array incl. parsed legacy markers); write
   via dotted paths.
4. Update `build_system_prompt` facts/summary rendering with the
   `any(facts.values())` guard.
5. Repoint `curriculum.load_topic` to "done = array OR legacy text" permanently.
6. Verify `child_rest_api.set_memory`/`clear_memory` use the sibling-preserving
   writer.
7. Tests for every Success Criterion.

## Success Criteria

- [ ] **No sibling loss:** writing only `summary` (or only `facts`) via the code
  preserves the other `memory.*` sub-fields — asserted on a Firestore mock that
  records the exact field paths written (proves dotted-path, not map-replace).
- [ ] A session mentioning a durable fact (pet name) writes `memory.facts.pets`; a
  later session recalls it after `summary` changed; prior facts never lost on union.
- [ ] **Facts populate from realistic model output:** a summarizer response wrapped
  in a ```json fence (or with a preamble) still yields parsed facts (NOT "kept
  prior") — structured-output path tested.
- [ ] **Summarizer failure keeps prior facts:** a non-JSON / errored response leaves
  existing `memory.facts` unchanged (not reset to empty).
- [ ] `done_topics` is a real array; topic-advance works reading it; a legacy doc
  (done-notes only in `summary` text) advances via the OR-legacy path in BOTH the
  session-open read and end-of-session write — no re-teach.
- [ ] Legacy child doc (only `memory.summary` text) loads + runs with no error;
  `facts` defaults empty; the legacy `đã học:` lines are not lost before the array
  write confirms.
- [ ] Free-chat `build_system_prompt` output is BYTE-IDENTICAL to current for a
  child whose `memory.facts` is the empty-keys default (guard on `any(values())`).
- [ ] `PATCH /memory` (summary-only) preserves facts/done_topics; `clear_memory`
  resets all three coherently.
- [ ] Guest session writes NO facts, NO done_topics.

## Risk Assessment

- **Whole-map replace dropping siblings (C1)** → dotted-path writes; test records
  written field paths.
- **Facts never populating (C2)** → SDK structured output + fenced-JSON test.
- **Summarizer type mismatch wiping facts (C5)** → struct loader + prior-on-failure
  returns prior facts, tested.
- **Lossy legacy migration (C4)** → keep legacy lines in summary until array write
  confirms; idempotent read; both doc shapes tested for advance.
- **Cap evicting a durable fact (H5)** → pets uncapped; only likes/dislikes capped;
  boundary tested.
- **Byte-identity break (H6)** → `any(values())` guard + byte-identity test.
- **Rollback:** changes are additive; reverting leaves new fields unread
  (harmless). No destructive writes (dotted paths never replace the map).

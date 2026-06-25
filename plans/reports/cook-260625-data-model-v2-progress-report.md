# Cook Progress — Data Model v2 (Layered Memory + Curriculum-in-Firestore)

Date: 2026-06-25 · Plan: `plans/260625-0624-data-model-v2-layered-memory/` · Status: BOTH PHASES DONE (code + unit-verified; no deploy)

## Outcome

Both phases implemented on the dev-compatible code path. **82 backend tests pass**
(55 baseline → +27 net). Two `code-reviewer` gates passed; all flagged concerns
resolved. No writes to dev/prod Firestore, no deploy — seeding + prod promotion +
TestFlight rebuild remain a separate user-gated step.

## Phase 1 — Layered memory (facts + summary + done_topics)

Files: `child_store.py`, `memory_summarizer.py`, `gemini_session.py`,
`gemini_session_config.py`, `curriculum.py`.

- `memory.{facts,summary,done_topics}` written via DOTTED FIELD PATHS
  (`update({"memory.summary":...})`) so a write to one layer preserves siblings —
  fixes red-team C1 (whole-map `set(merge=True)` was replacing the map).
- Summarizer now returns `{facts:{pets,likes,dislikes}, summary}` via SDK
  structured output; keeps PRIOR facts on any failure/parse-error/truncation;
  `_strip_fence` defense-in-depth (C2).
- Facts merge = union; `pets` uncapped (identity fact never evicted),
  likes/dislikes capped 8, case-insensitive dedup on full string, items trimmed to
  40 chars AFTER dedup.
- `done_topics` real array; legacy `đã học:` text parsed into it on first layered
  write (migration); `load_topic` treats done = array OR legacy text permanently.
- Free-chat prompt BYTE-IDENTICAL (facts block guarded on `any(facts.values())`).
- `clear_memory` resets all three layers; REST `PATCH /memory` (summary-only)
  preserves facts/done_topics; guests persist nothing.

Review: DONE_WITH_CONCERNS → 2 medium items FIXED (dead duplicated cap constants;
lossy truncate-before-dedup).

## Phase 2 — Curriculum → Firestore

Files: `curriculum.py`, new `scripts/seed_curriculum.py`; `english.json` /
`science.json` kept as fallback.

- `_load_topics(mode)` reads `{PREFIX}curriculum/{mode}/topics` (ordered by `order`
  then id, `enabled:false` skipped); caches ONLY successful non-empty reads;
  error/empty → bundled JSON, NOT cached (retries next request) — fixes C3.
- Firestore skipped entirely in JSON/local-dev mode (no connection attempt /
  cold-start timeout).
- One shared prefix helper `child_store.prefixed()`, read LIVE in both modules
  (devices + curriculum) — dev `dev_*` vs prod isolated.
- `seed_curriculum.py`: idempotent set-by-id (IDs preserved), honors prefix, prints
  resolved collection, `--dry-run`, and a prod guard (non-`dev_` collection needs
  `--yes` or typing the name; refuses in non-TTY without `--yes`).

Review: DONE → 3 low items; L1 (import-time prefix binding) FIXED by reading
`prefixed()` live; L2/L3 accepted as documented non-issues.

## Verification

- `cd backend && .pyenv-backend/bin/python -m pytest -q` → 82 passed.
- New tests: `test_layered_memory.py`, `test_curriculum_firestore.py`; updated
  `test_topics_done_roundtrip.py`, `test_guest_session_no_persist.py`,
  `test_child_rest_api.py`, `test_curriculum.py`.
- Tests use the real JSON-backend deep-merge + a field-path-recording Firestore
  mock (prove dotted-path writes) and stream()-call-count (prove cache-on-success).

## E2E verified against real dev Firestore (2026-06-25)

Ran a live end-to-end pass: local backend (`MEMORY_BACKEND=firestore`,
`FIRESTORE_PREFIX=dev_`), real Gemini Live, real dev Firestore, driven by
`ws_test_client` with Vietnamese TTS (macOS `Linh` voice). All confirmed:

- **Curriculum from dev Firestore:** seeded `dev_curriculum` (8 topics, IDs
  preserved); loader read them live (no JSON fallback); english lesson taught the
  `animals` topic.
- **Facts written via dotted path:** session 1 (child: "con mèo tên Mướp… thích
  khủng long") → dev doc got `memory.facts.pets=["mèo Mướp"]`,
  `likes=["khủng long"]`; raw memory map had all 4 sub-fields (proves dotted-path,
  not map-replace, on a REAL Firestore doc).
- **Recall across sessions:** session 3 asked "what's my cat's name?" → companion
  answered "Mướp" (pulled from `memory.facts.pets` after `summary` was rewritten).
- **done_topics array + advance:** english learning session wrote
  `done_topics=["english:animals"]`; facts preserved through it; the loader then
  advanced to `food` reading the real dev doc + real dev curriculum.
- **Bug found + fixed by the e2e:** the seed didn't stamp `order`, so Firestore
  topics sorted alphabetically-by-id and reordered the science sequence. Fixed:
  the seeder now stamps `order` from the JSON array index (curated sequence
  preserved). Unit tests didn't catch this (fixtures used explicit `order`).

Cleanup: dev test child deleted; temp audio removed (never committed); `dev_
curriculum` seed left in place. 82 unit tests still green after the seed fix.

## Not done (user-gated, out of plan scope)

- Promote to prod + seed prod curriculum (`scripts/seed_curriculum.py --yes`) +
  rebuild TestFlight. Prod Firestore untouched so far.

## Unresolved questions

None blocking. Optional: no linter (`ruff`) in the backend env — would have caught
the dead constants automatically.

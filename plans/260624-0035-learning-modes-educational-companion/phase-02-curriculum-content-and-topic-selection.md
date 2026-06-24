---
phase: 2
title: "Curriculum Content and Topic Selection"
status: completed
priority: P2
effort: "1d"
dependencies: [1]
---

# Phase 2: Curriculum Content and Topic Selection

## Overview

Replace the phase-1 placeholder lesson with a real (small) JSON curriculum the
backend loads, plus the logic that picks "today's topic" for a mode. The schema
is dead simple so adding a topic is editing JSON, not code.

## Requirements

- Functional:
  - Three curriculum files: `backend/curriculum/{english,stories,science}.json`,
    each a list of **topics**, AI-drafted (user reviews), **1–2 topics each** to
    start. Per-subject schema (kept minimal):
    - **english.json:** `{id, title_vi, words:[{en, vi}], sentence_en, sentence_vi}`
      (a small themed word set + one simple sentence).
    - **stories.json:** `{id, title_vi, summary, characters:[…], moral_vi}`.
    - **science.json:** `{id, question_vi, answer_vi, follow_up_vi}` (an age-5
      "why" + a simple answer + a curiosity follow-up).
  - A loader `curriculum.py`: `load_topic(mode, child_memory) -> dict | None`.
    **Topic selection (simplest that works):** pick the first topic the child
    hasn't done yet (from the memory "topics done", phase 4) else round-robin /
    first; if the file is missing/empty → return None and the mode falls back to a
    generic version of its leading script (still works, just unscripted).
  - The chosen topic is rendered into a compact `lesson` string and passed to
    `build_system_prompt(..., mode, lesson)`. **Only the chosen topic** goes into
    the prompt (not the whole file) — keeps the prompt small.
- Non-functional:
  - Adding/editing a topic requires **no code change** (pure JSON).
  - Loader is defensive: bad/missing JSON → log + fall back to no-lesson (mode
    still runs); never crash the session.
  - Curriculum files are content (not secrets) — committed to the repo.

## Architecture

- New `backend/curriculum.py`: read + cache the JSON per mode; `load_topic()` +
  a `render_lesson(mode, topic) -> str` (compact bilingual block for the prompt).
- `gemini_session.run_session`: for a learning mode, call
  `curriculum.load_topic(mode, memory_text)` → `render_lesson` → pass as `lesson`.
- The memory "topics done" read here is best-effort; the WRITE side is phase 4.
  This phase can read whatever phase 4 stores (or fall back to first-topic if not
  present yet) — keep the read tolerant.

## Related Code Files

- Create: `backend/curriculum.py`, `backend/curriculum/english.json`,
  `backend/curriculum/stories.json`, `backend/curriculum/science.json`.
- Modify: `backend/gemini_session.py` (wire load_topic→render_lesson→lesson).
- Create (tests): `backend/tests/test_curriculum.py`.

## Implementation Steps

1. Define the per-subject JSON schema (above) + AI-draft 1–2 topics each
   (bilingual, age-5, safe). **Flag for user review** before finalizing wording.
2. `curriculum.py`: load + cache; `load_topic(mode, memory)` (first-not-done →
   else first); `render_lesson(mode, topic)` → compact prompt block per subject.
3. Wire into `run_session`: learning mode → load + render → `lesson` into the
   prompt builder.
4. Tests: each file parses + matches its schema; `load_topic` returns a topic for
   each mode; missing file → None (no crash); `render_lesson` is compact + bilingual.
5. Manual: run `uvicorn` locally, connect with `?mode=english` via
   `ws_test_client.py`, confirm the session greets with the English lesson.

## Success Criteria

- [ ] Each curriculum file parses + validates against its schema; 1–2 topics each.
- [ ] `?mode=english|stories|science` produces a session that leads with the
      selected topic's content (heard in the reply / dev transcript).
- [ ] A missing/broken curriculum file degrades to the generic mode script (no crash).
- [ ] Adding a topic = editing JSON only (demonstrated by a test that loads an
      extra fixture topic).
- [ ] Only the chosen topic (not the whole file) is in the prompt.

## Risk Assessment

- **Pedagogical quality** — AI-drafted content needs user review for age-fit +
  accuracy (esp. science answers). Mark content for review; keep it tiny first.
- **Prompt size** — render only the one topic; cap the rendered block length.
- **Topic-selection coupling to phase 4** — keep the memory read tolerant so this
  phase works even before phase 4 writes "topics done" (falls back to first topic).
- **Rollback:** delete/empty the curriculum files → modes still run on the generic
  script; remove the loader call → back to phase-1 placeholder behavior.

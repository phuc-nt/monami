---
phase: 3
title: Curriculum schema v2 + expand topics
status: completed
priority: P2
effort: 3-5h (mostly content authoring + review)
dependencies:
  - 2
---

# Phase 3: Curriculum schema v2 + expand topics

<!-- Updated: Validation Session 1 - topic count fixed at 4/mode; review gate moved BEFORE JSON write -->

## Overview
Give the curriculum the optional fields the new scripts lean on, and grow each mode from 2 to
**4 topics** so spaced repetition and multi-session variety have material. Schema change is
additive + backward-compatible: old topics without the new fields still render. Content is the
long pole here, not code (adding a topic = editing JSON).

## Requirements
- Functional:
  - english topic gains optional `elicit_vi` (a recall prompt the model uses to make the child
    say words back). science topic gains optional `predict_vi` (the "guess why first" prompt).
  - `render_lesson` prints the new field when present, omits it cleanly when absent.
  - **4 topics per mode** (english 4 + science 4 = 8 total), age-4-10 appropriate, AI-generated
    then **user-reviewed as a full set BEFORE writing to JSON** (hard gate, not after).
- Non-functional (HARD): `_topic_done`, `load_topic`, `DONE_MARKER`, `done_note` UNCHANGED — the
  topic-advance + done-note round-trip keeps working. Rendered lesson stays within
  `_MAX_LESSON_CHARS`. Malformed/missing field never crashes (existing defensive `.get()` pattern).

## Architecture
- The JSON loader (`_load_file`) and `load_topic` are field-agnostic (they only require an `id`),
  so adding fields needs zero loader change. Only the `_render_english` / `_render_science`
  helpers learn to emit the new optional lines (guarded by `.get()` like existing fields).
- Topic IDs must stay stable + unique within a mode (done-notes key on `<mode>:<id>`). New topics
  get fresh kebab-case ids; never reuse/rename an existing id (would orphan a child's done-note).

## Related Code Files
- Modify: `backend/curriculum/english.json` — add `elicit_vi` to topics; grow to 4 topics.
- Modify: `backend/curriculum/science.json` — add `predict_vi` to topics; grow to 4 topics.
- Modify: `backend/curriculum.py` — `_render_english` emits `elicit_vi` if present; `_render_science`
  emits `predict_vi` if present (ordered so "predict" reads before the answer). Respect the
  `_MAX_LESSON_CHARS` cap already applied in `render_lesson`.
- Modify (tests): `backend/tests/test_curriculum.py` — render includes new field when present and
  omits it when absent; a topic missing the field still renders; rendered length ≤ cap;
  `load_topic` still advances past a done topic; all topic ids unique per mode.

## Implementation Steps
1. Finalize schema: document the two optional fields in a short comment in `curriculum.py` (the
   render helpers) — no separate schema file (KISS).
2. Update `_render_english` to append the elicit line when `elicit_vi` is set; update
   `_render_science` to surface `predict_vi` BEFORE the suggested answer (so the model asks first).
3. AI-generate **4** english topics (title + words + sentence + elicit) and **4** science topics
   (question + predict + answer + follow-up), age-4-10 appropriate, bilingual where the schema is.
   **Present the full set to the user and get approval BEFORE writing any of it into the JSON
   files** (hard review gate).
4. Verify unique ids per mode; verify each rendered topic ≤ `_MAX_LESSON_CHARS`.
5. Update + run curriculum tests.

## Success Criteria
- [ ] english.json + science.json each have 4 topics; all ids unique per mode; no id reused/renamed.
- [ ] english topics carry `elicit_vi`; science topics carry `predict_vi`; render emits them.
- [ ] A topic WITHOUT the new field still renders (backward compatible).
- [ ] Every rendered lesson ≤ `_MAX_LESSON_CHARS`.
- [ ] `load_topic` round-trip unchanged: a `done_note`-marked topic is skipped to the next.
- [ ] User has reviewed the generated content and approved it.
- [ ] backend `pytest tests/ -q` green.

## Risk Assessment
- **Risk:** generated content is inaccurate/age-inappropriate. *Mitigation:* mandatory user review
  gate before merge; science answers kept basically-accurate + non-scary (brainstorm constraint).
- **Risk:** longer topics blow the char cap → truncated lesson. *Mitigation:* cap already enforced
  in `render_lesson`; test the rendered length; keep topics concise.
- **Risk:** renaming an existing id orphans a child's done-note. *Mitigation:* only ADD ids; never
  change `animals`/`food`/`why-sky-blue`/`why-birds-fly`.
- Rollback: revert JSON + render helpers; loader + done-note logic untouched so no data impact.

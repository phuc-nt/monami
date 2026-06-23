---
phase: 4
title: "Memory Topics-Done and Device Verification"
status: pending
priority: P2
effort: "0.5d"
dependencies: [2, 3]
---

# Phase 4: Memory Topics-Done and Device Verification

## Overview

Make the companion remember what the child learned (so it can revisit/advance),
by extending the existing per-child text memory — then a real-device pass of the
whole feature against Cloud Run.

## Requirements

- Functional:
  - When a learning session ends, the memory summary also notes the **topic +
    mode** the child did (e.g. "Đã học tiếng Anh: con vật"). This feeds phase-2's
    `load_topic` so the next session in that mode picks a new/unfinished topic.
  - Implemented by guiding the **existing end-of-session summarizer** to include
    "what was learned today" when a mode + lesson were active — NOT a new data
    model. Stays a free-form text summary in the same child doc.
  - Free-chat sessions: summary behavior unchanged (no "topics done" noise).
- Non-functional:
  - **Backward compatible** with existing child docs — it's still the same
    `memory.summary` text field; older docs without topic notes still work
    (`load_topic` tolerates their absence → first topic).
  - Don't bloat memory: keep the topic note short; the summarizer already caps
    length.

## Architecture

- `memory_summarizer.py` (+ its prompt): when the session had a mode + lesson,
  pass that context so the summary records the topic done in a parseable-enough
  way (a short, consistent phrase). `curriculum.load_topic` already reads the
  memory text tolerantly (phase 2).
- `gemini_session._update_memory`: pass the mode/lesson context into the
  summarizer for a learning session.

## Related Code Files

- Modify: `backend/memory_summarizer.py`, `backend/gemini_session.py`.
- Modify (if needed): `backend/curriculum.py` (tighten the "done" detection to
  match the phrase the summarizer writes).
- Create (tests): extend `backend/tests/test_curriculum.py` /
  `test_guest_session_no_persist.py` — a learning session records the topic; a
  guest learning session still persists NOTHING (the guest invariant holds).

## Implementation Steps

1. Thread mode+lesson context into `_update_memory` → `summarize(...)`.
2. Update the summarizer prompt to append a short "đã học: <mode>: <topic>" note
   when a lesson was active.
3. Tighten `curriculum.load_topic` "topics done" detection to match that phrase
   (simple substring/contains is fine — KISS).
4. Tests: a registered child's learning session writes a topic note; the next
   `load_topic` skips it; a GUEST learning session writes NOTHING (re-assert the
   guest no-persist invariant with a mode set).
5. **Device verification:** redeploy backend; on a real device — pick each mode,
   confirm the bot leads the activity, end + re-enter to confirm topic advance;
   confirm free chat unchanged; confirm guest learning persists nothing (Firestore
   check). Capture results.

## Success Criteria

- [ ] After a learning session, the child's memory notes the topic + mode.
- [ ] The next session in that mode picks a different/unfinished topic.
- [ ] A guest learning session persists NOTHING (guest invariant intact with mode).
- [ ] Free-chat memory behavior unchanged; existing child docs still load.
- [ ] Real-device pass: all 4 modes work, free chat unchanged, no leak; backend +
      app suites green.

## Risk Assessment

- **Summarizer phrasing vs loader detection** — the write phrase and the read
  detection must agree. Keep both trivial (a fixed prefix like "đã học:") and test
  the round-trip.
- **Guest invariant regression** — adding mode context must not make a guest write;
  re-run the guest no-persist test WITH a mode set.
- **Over-tracking** — don't turn this into a progress DB; it's one short line in the
  existing summary. If detection gets fiddly, fall back to round-robin topic
  selection (still useful) rather than building structure.
- **Rollback:** stop passing mode context to the summarizer → memory behaves as
  today; `load_topic` falls back to first/round-robin topic.

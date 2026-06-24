---
phase: 4
title: Memory Topics-Done and Device Verification
status: completed
priority: P2
effort: 0.5d
dependencies:
  - 2
  - 3
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
2. Update the summarizer prompt to append the topic-done note using the EXACT
   format the matcher expects: `curriculum.DONE_MARKER + " " + f"{mode}:{topic_id}"`
   → i.e. **"đã học: <mode>:<topic_id>"** (note: a space after `đã học:`, then no
   space around the `:` between mode and id). Phase 2 already exports
   `curriculum.DONE_MARKER` and anchors `_topic_done` on this exact string — so the
   writer must use the same constant. (Phase-2 review flagged a space-mismatch
   risk; using the shared constant eliminates it.)
3. `curriculum.load_topic` "topics done" detection is ALREADY anchored on
   `DONE_MARKER` (phase 2) — no change needed unless the format changes here.
4. Tests: a registered child's learning session writes a topic note; the next
   `load_topic` skips it; a GUEST learning session writes NOTHING (re-assert the
   guest no-persist invariant with a mode set).
5. **Device verification:** redeploy backend; on a real device — pick each mode,
   confirm the bot leads the activity, end + re-enter to confirm topic advance;
   confirm free chat unchanged; confirm guest learning persists nothing (Firestore
   check). Capture results.

## Success Criteria

- [x] After a learning session, the child's memory notes the topic + mode.
- [x] The next session in that mode picks a different/unfinished topic.
- [x] A guest learning session persists NOTHING (guest invariant intact with mode).
- [x] Free-chat memory behavior unchanged; existing child docs still load.
- [x] Cloud-dev E2E pass: english mode led the lesson, advanced topics, no leak;
      backend suite green (48/48).

## Outcome (completed 2026-06-24)

- **Done-note is written DETERMINISTICALLY in code, not via the summarizer prompt**
  (stronger than the original step 2). The summarizer produces free-form prose;
  `gemini_session._with_done_notes` then re-asserts ALL `đã học: <mode>:<id>` markers
  (prior ones parsed from the existing summary + this session's) on their own lines.
  Both writer and matcher route through `curriculum.done_note` — one format, no
  drift. The matcher (`_topic_done`) matches the marker as the end of a line, so one
  topic id can't be a substring of another.
- **Why deterministic:** an LLM rewrite is free to drop a "đã học:" line, which would
  silently un-finish a topic. Carrying markers forward in code makes done-state
  durable across re-summarization.
- **E2E on cloud dev (`monami-backend-dev`, `dev_devices`):** session 1 (english) →
  memory got `đã học: english:animals`; session 2 → loader advanced to `food`, and
  the write kept BOTH markers even though the LLM's prose dropped them. Prod
  `devices` untouched; dev test child cleaned up.
- **Promotion to prod (`monami-backend`) + TestFlight rebuild is a SEPARATE,
  user-gated step** — not part of this phase.

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

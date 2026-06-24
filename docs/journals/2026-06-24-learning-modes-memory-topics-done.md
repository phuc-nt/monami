# Learning Modes — phase 4 (FINAL): Memory Topics-Done

**Date:** 2026-06-24
**Plan:** `plans/260624-0035-learning-modes-educational-companion/` (phase 4 of 4, terminal)

## Goal

End-of-session memory must durably record WHICH learning topic the child finished, so the companion advances to the next topic next session — without a new data model, using the existing per-child text memory (memory.summary).

## What shipped

- `backend/curriculum.done_note(mode, topic_id)` — single deterministic source for marker format: `"đã học: <mode>:<topic_id>"` (space after marker, no space around colon). Writer (summarizer) and matcher (_topic_done) both route through it → format cannot drift.
- `gemini_session._with_done_notes(new_summary, prior_summary, done_note)` — after the Gemini model produces a free-form summary, code re-asserts ALL markers:
  - every `"đã học: …"` line already in the prior summary PLUS
  - this session's done_note
  - each on its own line, after the prose
  - Why: an LLM rewrite ("merge into one concise note") can DROP a marker line. This silently un-finishes a topic and re-serves it next time. Carrying markers in code, not trusting the model, makes done-state durable across re-summarizations. (This was the marker-durability concern the code review flagged; fixed before finalize.)
- `curriculum._topic_done(mode, topic_id, memory_text)` — now matches marker at end-of-line only, not bare substring. Fixes prefix-collision false positives: "food" will no longer match inside "foods".

## Guest invariant: held

A guest session with a learning mode set still persists NOTHING — the whole done-note path gated behind the existing `persist` flag. Tested: guest_session_no_persist + guest_child_records_note cases.

## Verification + testing

- Backend suite: **48/48** (added `test_topics_done_roundtrip.py` incl. carry-forward-when-model-drops-marker + prefix-id edge cases; extended `test_guest_session_no_persist.py` with learning-mode guest + registered-child-records-note cases).
- E2E on REAL dev cloud (monami-backend-dev, FIRESTORE_PREFIX=dev_ → dev_devices, isolated from prod):
  - Session 1: english mode → memory got marker `"đã học: english:animals"` recorded.
  - Session 2: english mode, child asks new question → `load_topic` ADVANCED to next topic ("food") AND the summarizer kept BOTH markers even though the LLM's prose summary dropped them (M1 proven live, durability gap closed).
  - Cleanup: prod `devices` untouched; dev test child cleaned up (HTTP 204).
  - Cold start (scale-to-zero) then warm — working.

## State

**Learning Modes COMPLETE.** Feature end-to-end: optional `?mode=english|stories|science` WS param (absent = free chat, byte-identical backward-compat), app mode-selector chips (phase 3), JSON curriculum → one topic in system prompt (phase 2), memory notes topics done (phase 4, THIS). All 4 phases shipped on `monami-backend-dev`.

**Next (user-gated, NOT in this phase):** promote dev feature to prod (`monami-backend`), rebuild + push TestFlight. Prod `devices` Firestore untouched until promotion step; dev test data cleaned.

## Lessons

1. **Durability over trust.** An LLM rewrites text freely. If you care that a marker persists, carry it in code, not in the model's hands. Test that it actually does (the roundtrip test proves it).
2. **Substring matching bites.** `in` operator on text is almost never the right matcher for structured data. End-of-line anchoring costs nothing, catches real bugs.
3. **Constant-driven format.** When two layers (writer + matcher) must agree on a format, export ONE constant (`done_note()`) and route both through it. No manual "write a string" + "look for a string" in different files.

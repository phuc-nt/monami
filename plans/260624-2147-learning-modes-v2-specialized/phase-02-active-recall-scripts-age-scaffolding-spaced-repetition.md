---
phase: 2
title: Active-recall scripts + age scaffolding + spaced repetition
status: completed
priority: P1
effort: 3-5h
dependencies:
  - 1
---

# Phase 2: Active-recall scripts + age scaffolding + spaced repetition

## Overview
The pedagogical core. Rewrite the english + science leading scripts into a mandatory
**elicit–wait–respond** loop, inject an **age-band** line from `profile.age`, and add a
**spaced-repetition** instruction so the model briefly revisits prior topics. All three are
prompt/instruction changes — no new code paths, no architecture change. This phase carries the
plan's highest risk: whether the model actually WAITS instead of monologuing (confirmed in P4).

## Requirements
- Functional:
  - English script: ELICIT one item → ask the child to say it back → WAIT → praise if right /
    gently correct if wrong → only then move on. Never reads the whole word list in one breath.
  - Science script: state the phenomenon → ask the child to PREDICT "why" FIRST → WAIT → only
    then explain, tying back to the child's guess.
  - Age-band line injected based on `profile.age`: default 2 bands — **4-6** (very short
    sentences, 1 item/turn, lots of repetition, no sentence-building) and **7-10** (phrases →
    sentences, "explain why", multi-step, wider vocabulary). Within a session, go easy → hard.
  - Spaced repetition: if `memory_text` contains a prior `done_note(mode, id)` for THIS mode,
    the script tells the model to do a ~30s warm review of that old topic before the new one.
- Non-functional (HARD): free-chat path byte-identical (no mode → empty leading script, no
  age-band, no review note); guest still persists nothing; total prompt stays bounded.

## Architecture
- **Scripts:** `learning_modes._SCRIPTS[ENGLISH|SCIENCE]` get the new elicit-wait wording.
  `_LEAD_PREAMBLE` may be tightened to assert the WAIT discipline globally. `leading_script(None)`
  must still return `""` (free-chat unchanged).
- **Age-band seam:** a small pure helper `age_band_line(age:int) -> str` (location: `learning_modes.py`
  or a tiny helper — planner picks, but it must be unit-testable like `parse_mode`). The prompt
  builder appends it ONLY when a learning mode is active. `profile.age` already exists and is
  already rendered by `to_prompt_text()`, so this is an extra targeted line, not a new data source.
- **Spaced-repetition seam:** the instruction is static text in the leading script ("if the memory
  notes a topic you've already taught in this mode, start by briefly reviewing it"). The model
  reads `memory_text` (already in the prompt) and the `đã học: <mode>:<id>` notes there. No new
  code path, no reading Firestore differently.
- **Wiring:** confirm `gemini_session_config.build_system_prompt(profile, memory_text)` (or
  `build_live_connect_config`) is where leading_script + lesson + age-band compose, and that it
  receives `profile` (has `age`) and the active `mode`. Thread `mode`/`age` only if not already
  available there.

## Related Code Files
- Modify: `backend/learning_modes.py` — rewrite ENGLISH + SCIENCE scripts (elicit-wait + spaced-rep
  line); add `age_band_line(age)` helper (pure, testable).
- Modify: `backend/gemini_session_config.py` — append `age_band_line(profile.age)` when a mode is
  active; keep free-chat assembly byte-identical.
- Verify (likely no change): `backend/gemini_session.py` — `run_session` already passes `mode` and
  resolves the profile; spaced-rep needs no new path since `memory_text` is already in the prompt.
- Modify (tests): `backend/tests/test_learning_modes.py` (+ new cases) — assert english/science
  scripts contain an explicit WAIT/elicit instruction and a review instruction; `age_band_line`
  maps 4/6/7/10 to the right band; free-chat (`leading_script(None)`) is still `""`; guest-no-persist
  and free-chat byte-identical invariants still hold.

## Implementation Steps
1. Decide the exact age-band thresholds (default 4-6 / 7-10; planner may add a 3rd band if a clear
   need — keep 2 unless justified). Write `age_band_line(age)` returning a one-line bilingual band
   hint; `""` for out-of-range/guest-neutral if desired (decide + test the boundary).
2. Rewrite `_SCRIPTS[ENGLISH]`: enforce one-item elicit → "ask the child to repeat" → "STOP and wait
   for the child, do NOT continue" → praise/correct → next. Add the spaced-rep review line.
3. Rewrite `_SCRIPTS[SCIENCE]`: phenomenon → "ask the child to guess WHY first" → "STOP and wait" →
   explain tying back to the guess → follow-up. Add the spaced-rep review line.
4. In the prompt builder, append `age_band_line(profile.age)` only when `mode` is a learning mode.
   Leave the free-chat branch untouched (byte-identical).
5. Add/adjust unit tests for: script contains WAIT+elicit wording; `age_band_line` bands; free-chat
   empty script; invariants. Run `pytest tests/ -q`.

## Success Criteria
- [ ] english + science scripts each contain an explicit, hard WAIT/elicit instruction (asserted by test).
- [ ] `age_band_line(4)`, `(6)`, `(7)`, `(10)` return the expected band hints (tested at boundaries).
- [ ] Age-band line present in a learning-mode prompt, ABSENT in a free-chat prompt.
- [ ] Spaced-rep review instruction present in both learning scripts (asserted by test).
- [ ] `leading_script(None) == ""`; free-chat byte-identical test green; guest-no-persist green.
- [ ] backend `pytest tests/ -q` green.

## Risk Assessment
- **Risk (highest in the plan):** model ignores the WAIT and monologues anyway. *Mitigation:*
  make the instruction blunt and repeated ("DỪNG. Chờ bé trả lời. KHÔNG nói tiếp."); verify on a
  real device in P4 — unit tests only prove the *instruction* is present, not that the model obeys.
- **Risk:** age-band line bloats the prompt / hurts latency. *Mitigation:* keep it ONE short line;
  lesson already capped by `_MAX_LESSON_CHARS`.
- **Risk:** accidental drift in the free-chat prompt. *Mitigation:* keep the byte-identical test;
  only append age-band inside the mode-active branch.
- Rollback: revert scripts to v1 wording; no persisted state changes.

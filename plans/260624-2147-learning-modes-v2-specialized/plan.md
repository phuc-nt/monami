---
title: Learning Modes v2 — Specialized English + Science
description: >-
  Make english + science modes pedagogically distinct from free-chat (active
  recall + age scaffolding + spaced repetition); drop stories; rename science
  label.
status: completed
priority: P2
created: 2026-06-24T00:00:00.000Z
blockedBy: []
blocks: []
---

# Learning Modes v2 — Specialized English + Science

## Overview

Learning Modes v1 shipped 3 modes (english/stories/science) but english+science are not
meaningfully better than free-chat — the model answers an English/science question in free
chat too. This plan makes the two modes *teach* via a structured loop free-chat can't do:
**active recall** (model asks & WAITS for the child), **age scaffolding** (uses the existing
`profile.age` to set difficulty for ages 4-10), and **spaced repetition** (revisit past topics
from memory). It also drops `stories` entirely and renames the science button label
"Vì sao?" → "Khoa học". Architecture unchanged: Gemini Live native-audio, optional `?mode=`
WS param, JSON curriculum + leading script in the system prompt, per-child text memory.

Source design: `plans/reports/brainstorm-260624-2147-learning-modes-v2-specialized-english-science-report.md`

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Drop stories + rename label](./phase-01-drop-stories-rename-label.md) | Completed |
| 2 | [Active-recall scripts + age scaffolding + spaced repetition](./phase-02-active-recall-scripts-age-scaffolding-spaced-repetition.md) | Completed |
| 3 | [Curriculum schema v2 + expand topics](./phase-03-curriculum-schema-v2-expand-topics.md) | Completed |
| 4 | [Device + dev-cloud verification](./phase-04-device-dev-cloud-verification.md) | Completed |

## Dependencies

- P2 depends on P1 (clean 2-mode set before rewriting scripts).
- P3 depends on P2 (scripts reference the new `elicit_vi`/`predict_vi` fields).
- P4 depends on P1-P3 (verifies the whole thing on a real device + dev cloud).
- External: builds on completed plan `260624-0035-learning-modes-educational-companion` (v1).
  No blocking relationship — v1 is `completed`.

## Acceptance (whole plan)

- `stories` removed cleanly from backend + app + JSON; an old app build sending `?mode=stories`
  still resolves to free-chat (no crash) — regression test kept.
- Science button shows "Khoa học"; the `science` mode key, JSON, and done-notes are unchanged.
- english + science run an **elicit–wait–respond** loop on a real device: the model asks a
  question and WAITS for the child instead of reading the whole list / lecturing in one breath.
  (This is the defining success criterion and can only be confirmed on-device, not by unit tests.)
- Difficulty visibly tracks `profile.age` (younger = shorter/simpler).
- Spaced repetition: with a prior `done_note` in memory, the model briefly revisits the old
  topic before the new one.
- 4 topics per mode (english, science) — 8 total.
- HARD invariants preserved: guest sessions persist NOTHING (even with a mode set); free-chat
  is byte-identical to today; existing child docs still load; lesson stays within
  `_MAX_LESSON_CHARS`.

## Out of scope (deferred)

Pronunciation scoring; new UI / WS params / Gemini Live architecture changes; a dedicated
learning data model; age-variant curriculum content (the model self-adjusts from `age`);
on-screen images; parent dashboard. **Promoting to prod + rebuilding TestFlight is a separate,
user-gated step — NOT part of this plan.**

## Validation Log

### Verification Results (Standard tier — 4 phases)
- Claims checked: 14 | Verified: 14 | Failed: 0 | Unverified: 0
- Roles: Fact Checker + Contract Verifier
- Key confirmations (file:line evidence):
  - `learning_modes.py`: `ENGLISH/STORIES/SCIENCE` (21-23), `VALID_MODES` (25), `parse_mode`
    (28), `_SCRIPTS` (55), `leading_script` (88) — all present, stories removal seam confirmed.
  - `curriculum.py`: `DONE_MARKER` (58), `done_note` (61), `_topic_done` (68), `load_topic` (84),
    `render_lesson` (104), `_render_english/_render_story/_render_science` (123/138/150),
    `_MAX_LESSON_CHARS=800` (28) — schema-v2 + drop-story seams confirmed.
  - `gemini_session_config.py`: `build_system_prompt(profile, memory_text, mode)` (74-77)
    ALREADY takes `mode` AND `profile` (has `age`); age-band must be appended INSIDE the
    `if script:` block (99-108) so free-chat stays byte-identical. This is the exact P2 seam.
  - `gemini_session.py`: `run_session` already threads `mode` → `load_topic`/`render_lesson`
    (173-178); spaced-rep needs no new code path (memory_text already in prompt).
  - App `learning_mode.dart`: enum + 3 switches (wsValue/label/icon) confirmed; `learning_mode_test.dart`
    exists and must be updated when the enum changes.

### Decisions Confirmed (validation interview)
1. **Age-band:** 2 bands — **4-6 / 7-10** (plan default kept). `age_band_line` tests boundaries 4/6/7/10.
2. **Topic count:** **4 topics per mode** (english 4 + science 4 = 8 total). (Was "4-5"; now fixed at 4.)
3. **Content review gate:** I generate ALL new topics (bilingual, age-appropriate) → **user reviews
   the full set BEFORE writing to JSON** (hard gate in P3, not after).
4. **P4 verify method:** **both** — `ws_test_client.py` first (fast: topic-advance, done-note,
   prompt correctness), then **app on a real iPhone** to confirm the elicit-wait experience.
5. **App build for P4:** **yes** — P1 changes the app (drop `stories` enum + "Khoa học" label), so
   build a **dev IPA pointed at `monami-backend-dev`** to verify UI + elicit-wait on device.

### Recommendation
Proceed. Failed: 0 → safe for `--auto` on the low-risk phases (P1, P3 mechanical parts); the
elicit-wait behavior risk is handled by the mandatory on-device gate in P4, not by skipping review.

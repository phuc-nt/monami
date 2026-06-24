# Learning Modes v2: drop stories, specialize English/Science

**Date:** 2026-06-24  
**Plan:** `plans/260624-2147-learning-modes-v2-specialized/` (phase 3 complete)

## Goal

Make English and Science modes pedagogically distinct from free-chat (which already
simulates any conversation). Shift target age 5 → 4-10. Introduce three mechanisms
to elicit active learning: (1) ask-then-wait loops, (2) age-band scaffolding,
(3) spaced repetition via memory notes.

## What shipped

**Three changes end-to-end:**

1. **Dropped stories/Kể chuyện mode** — removed `curriculum/stories.json`, deleted
   backend `learning_modes.py` enum entry + `curriculum.py` handler, dropped app
   `LearningMode.stories` + router `case "stories"`. Zero bytes wasted on unshipped
   pedagogy.

2. **Specialized English + Science modes** — three prompt/instruction-level mechanisms
   (no architecture change):
   - **Active recall loop** — rewrote English+Science leading scripts into
     `ASK_THEN_WAIT` pattern: model elicits ONE item/question, prints
     `"DỪNG. Chờ bé trả lời. KHÔNG nói tiếp."` and halts. Older version monologued;
     v2 forces elicitation. Verified live: model taught one word ("dog") + waited,
     child said "Con thử nói xem!" → model recorded it.
   - **Age scaffolding** — new helper `learning_modes.age_band_line(age)` returns
     instruction line for 2 bands (4-6 / 7-10), clamps out-of-range, never empty.
     Appended in `gemini_session_config.build_system_prompt()` INSIDE the mode-active
     `if script:` branch only — free-chat stays byte-identical.
   - **Spaced repetition** — static instruction line in both scripts. Model reads
     per-child memory's `"đã học: <mode>:<topic_id>"` notes (already in system
     prompt) and briefly reviews one prior topic. No new code path.

3. **Renamed science button** — label `"Vì sao?"` → `"Khoa học"` (mode key `science`
   unchanged). Matches Vietnamese education terminology.

## Curriculum schema v2 (backward-compatible)

Grew from 2 → 4 topics per mode (8 total):
- **English:** animals, food, `+ numbers, body_parts`
- **Science:** why-sky-blue, why-birds-fly, `+ how-plants-grow, where-water-goes`

Original topic IDs (animals/food/why-sky-blue/why-birds-fly) preserved — no
done-note orphaning on existing devices. New topics gain optional fields:
- English topic: `elicit_vi` (recall prompt, e.g., "Em nhớ lại xem...")
- Science topic: `predict_vi` (rendered BEFORE the suggested answer, so model asks
  child to guess first). All 8 topics user-reviewed + approved before JSON write.

## Hard invariants preserved

- **Free-chat byte-identical:** no mode → empty script, no age-band line appended.
- **Legacy fallback:** `?mode=stories` from old app builds → free chat (no crash).
- **Guest persistence:** guest/null still persists nothing.
- **Lesson cap:** rendered lesson ≤ `_MAX_LESSON_CHARS` (800 chars).
- **Done-note round-trip:** `DONE_MARKER` / `done_note` / `_topic_done` / `load_topic`
  unchanged.

## Verification

- **Backend:** 55 pytest passed (new coverage: elicit-wait loop, age bands, v2
  schema). Code reviewer: 0 blockers.
- **App:** 50 Flutter tests + `flutter analyze` clean.
- **Two-stage device verify:**
  - **Stage 1 (dev):** ws_test_client.py against monami-backend-dev (FIRESTORE_PREFIX=dev_).
    Confirmed elicit-wait live (model taught "dog", printed wait instruction),
    done-note round-trip (session 1: english:animals → session 2 advances to food),
    stories-mode fallback (no crash).
  - **Stage 2 (iPhone):** user tested dev build on a real iPhone 15; approved
    elicit-wait UX ("Con thử nói xem!" then silent wait).
- **Prod deployment:** promoted to LIVE backend monami-backend revision 00005-vxk
  (FIRESTORE_PREFIX removed → prod `devices`). Health 200. Elicit-wait smoke-tested
  on prod. Temp test child cleaned.

## State

Shipped to production. Flutter archive built (1.0.0+4, bundle com.phucnt.openchatbot,
prod backend baked). Six commits on main NOT yet pushed.

## Open items

- **TestFlight Distribute:** Runner.xcarchive ready; blocked on missing "iOS
  Distribution" signing cert/private key in Xcode Organizer — user must Distribute
  via Xcode (regenerates cert there).
- **Push 6 commits to origin/main.**
- **Cosmetic:** launch image still default placeholder (user deferred).

---
phase: 4
title: Device + dev-cloud verification
status: completed
priority: P1
effort: 2-3h
dependencies:
  - 1
  - 2
  - 3
---

# Phase 4: Device + dev-cloud verification

<!-- Updated: Validation Session 1 - verify in two stages (ws_test_client.py first, then dev IPA on iPhone) -->

## Overview
Prove the thing that unit tests can't: on a REAL device against the dev cloud backend, the
english + science modes actually run the elicit–wait–respond loop (model asks and WAITS),
difficulty tracks age, spaced repetition revisits old topics, and stories is gone cleanly —
all without touching prod data. This phase defines whether the plan succeeded.

**Two-stage verify (confirmed):** (1) `ws_test_client.py` first to check logic fast (topic
advance, done-note round-trip, prompt correctness, `?mode=stories`→free-chat); (2) then build a
**dev IPA pointed at `monami-backend-dev`** and run it on a real iPhone to confirm the elicit-wait
*experience* (model asks & WAITS) + the "Khoa học" label + no stories button. Stage 2 is the gate.

## Requirements
- Functional verification (on-device, dev cloud `monami-backend-dev`, `FIRESTORE_PREFIX=dev_`):
  1. **Elicit-wait holds:** in english, the model says a word and WAITS for the child to repeat
     before continuing (does NOT read the whole list); in science, it asks the child to guess
     "why" and WAITS before explaining. This is THE success criterion.
  2. **Age scaffolding:** a younger profile gets noticeably shorter/simpler turns than an older one.
  3. **Spaced repetition:** a second session in the same mode, with a `done_note` in the child's
     dev memory, opens with a brief review of the prior topic.
  4. **Stories gone:** no story mode reachable; an explicit `?mode=stories` connect behaves as
     free-chat (backward-compat).
- Non-functional (HARD): prod `devices` collection UNTOUCHED; guest learning session persists
  nothing; clean up the dev test child afterward.

## Architecture
Deploy P1-P3 code to `monami-backend-dev` (separate `dev_devices` collection via
`FIRESTORE_PREFIX=dev_`). Drive sessions via `backend/scripts/ws_test_client.py` (has `--mode`;
for a registered child pass `--device <id> --profile <childId>` — create the child first via REST
on the dev backend) and/or the app pointed at the dev WS. Token from Secret Manager.

## Related Code Files
- Use: `backend/scripts/ws_test_client.py` (drive english/science sessions with `--mode`).
- Use: dev deploy command from the `monami:backend` skill / `app/RELEASE.md` (with
  `FIRESTORE_PREFIX=dev_`).
- No production code changes expected in this phase (verification only; fix-forward if a defect
  surfaces, then re-verify).

## Implementation Steps
1. Deploy P1-P3 to `monami-backend-dev` (FIRESTORE_PREFIX=dev_). Health check.
2. Create a dev registered child via REST (note the `age` for the scaffolding check).
3. **Stage 1 — `ws_test_client.py`:** run english + science sessions; verify the prompt is correct
   (elicit/predict + age-band lines present), `?mode=stories`→free-chat, the done-note is written,
   and `load_topic` advances on session 2. Fast logic check before building anything.
4. Re-run the same mode in a second session; confirm the opening review of the prior topic
   (spaced repetition) and that `load_topic` advanced to a new topic.
5. Compare a young vs older profile to confirm age scaffolding differs.
6. **Stage 2 — dev IPA on iPhone:** build a dev IPA pointed at `monami-backend-dev`, install on a
   cabled iPhone. Confirm on-device: english elicits one word and WAITS; science asks the child to
   guess "why" and WAITS; the "Khoa học" label shows; no stories button. THIS is the success gate.
7. Read `dev_devices` to confirm the done-notes; CONFIRM prod `devices` is untouched. Clean up the
   dev test child.

## Success Criteria
- [ ] On-device: english + science run elicit–wait–respond (model asks & WAITS, no monologue).
- [ ] Difficulty visibly tracks `profile.age` (young vs older differ).
- [ ] Spaced repetition: 2nd same-mode session opens by revisiting the prior topic.
- [ ] `?mode=stories` → free-chat; no story content.
- [ ] dev memory shows correct `đã học: <mode>:<id>` notes; topic advanced on session 2.
- [ ] prod `devices` collection untouched; guest session persisted nothing; dev test child cleaned up.

## Risk Assessment
- **Risk:** model still monologues despite the WAIT instruction. *Mitigation:* if so, this is a
  fix-forward in P2 (strengthen wording) then re-verify — do NOT mark the plan done until the loop
  holds on-device. This is the plan's defining risk.
- **Risk:** accidental prod write. *Mitigation:* dev backend uses `dev_devices` prefix; explicitly
  read prod `devices` to confirm no change; never run against prod URL.
- **Risk:** dev test child left behind. *Mitigation:* explicit cleanup step + verify.
- Rollback: dev-only; revert the dev deploy. Prod promotion is a separate user-gated step.

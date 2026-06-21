---
phase: 3
title: "Integrate Bilingual Voice Loop"
status: pending
priority: P1
effort: "0.5-1d"
dependencies: [2]
---

# Phase 3: Integrate Bilingual Voice Loop

## Overview

Wire backend + Flutter client into one working conversation and tune it: bilingual
EN/VN, the hard-coded child profile felt in responses, warm safe tone, smooth
turn-taking. This is where the pieces become an actual experience.

## Requirements

- Functional: a full spoken conversation works end-to-end (multiple turns in one
  session); EN and VN both handled; child profile (name + interests) reflected in
  greetings/answers; safety holds.
- Non-functional: turn-taking feels natural (no obvious clipping in normal speech);
  perceived latency acceptable; session survives several back-and-forth turns.

## Architecture

- No new components — integration + tuning of Phase 1/2.
- Multi-turn: keep the Gemini Live session open across turns; backend manages
  turn boundaries (trailing-silence VAD) and forwards each turn.
- Profile injection: `child_profile.py` text stuffed into the system prompt at session
  start (name + a couple interests, e.g. likes Elsa / cars). One hard-coded profile.
- Tuning knobs: `END_SILENCE_MS` (turn-end), playback jitter buffer, prompt wording
  for tone/brevity/slow-pacing for a 5yo.

## Related Code Files

- Modify: `backend/gemini_session_config.py` (prompt tuning, profile wording)
- Modify: `backend/child_profile.py` (the hard-coded profile content)
- Modify: `backend/gemini_session.py` (multi-turn handling if needed)
- Modify: `app/lib/voice_controller.dart` (multi-turn UX: re-arm push-to-talk, show speaking state)
- Modify: `app/lib/main.dart` (polish minimal UX: clear listening/speaking cues)

## Implementation Steps

1. Confirm multi-turn: have a 3-4 turn spoken conversation in one session; fix any
   state issues (e.g. push-to-talk re-arming, audio overlap).
2. Profile felt: bot greets/uses the child's name and references an interest naturally.
3. Bilingual check: say a VN turn and an EN turn in the same session; both handled,
   code-switching natural.
4. Tone/safety pass: verify warm, short, slow, age-5 wording; try a gentle off-topic
   prompt → graceful redirect.
5. Tune `END_SILENCE_MS` + jitter buffer for natural normal-speed turn-taking (NOT the
   slow-speech edge case — that's Phase 4).
6. Quick latency sanity check on the real loop (full Phase 4 measurement later).

## Success Criteria

- [ ] A multi-turn spoken conversation works in one session.
- [ ] EN and VN both handled in the same conversation.
- [ ] Child profile reflected (name + interest) naturally.
- [ ] Tone warm/age-appropriate; off-topic gets gentle redirect; safety holds.
- [ ] Normal-speed turn-taking feels natural (no obvious clipping).

## Risk Assessment

- **Audio overlap / double-talk** across turns → ensure playback finishes / mic gating
  on push-to-talk; serialize turns.
- **Profile makes prompt brittle** → keep profile text short, plain; don't over-engineer.
- **Tuning END_SILENCE_MS trades latency vs clipping** → tune for normal speech here;
  slow-speech is the Phase 4 gate, don't conflate.

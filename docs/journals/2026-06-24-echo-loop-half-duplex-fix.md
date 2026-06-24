# Echo loop fix — half-duplex mic gate

**Date:** 2026-06-24

## Symptom

TestFlight 1.0.0 feedback: child says one sentence → AI replies 2-3 times,
each reply nearly identical, sometimes looping non-stop. Only on built-in
**speaker**; headphones = no problem.

## Root cause

Acoustic echo feedback loop. The app streams the mic continuously and relies on
the backend's server VAD for turn boundaries (no per-turn end_utterance). On a
loudspeaker the mic re-captures the bot's own voice → server VAD treats it as a
new utterance → bot replies again → that reply plays → re-captured → loop.
Headphones break the acoustic path, hence no loop there. Not a server
duplicate/replay; purely client-side echo.

## Fix — half-duplex gate (KISS, chosen over hardware AEC)

`voice_controller.dart`: while the bot is speaking (state `speaking`) the mic
stream keeps running but its chunks are NOT sent to the server. After playback
drains, a 400ms guard keeps suppressing so room/speaker tail echo dies out, then
sending resumes. The bot's audio can no longer re-enter the VAD → loop broken at
the source.

- Decision extracted as a pure static `VoiceController.shouldSendMicAudio(state,
  speakingEndedAt, now)` so it's unit-testable without platform plugins (matches
  the existing `buildConnectUrl`/`restBaseOf` testable-helper pattern).
- Rejected hardware AEC for now: iOS has two plugins (`record` +
  `flutter_pcm_sound`) contending for the AVAudioSession; enabling
  voice-processing reliably is risky and hard to verify. Half-duplex is simple,
  certain, and fine for a 5-year-old (interrupting the bot mid-reply is rare).

## Verification

- `flutter analyze` clean; app suite 49/49 (+5 echo-gate cases).
- Real device (iPhone 16, built-in speaker, dev cloud backend): one sentence →
  exactly one reply, no loop; subsequent turns work (mic auto-resumes after the
  bot finishes).

## Scope

Same voice loop ships in TestFlight 1.0.0, so this fix is needed in prod too.
Trade-off: the child can't barge in over the bot until it stops speaking — a
deliberate, acceptable limitation. Hardware full-duplex AEC remains a possible
later enhancement if barge-in is wanted.

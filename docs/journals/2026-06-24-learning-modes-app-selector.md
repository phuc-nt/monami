# Learning Modes — phase 3: app mode selector

**Date:** 2026-06-24
**Plan:** `plans/260624-0035-learning-modes-educational-companion/` (phase 3 of 4)

## Goal

Give the child (or parent) a way to pick a learning mode from the voice screen,
so the optional `?mode=` the backend already understands gets sent — without
touching the voice loop or regressing free chat.

## What shipped

- `app/lib/learning_mode.dart` — `enum LearningMode { chat, english, stories,
  science }` with `wsValue` (null for chat → no param; else the backend strings),
  VN `label`, and `icon`. The single app-side source mirroring backend
  `VALID_MODES`; a drift falls back to free chat server-side.
- `app/lib/voice_controller.dart` — `buildConnectUrl` gained an optional `mode`
  (dropped when empty). The controller holds the active mode; `setMode(m)` updates
  it + reconnects via the existing `reconnect()` (shutdown+reopen, reusing the
  cold-start UX), no-op if unchanged/disposed.
- `app/lib/main.dart` — a compact `_ModeSelector` (a Wrap of stadium chips, one per
  mode) on the voice screen between the status line and the talk button. Default =
  "Trò chuyện" (free chat); the active chip is highlighted in the child tint; taps
  are debounced + haptic. Doesn't crowd the robot-face hero.

## The invariant held

Free chat = default. `chat.wsValue` is null → `buildConnectUrl` drops the param →
the URL is byte-identical to before. A child/guest who never taps a mode connects
exactly as today. Locked by the extended `guest_mode_url_test.dart`.

## Verification + E2E (on a dedicated dev backend)

- 6 new tests + 44/44 full app suite; `flutter analyze` clean.
- **Simulator E2E vs the DEV cloud backend** (not prod/TestFlight): the integration
  test drove the real selector — rendered all 4 chips, default chat, switched
  modes. The dev backend logs confirmed the taps arrived as `?mode=english`,
  `?mode=stories`, and `mode=chat` (free chat). Prod `devices` collection untouched
  (dev data is isolated under `dev_devices` via FIRESTORE_PREFIX). Note: the dev
  backend is scale-to-zero, so the first run cold-started (a few seconds) — once
  warm the E2E passed consistently.

## Review

Verdict: safe, all 6 criteria met, no must-fix. Applied the one suggested cleanup
(L1): moved the tap-debounce from a process-static `Map<VoiceController,DateTime>`
(which never evicted disposed controllers) to instance state on `_ModeSelector`,
matching the existing `VoiceController._lastToggle` pattern.

## State

Phase 3 done + cloud-E2E verified. Only phase 4 left: the end-of-session summarizer
writes the `DONE_MARKER` ("đã học: <mode>:<id>") so the companion remembers what was
learned and the loader advances to the next topic, then a real-device pass.

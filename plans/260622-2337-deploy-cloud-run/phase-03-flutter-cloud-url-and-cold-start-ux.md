---
phase: 3
title: "Flutter Cloud URL And Cold Start UX"
status: pending
priority: P2
effort: "0.5d"
dependencies: [2]
---

# Phase 3: Flutter Cloud URL And Cold Start UX

## Overview

Point the app at the cloud backend (configurable URL + token), and make the
cold-start wait friendly: while the (scale-to-zero) backend wakes up, show a
clear "đang đánh thức bạn nhỏ…" state and LOCK the talk button so the child can't
trigger broken actions; add a timeout + retry.

## Requirements

- Functional: the app connects to `wss://…run.app/ws/voice?profile=<id>&token=…`.
  On connect (especially a cold start) the UI shows a distinct "connecting/waking
  up" state with the robot in a gentle waking look and the talk button DISABLED;
  once the backend is ready (socket open / first session) it switches to the
  normal idle state and enables the button. If connecting exceeds a timeout, show
  a friendly error + a "Thử lại" (retry) action.
- Non-functional: URL + token are configurable (NOT hardcoded in source — e.g.
  `--dart-define` or a gitignored config), with a local default for dev. No
  regression to the voice loop / robot face / memory recall.

## Architecture

- **Config**: read base URL + token from `--dart-define` (e.g.
  `MONAMI_WS_BASE`, `MONAMI_TOKEN`) with a local-dev default (`ws://127.0.0.1:8000/
  ws/voice`, empty token). `VoiceController`/`VoiceSocket` build the full URL with
  `?profile=&token=`.
- **Connecting state**: add a `connecting` state (or reuse `disconnected` with a
  `bool _connecting`) in `VoiceController` so the UI can distinguish "waking up"
  from "failed". Enter it on `connect()`, leave it when the socket opens (→ idle)
  or errors/times out (→ disconnected with a message).
- **UI** (`main.dart`): when connecting, robot shows a gentle "waking" expression
  (e.g. `sleepy`/blinking), status line says "Đang đánh thức bạn nhỏ…", and the
  talk button is visibly disabled (greyed, non-tappable). A connect-timeout (e.g.
  12-15s) flips to an error state with a "Thử lại" button (calls `reconnect`).
- **Token safety**: never print the token; keep it out of committed files.

## Related Code Files

- Modify: `app/lib/voice_controller.dart` (config URL + token; a connecting state;
  connect timeout → retry)
- Modify: `app/lib/voice_socket.dart` (append `&token=` if present)
- Modify: `app/lib/main.dart` (cold-start UI: waking look, locked button, retry)
- Create/Modify: a small config source (e.g. `app/lib/app_config.dart` reading
  `--dart-define`), default to local dev
- Modify: `app/test/widget_test.dart` if the home/wiring changes

## Implementation Steps

1. `app_config.dart`: base URL + token from `String.fromEnvironment(...)` with
   local defaults. Document the `--dart-define` flags in `app/README.md`.
2. Thread config into `VoiceController` (build `?profile=&token=`); `voice_socket`
   appends the token when present.
3. Add the `connecting` state + a connect timeout (→ error + retry) in the
   controller; keep the voice loop logic otherwise unchanged.
4. `main.dart`: render the cold-start state — waking robot, "đang đánh thức…",
   DISABLED talk button; on timeout show "Thử lại".
5. Verify against the deployed Cloud Run backend: cold start shows the waking UI +
   locked button, then becomes ready; a full conversation works; memory recalled.
   Confirm local dev still works with defaults.

## Success Criteria

- [ ] App connects to the cloud over `wss://` with the token.
- [ ] During cold start: friendly "waking up" UI, talk button DISABLED (no broken
      taps), then auto-enables when ready.
- [ ] Connect timeout → clear message + working "Thử lại".
- [ ] URL + token are configurable and NOT hardcoded/committed; local dev default
      still works.
- [ ] Full spoken loop + memory recall work from the cloud; `flutter analyze`
      clean; smoke test passes; macOS build OK.

## Risk Assessment

- **Child taps during cold start** → the talk button is disabled in the connecting
  state (the core requirement); also guard `toggleMic()` when not idle.
- **Token leaks into source/logs** → load via `--dart-define`/gitignored config;
  never log it.
- **Cold start longer than expected** → generous timeout + retry; the waking UI
  keeps it from looking broken.
- **Local vs cloud config confusion** → default to local dev; require explicit
  `--dart-define` for the cloud build; document both in `app/README.md`.

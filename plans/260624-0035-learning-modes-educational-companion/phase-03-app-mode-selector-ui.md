---
phase: 3
title: "App Mode Selector UI"
status: completed
priority: P2
effort: "1d"
dependencies: [1]
---

# Phase 3: App Mode Selector UI

## Overview

Add a friendly mode selector to the voice screen so a child (or parent) can pick
"Trò chuyện / Học tiếng Anh / Kể chuyện / Vì sao?". The choice adds an optional
`mode` to the WS URL; reconnecting in a new mode reopens the session with it.

## Requirements

- Functional:
  - A compact, icon-led selector on the voice screen with 4 entries:
    - **Trò chuyện** (`mode=null` → free chat, the default/selected at start)
    - **Học tiếng Anh** (`mode=english`)
    - **Kể chuyện** (`mode=stories`)
    - **Vì sao?** (`mode=science`)
  - Tapping a mode that differs from the current one **reconnects** the session
    with the new `mode` (the WS URL is built at connect-time — phase-2 of
    publish-prep made `buildConnectUrl` pure + param-dropping, so an empty/absent
    mode = free chat).
  - Big, few, icon-led buttons (kid-tappable); the current mode is visibly
    selected. Tapping randomly is safe (all modes are safe content).
  - Default on entering the voice screen = **Trò chuyện** (no behavior change for
    anyone who never taps a mode).
- Non-functional:
  - **Backward compatible:** with mode = free chat, the screen + voice loop behave
    exactly as today.
  - Mode strings are the SAME constants as the backend `VALID_MODES`
    (`english`/`stories`/`science`) — keep one Dart source mirroring them.
  - Match the existing theme (Baloo font, dark, per-child tint).
  - Don't disrupt the talk button / cold-start / robot face.

## Architecture

- `voice_controller.dart`: add an optional `mode` to the controller (or a
  `setMode(mode)` that updates the field + reconnects). `buildConnectUrl` gains a
  `mode` param (dropped when empty/null) — same drop-empty pattern as
  device/profile/token. Reconnect = `shutdown()` + reopen with the new URL.
- New `lib/learning_mode.dart`: a small enum/const mirror of the backend modes +
  their VN label + icon, so the selector + the controller agree.
- `main.dart` (`VoiceHome`): render the selector (a `Wrap`/`Row` of mode chips)
  above or below the robot face; wire taps → `controller.setMode(...)`. Default
  selected = free chat.

## Related Code Files

- Create: `app/lib/learning_mode.dart`.
- Modify: `app/lib/voice_controller.dart`, `app/lib/main.dart`.
- Create (tests): `app/test/learning_mode_url_test.dart` (mode→URL),
  extend a render test to show the selector.

## Implementation Steps

1. `learning_mode.dart`: `enum LearningMode { chat, english, stories, science }`
   + `wsValue` (null for chat, else the backend string) + VN label + icon.
2. `voice_controller.dart`: store the current mode; `buildConnectUrl(..., mode)`
   drops it when null; `setMode(m)` updates + reconnects (shutdown + reopen).
3. `main.dart`: a mode selector widget on the voice screen; default = chat;
   highlight the active one; tap → `setMode`.
4. Tests: `buildConnectUrl` with each mode (chat → no `mode=`; others → `mode=…`);
   render the selector; tapping a mode rebuilds the URL with it.

## Success Criteria

- [ ] The voice screen shows 4 mode entries; **Trò chuyện** is the default.
- [ ] Selecting **Học tiếng Anh/Kể chuyện/Vì sao?** reconnects with `?mode=…`; the
      bot leads that activity (with phase 2's content).
- [ ] Selecting **Trò chuyện** (or never tapping) = today's free chat, unchanged.
- [ ] Mode strings match the backend exactly; `flutter analyze` clean; tests pass.
- [ ] Robot face / talk button / cold-start unaffected.

## Risk Assessment

- **Reconnect UX** — switching mode tears down + reopens the socket (a brief
  connecting state). Acceptable; reuse the existing cold-start UX. Debounce rapid
  mode taps like the talk button.
- **Selector clutter on a small phone** — keep it to 4 compact chips; it must not
  crowd the robot-face hero. Test on phone + iPad, portrait + landscape.
- **String drift** — `learning_mode.dart` is the single app-side source; a mismatch
  with backend `VALID_MODES` silently falls back to free chat (safe but wrong) —
  cover with a comment + (optionally) a shared-constants check.
- **Rollback:** remove the selector → controller defaults to free chat → today's app.

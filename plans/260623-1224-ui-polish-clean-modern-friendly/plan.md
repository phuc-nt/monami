---
title: "UI Polish Clean Modern Friendly"
description: "A single visual-polish pass on the Flutter app per the UI/UX review: dark theme/AppBar, robot-face hero + glow, per-child gradient background, Baloo 2 font, hide status text on the kid screen, lively talk button, picker card cap, micro-animations, haptics, dark launch screen. No voice-logic changes."
status: completed
priority: P2
created: 2026-06-23
blockedBy: [260623-0807-ios-ipad-universal-polish]
---

# UI Polish Clean Modern Friendly

## Overview

Make the app feel designed — clean + modern, yet friendly and easy for a 5-year-old
— per the UI/UX review
(`plans/reports/ui-ux-review-260623-1224-monami-clean-modern-friendly-improvements.md`).
This is a **UI-only** pass: theme, layout, motion, font, and small touch polish.
The voice loop, robot face logic, memory, cold-start state machine, and backend are
untouched.

## Decided (from the review)

- Scope: **all of P1 + P2 + P3.**
- Font: add **Baloo 2** (rounded, kid-friendly) via `google_fonts`.
- Status text: **hidden on the kid-facing screen** (the robot face conveys state);
  kept in the dev transcript panel and on the disconnected/reconnect affordance.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Visual Polish Pass](./phase-01-visual-polish-pass.md) | ✅ Completed |

## Acceptance criteria (whole plan)

- No light AppBar clash — the app is consistently dark; AppBar matches the body.
- The robot face reads as the hero (fills the space, soft glow), not floating in
  emptiness; each child's screen carries their tint (gradient background).
- Baloo 2 font applied app-wide; status text hidden on the kid screen (face speaks),
  still shown in dev panel + on disconnect.
- Talk button feels inviting (idle pulse, pressed + listening feedback); picker
  cards capped + tidy on iPad; transitions animate; haptic on tap (iOS); dark
  launch screen.
- No regression to the voice loop / memory / cold-start; `flutter analyze` clean;
  tests pass; iOS sim + macOS build OK; verified via simulator screenshots.

## Scope OUT

Voice/audio logic, backend, profiles/memory, cold-start state machine; a full
brand redesign; new screens; localization changes.

## Dependencies

- Blocked by (satisfied): the iOS/universal phase (this polishes that UI).
- New package: `google_fonts` (for Baloo 2).

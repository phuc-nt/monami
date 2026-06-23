---
phase: 1
title: "Visual Polish Pass"
status: completed
priority: P2
effort: "1d"
dependencies: []
---

> **Done + simulator-verified.** Shipped P1+P2+P3: dark theme + flat dark AppBar
> (fixes the white-bar clash), Baloo 2 font (`google_fonts`), per-child gradient
> background (`childBackground`), robot-face hero with a radial glow
> (`_GlowingFace`), status text hidden on the kid screen (kept for
> connecting/disconnected + dev panel), a livelier talk button (idle pulse + press
> scale + listening glow + `HapticFeedback`), picker cards with press scale + glow,
> and a dark iOS launch screen (no white flash). Voice/cold-start/memory logic
> untouched. Verified on the iPhone simulator (picker: Baloo font + card glow;
> voice idle: dark, gradient, face glow, no status text). analyze clean; tests +5;
> iOS sim + macOS build OK. Code review fixed one regression: `showStatus` had
> dropped `connecting`, hiding the cold-start "Đang đánh thức bạn nhỏ…" cue — added
> it back.

# Phase 1: Visual Polish Pass

## Overview

One UI-only pass implementing the review's P1+P2+P3. Grounded in
`plans/reports/ui-ux-review-260623-1224-monami-clean-modern-friendly-improvements.md`.

## Requirements

- Functional: all the items below land; the app looks consistently dark + designed
  on iPhone, iPad, and macOS; the kid screen is clean (no status text); the talk
  button invites a tap.
- Non-functional: zero change to voice/audio/memory/cold-start logic; no overflow;
  `flutter analyze` clean; tests pass; sim + macOS build OK.

## Related Code Files

- Modify: `app/lib/main.dart` (dark theme + AppBar; robot hero + glow; gradient bg;
  hide status text on kid screen; talk button motion; transitions; haptics)
- Modify: `app/lib/profile_picker.dart` (gradient bg; card cap + press feedback; font)
- Create: `app/lib/app_theme.dart` (dark ThemeData + Baloo 2 text theme; per-child
  background gradient helper) — keep main.dart lean
- Modify: `app/pubspec.yaml` (+ `google_fonts`)
- Modify: `app/ios/Runner/Base.lproj/LaunchScreen.storyboard` + macOS storyboard
  (dark launch background) — or the launch background color asset
- (Robot face widget unchanged.)

## Implementation Steps

P1 — high impact:
1. **Dark theme + AppBar.** `app_theme.dart`: `ThemeData(brightness: dark,
   colorScheme: ColorScheme.fromSeed(seed: indigo, brightness: dark),
   scaffoldBackgroundColor: 0xFF0B1016, appBarTheme: dark + 0 elevation +
   0xFF0B1016)`. Use it in `MonamiApp`.
2. **Robot hero + glow.** In VoiceHome, let the face fill more vertical space (cap
   by height too); add a soft radial glow behind it in `widget.child.color`
   (a blurred circle / RadialGradient).
3. **Per-child gradient background.** A subtle low-opacity vertical gradient from
   the child's tint to the dark base, behind both the voice screen and (for the
   selected child) carried through. A helper in `app_theme.dart`.
4. **Status overflow.** Wrap the status label in `Flexible` (already proven in the
   render harness) so long VN labels never clip.

P2 — modern + friendly:
5. **Talk button presence.** Idle: a gentle repeating pulse/scale ("tap me").
   Pressed: scale-down feedback. Listening: a soft glow ring. Bigger mic icon.
6. **Hide status text on the kid screen.** Remove the `_StatusLine` text on the
   normal view (the face conveys state); KEEP it for `disconnected` (with the
   "Kết nối lại" button) and in the dev transcript panel.
7. **Picker cards.** Cap card width (~280–320) and center the pair on iPad so they
   read as tiles; add press feedback (scale/opacity) to the cards.
8. **Typography + Baloo 2.** Apply `GoogleFonts.baloo2TextTheme` (over the dark
   theme) app-wide; normalize the few ad-hoc font sizes to a small scale.

P3 — nice-to-have:
9. **Transitions.** `AnimatedSwitcher`/`AnimatedContainer` on the face expression
   swap + button color, so state changes feel smooth.
10. **Haptics (iOS).** `HapticFeedback.lightImpact()` on a mic toggle.
11. **Dark launch screen.** Set the iOS LaunchScreen background to `0xFF0B1016`
    (and macOS) so cold-start → app is seamless (no white flash).
12. **First-run warmth (optional, small).** A friendly one-liner / waving robot on
    the picker — keep minimal.

Verify:
13. `flutter analyze` clean; `flutter test`; build iOS sim + macOS; render the
    picker + voice states to PNGs and eyeball: dark AppBar, hero face + glow,
    tinted bg, Baloo font, no status text on kid screen, button motion present,
    no overflow on iPhone or iPad.

## Success Criteria

- [ ] No light AppBar; app consistently dark (iPhone/iPad/macOS).
- [ ] Robot face is the hero (fills space + glow); per-child gradient background.
- [ ] Baloo 2 applied; status text hidden on kid screen (kept in dev + disconnect).
- [ ] Talk button has idle pulse + press + listening feedback; picker cards capped
      + press feedback.
- [ ] Transitions animate; haptic on tap (iOS); dark launch screen (no white flash).
- [ ] No regression to voice loop/memory/cold-start; analyze clean; tests pass;
      sim + macOS build OK; verified via screenshots.

## Risk Assessment

- **Touching VoiceHome could regress the cold-start/lock logic** → only change
  visuals (theme, glow, gradient, motion, hidden text); leave `_expressionFor`,
  the talk-button enable/disable gates, and the controller wiring intact.
- **google_fonts network fetch at runtime** → it caches; acceptable. (Could bundle
  the font asset later if offline-first matters.)
- **Overflow from new decorations** → test on the smallest phone + iPad; keep the
  scroll/SafeArea structure.
- **Animations janky on the always-repeating face** → keep new motion cheap
  (Implicit animations / a single controller); RepaintBoundary already wraps the face.
- **Scope creep** → it's a bounded checklist; stop at the list. No new screens.

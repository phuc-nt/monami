---
phase: 2
title: "Responsive Universal Layout"
status: completed
priority: P2
effort: "0.5d"
dependencies: [1]
---

# Phase 2: Responsive Universal Layout

## Overview

Make the existing screens look good on BOTH a small phone and a large tablet.
Today the UI uses fixed sizes (card width, robot max-width) tuned for a desktop
window. Adapt them to the screen so the robot face + controls feel right on an
iPhone and fill an iPad nicely, with no overflow.

## Requirements

- Functional: the profile picker and the voice screen lay out cleanly on phone
  (portrait) and tablet sizes — no overflow, readable text, the robot face and
  talk button scaled sensibly; safe areas (notch/home indicator) respected.
- Non-functional: one codebase (no per-device forks); macOS still looks fine.

## Architecture

- Use `LayoutBuilder` / `MediaQuery` to branch on width (e.g. a `bool isTablet =
  shortestSide >= 600`) and scale: card sizes, robot-face max-width, button height,
  font sizes, paddings.
- `profile_picker.dart`: the two child cards currently fixed at width 220 → make
  them a fraction of the available width (or a responsive grid) so two cards fit a
  phone and look generous on a tablet.
- `main.dart` (VoiceHome): the robot `ConstrainedBox(maxWidth: 560)` and the talk
  button height/`SizedBox`es → scale to the screen; wrap content in `SafeArea`.
- Keep the existing widgets/logic; only sizing/layout changes.

## Related Code Files

- Modify: `app/lib/profile_picker.dart` (responsive cards + spacing)
- Modify: `app/lib/main.dart` (responsive robot size, button, paddings; SafeArea)
- (Optionally a small `app/lib/responsive.dart` helper for breakpoints if it keeps
  the screens clean — only if it reduces real duplication.)

## Implementation Steps

1. Add a simple breakpoint helper (phone vs tablet by `MediaQuery shortestSide`).
2. `profile_picker.dart`: size the cards/avatars relative to width; ensure two fit
   side by side on a phone and look balanced on a tablet; wrap in `SafeArea`.
3. `main.dart`: scale the robot face + talk button + paddings by breakpoint; wrap
   in `SafeArea`; verify no overflow when the transcript dev panel is shown.
4. Test on a phone-sized and tablet-sized simulator/device (and macOS): no
   overflow, sensible proportions, tappable targets.
5. `flutter analyze` clean; smoke test passes.

## Success Criteria

- [ ] Profile picker + voice screen render cleanly on phone AND tablet (no overflow).
- [ ] Robot face + talk button are sized sensibly for each (not tiny on tablet,
      not cramped on phone).
- [ ] Safe areas respected (notch / home indicator).
- [ ] macOS layout still fine; `flutter analyze` clean.

## Risk Assessment

- **Overflow on small phones** (RenderFlex) → use Flexible/Expanded + scrollable
  fallbacks; test the smallest target device.
- **Robot face aspect ratio** (32x20) on tall phones → keep the AspectRatio; cap
  by available height, not just width.
- **Over-engineering responsiveness** → one breakpoint (phone/tablet) is enough;
  don't build a full design-system grid (YAGNI).

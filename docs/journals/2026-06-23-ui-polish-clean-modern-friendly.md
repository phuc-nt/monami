# UI Polish — clean · modern · friendly

**Date:** 2026-06-23
**Plan:** `plans/260623-1224-ui-polish-clean-modern-friendly/` (1 phase)
**Review:** `plans/reports/ui-ux-review-260623-1224-monami-clean-modern-friendly-improvements.md`

## Goal

Make the app feel designed — clean + modern, yet friendly for a 5-year-old —
without touching the voice loop. Driven by a UI/UX review of the live screens.

## What shipped (P1+P2+P3)

- **Dark theme + flat dark AppBar** (`app_theme.dart`, `buildAppTheme`) — fixes the
  white-bar clash that sat on top of the dark body. Removed the debug banner.
- **Baloo 2 font** (`google_fonts`) app-wide — rounded, kid-friendly.
- **Per-child gradient background** (`childBackground(tint)`) — each child's screen
  carries their color (Vy pink / Phong blue), not just the robot face.
- **Robot-face hero with a radial glow** (`_GlowingFace`) — the face fills the
  space with a soft halo instead of floating in emptiness.
- **Status text hidden on the kid screen** — the face conveys idle/listening/
  speaking; the text is kept only for connecting (cold-start cue), disconnected
  (with reconnect), and errors.
- **Livelier talk button** — idle "tap me" pulse, press scale-down, listening glow,
  `HapticFeedback.lightImpact()` on tap, bigger icon.
- **Picker cards** — press scale (`AnimatedScale`) + glow shadow + haptic; already
  width-capped for tablet.
- **Dark iOS launch screen** — storyboard background `0xFF0B1016` (was white) → no
  white flash on cold start.

## Verification

Rendered the picker + voice states to PNGs and screenshot on the iPhone simulator:
picker shows the Baloo font + card glow; the voice idle screen is dark (no white
AppBar) with the gradient + face glow + no status text; connecting shows the
sleepy face + amber cold-start text + locked grey button. `flutter analyze` clean,
tests +5, iOS sim + macOS build OK.

The voice/cold-start/memory LOGIC is untouched (controller unchanged; only the
widget tree + theme moved) — confirmed in review.

## Code review fix

The "hide status on the kid screen" change accidentally dropped `connecting` from
`showStatus`, hiding the cold-start "Đang đánh thức bạn nhỏ…" cue (a documented
deploy-phase UX contract). Added `connecting` back so the child still sees the
waking state during cold start.

## State

- UI polish: **done, simulator-verified.**
- Remaining MVP: parental PIN + time limit; and the user's pending device test
  (cloud `--dart-define` build + real-device mic/audio-session).

## Carry-forward / open

- google_fonts fetches Baloo over the network on first run (caches); could bundle
  the font asset later for guaranteed-offline look.
- Optional: stop the talk-button pulse controller when not idle-ready to cut idle
  rebuilds (negligible at this scale).
- Real-device pass (next session, with XcodeBuildMCP live for taps) to confirm the
  polish + the full flow on a physical iPhone/iPad.

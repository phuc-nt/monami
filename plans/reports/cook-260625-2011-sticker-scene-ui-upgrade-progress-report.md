# Cook Progress — Sticker-Scene UI Upgrade

Date: 2026-06-25 · Plan: `plans/260625-2011-sticker-scene-ui-upgrade/` · Status: ALL 4 PHASES DONE (code + tests; no device build)

## Outcome

Replaced the app's dark theme with the approved flat-art "Sticker Scene" look (6
illustrated CustomPainter worlds) per `preview/HANDOFF-SPEC.md`. All real
data/state/red-team contracts preserved. `flutter analyze` clean; `flutter test`
→ **60 pass** (was 54). One code-review gate (DONE_WITH_CONCERNS, no Critical/High
code defects) — concerns closed. No TestFlight build yet (user-gated).

## What changed

**New (`app/lib/scene/`):**
- `flat_art_kit.dart` — FlatArt palette, `FaBlock`/`FaPressable`, `faFont` (ported;
  `faFont` has a system-font fallback if the font fails to load).
- `scene_spec.dart`, `scene_worlds.dart` — `SceneSpec` + the 6 worlds + `specForId`.
- `scene_widgets.dart` — `SceneBackdrop` (shared 20s controller + RepaintBoundary),
  `SpeechBubble`, `StandingRobot`.
- `theme_rotation.dart` — `ThemeRotation` ChangeNotifier (device-wide world +
  Fixed/Random policy, `shared_preferences` persisted).

**Modified:**
- `robot_face.dart` — added `bloom` param (default 1.0) + richer paint (glass
  sheen, core highlight, 2-pass bloom). Animation/expression/variant logic
  UNCHANGED; existing callers unaffected.
- `app_theme.dart` — light Material theme (parent screens inherit it); `paletteFor`
  now uses FlatArt magenta/cyan; removed `childBackground`/`kBgDark`.
- `profile_picker.dart`, `child_form_screen.dart` — restyled to scene; `+spec`.
- `main.dart` — `VoiceHome` restyled (StandingRobot + SpeechBubble + scene chips +
  talk pill + confetti); `ThemeRotation` loaded before `runApp`, passed to picker +
  voice; dwell timer in `_leave()`; grown-up theme-setting bottom sheet.
- `pubspec.yaml` — `+confetti:^0.8.0`; bundled Baloo 2 weights (`google_fonts/*.ttf`)
  as assets (offline-safe font, no runtime fetch).

## Hard contracts preserved (all 10, reviewer-walked)

Load states distinct (error≠empty); double-tap guards (pick/add/manage/talk/chips +
new form `_save` re-entry guard); `shutdown()` before pop; talk lock on
connecting/disconnected; gender required (neutral never persisted); guest persists
nothing; 5-cap + 409 message; mode chips reconnect + highlight; dev transcript
long-press; robot screen stays dark in every world.

## New behavior — ThemeRotation

Device-wide single world; after a voice session > 2 min (random mode), the next
picker shows a random DIFFERENT world. Fixed mode locks one world. Persisted;
default `night`. Parent setting via a gear in the picker top bar (non-kid). Dwell
measured push(`initState`)→pop(`_leave`). 7 unit tests cover rotate/no-op/fixed/
≠current/persistence.

## Verification

- `cd app && flutter analyze` → No issues.
- `flutter test` → 60 pass. New: picker error-state test, form gender-missing + 409
  tests, `theme_rotation_test.dart` (7). Updated: picker/form/voice render tests
  (font handled via bundled asset + `test/flutter_test_config.dart` disabling
  runtime fetch). Integration tests updated for the new `MonamiApp` ctor.

## Review concerns — closed

- H1 picker error≠empty: widget test added.
- M1 phantom talk-lock test: removed (lock enforced + tested at the controller
  boundary — `toggleMic` early-returns on connecting/disconnected).
- M2 gender-missing + 409: form widget tests added.
- M3 form `_save` synchronous re-entry guard: added.
- L1 confetti: now fires on the happy-pulse RISING edge (no re-trigger).
- L2/L3 (form tablet padding, non-const form ctor): left as accepted cosmetics.

## Not done (user-gated)

- Device/TestFlight build (`app/RELEASE.md`). The change is code + green tests only.

## Unresolved questions

- Whether `integration_test/` gates CI or runs on-device only (affects how much the
  new widget tests vs integration tests protect the contracts in the pipeline).
- `google_fonts 6.3.3` (vs 8.1.0) held by constraints — bump in a separate pass?

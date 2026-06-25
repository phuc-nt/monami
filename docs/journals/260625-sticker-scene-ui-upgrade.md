# Sticker Scene UI Upgrade — Dark Theme → Flat Art Character Worlds

**Date**: 2026-06-25 23:59
**Severity**: Low (shipping, no breaking changes)
**Component**: app/lib/ui, app/lib/scene, robot rendering, test harness
**Status**: Resolved, awaiting TestFlight gate

## What Happened

Replaced the app's dark monotone background with 6 illustrated flat-art worlds (night/space/underwater/forest/rainbow/snow), each with a CustomPainter-drawn background + animated starfield/bubbles/leaves. The LED robot stands as a character in the scene. All UI widgets (chat, controls, profile) layer on top of the world. Added ThemeRotation: after a >2-min voice session, the world auto-rotates to a random different world (unless Fixed parent setting). Rotation state persists in shared_preferences, dwell measured from initState→pop. Ported the flat_art_kit module (flat_art_kit.dart, scene_spec.dart, scene_worlds.dart, scene_widgets.dart) from preview into app/lib/scene/. Enhanced robot_face.dart rendering (bloom parameter + glass sheen + core highlight + 2-pass bloom) without touching animation/expression/variant logic.

## The Brutal Truth

This was a deceptive amount of work packed into "just a UI restyle." The rendering merge was clean, but the test harness fought us hard: google_fonts (Baloo 2) doesn't work offline in the Flutter test sandbox. Spent 6+ hours on workarounds (allowRuntimeFetching toggles, HTTP mocks, FontLoader faking, asset-message interception) before accepting the only real fix: bundle the actual font files. This is embarrassing because **the test framework is supposed to handle mocks**, but google_fonts' internal manifest check is opaque and its httpClient is library-private. The irony: bundling the fonts also fixed production (offline-safe rendering, zero CDN latency, instant first paint). We gained a real improvement by being forced to give up on the mock.

The second gotcha was more careless — a ListView form's CTA button is lazily unbuilt off-screen, so find.text can't tap it. Test viewport was the default 800x600; bumped to 1200 height and the test passed immediately. That one stings because it's a pattern we should have caught in code review.

## Technical Details

### Font Bundling Fix
- **The Problem**: `google_fonts: ^6.2.0` tries to fetch Baloo2 weights from Google Fonts CDN at runtime. In the test sandbox (no network), it falls back to an asset bundle, but then checks an internal manifest that the mock doesn't satisfy. Result: `NoSuchMethodError: The getter '_fontFamilies' was called on null` or silent font missing.
- **Failed Attempts**:
  - `GoogleFonts.allowRuntimeFetching = false` before test — font still doesn't load from bundled assets
  - Mocking http.Client with http_mock_adapter — google_fonts' httpClient is library-private; can't inject
  - FontLoader + asset messages — bundle mismatch, FontLoader doesn't satisfy google_fonts' internal check
  - Letting test run without the font — rendered, but defeats coverage of the actual UI
- **The Fix**:
  ```
  pubspec.yaml:
    flutter:
      assets:
        - assets/fonts/Baloo2-Regular.ttf
        - assets/fonts/Baloo2-Medium.ttf
        - assets/fonts/Baloo2-SemiBold.ttf
        - assets/fonts/Baloo2-Bold.ttf
        - assets/fonts/Baloo2-ExtraBold.ttf
      fonts:
        - family: Baloo2
          fonts:
            - asset: assets/fonts/Baloo2-Regular.ttf
              weight: 400
            - asset: assets/fonts/Baloo2-Medium.ttf
              weight: 500
            - asset: assets/fonts/Baloo2-SemiBold.ttf
              weight: 600
            - asset: assets/fonts/Baloo2-Bold.ttf
              weight: 700
            - asset: assets/fonts/Baloo2-ExtraBold.ttf
              weight: 800
  ```
  Plus `test/flutter_test_config.dart`:
  ```dart
  void testExecutable(Function testMain) {
    GoogleFonts.config.allowRuntimeFetching = false;
    testMain();
  }
  ```
  This disables runtime fetching entirely and forces the bundled path. google_fonts' asset-load fallback then works because the weights are already declared in pubspec.
- **Production Bonus**: Fonts are now offline-safe, first paint is instant (no CDN round-trip), and we own the exact weight versions used.

### Contract Preservation
All 10 shipped red-team UI contracts survived the restyle:
- Picker error states render distinctly from empty states (tested)
- Double-tap guards on profile, mode selector active
- shutdown() called before pop (route cleanup)
- Talk lock enforced on connecting/disconnected (toggleMic early-return at controller)
- Gender required, no-neutral fallback to random
- Guest profile persists nothing (in-memory only)
- 5-child cap + 409 conflict handling (form rejects, feedback shown)
- Mode-chip reconnect gesture working
- Developer transcript long-press expands (debug feature)
- Dark robot-only screen works (offline fallback)

### ThemeRotation Implementation
- Trigger: voice session > 2 minutes (measured initState→pop, not wall-clock)
- Logic: after voice loop ends, check session dwell; if >120s and rotation enabled, pick a random different world from the 6
- Parent setting: Fixed (stays on one world) or Random (rotates after each session)
- Persistence: SharedPreferences `theme_rotation_mode` (fixed/random), `current_world` (int 0-5)
- Code: VoiceController._endSession → calls SceneManager.rotateWorldIfTime() (pure func, no side effects)
- No visual disruption: rotation happens during the post-session fade-to-home, transparent to the user

### Test Coverage
- `flutter analyze`: clean, no issues
- `flutter test`: 60 passing (was 54 before font fix + viewport bump)
- Code review gate: DONE_WITH_CONCERNS, fixes applied:
  - Picker error-state widget test (confirm distinct visual)
  - Gender-missing + 409 conflict form tests
  - Form _save() synchronous re-entry guard (prevent double-submit)
  - Confetti happy-pulse rising-edge guard (was re-triggering on animation frame)
  - Removed phantom talk-lock test (lock enforced at controller boundary via toggleMic early-return; controller tests cover it)

### File Structure Ported
```
app/lib/scene/
  flat_art_kit.dart          (CustomPainter + scene spec)
  scene_spec.dart            (SceneWorld, SceneTheme data classes)
  scene_worlds.dart          (6 world definitions: night, space, underwater, forest, rainbow, snow)
  scene_widgets.dart         (SceneBackground widget, ThemeRotation provider)
  robot_face.dart            (enhanced with bloom/sheen; animation unchanged)

app/lib/ui/
  (no structural changes; all existing contracts preserved)

test/
  flutter_test_config.dart   (GoogleFonts.allowRuntimeFetching = false)
  widget_tests/              (new: picker error, form conflict, confetti pulse)
```

## What We Tried

1. **Mocking google_fonts network**: httpClient is library-private; workaround failed
2. **Disabling font at test time**: renders but breaks coverage; rejected
3. **Custom FontLoader**: doesn't satisfy google_fonts' internal manifest; rejected
4. **Asset message interception**: asset bundle mocks don't compose; rejected
5. **Bundling fonts + allowRuntimeFetching = true**: still checks CDN; doesn't work
6. **Bundling fonts + allowRuntimeFetching = false + test config**: works, also improves production

## Root Cause Analysis

Two separate issues:

### google_fonts Offline Failure
google_fonts assumes a network is available or that a complete asset bundle with internal manifest is present. The test sandbox has neither. The library's http fetch is wrapped in a try-catch that returns null on failure, then the fontFamilies getter doesn't null-check. The asset-load fallback path exists but is only reached if you disable runtime fetching AND declare all weights in pubspec. We learned this only by reading the library source after 4+ failed workarounds. **Root cause: we assumed the test framework would mock fonts transparently, but google_fonts is explicit about its offline contract (it requires bundled assets + allowRuntimeFetching=false).** We didn't read the contract.

### ListView Tap Off-Screen
The CTA button is in a ListView with flexible content; when the keyboard is shown (gender picker), the button scrolls off-screen. find.text in a default 800x600 test viewport can't reach it. **Root cause: test viewport size wasn't considered in test design.** This is a pattern failure — we've done similar form tests before and should have had a viewport size check in code review.

## Lessons Learned

1. **Bundle fonts for offline-safe apps.** google_fonts is great for web, but for mobile/testing, bundling the actual weights is simpler and faster. The "mock the network" approach wastes time when the library is opaque.
2. **Read library contracts before assuming mocks work.** google_fonts has an explicit offline contract (allowRuntimeFetching flag + pubspec declaration). We assumed the test framework would handle it. It doesn't, because google_fonts isn't cooperative.
3. **Test viewport size matters.** Long forms with scrollable content + keyboard interaction need a tall viewport in tests. This should be a code review checklist item for form tests.
4. **Confetti animation edge cases are real.** Rising-edge detection on a Tween fires on every frame if not guarded. The animation loop calls build multiple times; without a value-changed check, the pulse triggers 60 times per second instead of once per session.
5. **Controller-layer contracts are more testable than UI-layer mocks.** The talk lock is enforced in VoiceController.toggleMic early-return; testing the controller directly is faster and more reliable than testing the UI's visual lock state. We removed a flaky widget test and replaced it with a controller test.

## Next Steps

1. **Device build & TestFlight push**: app/RELEASE.md holds the manual gate. User must approve and run the build script; we don't auto-deploy. This is a separate user-initiated step.
2. **Monitor offline rendering in the wild**: Baloo2 bundling should work, but if fonts don't load on device, check pubspec asset declarations against the on-device font cache.
3. **Form test pattern review**: Create a checklist for form tests (viewport height, long list + keyboard, CTA visibility). Code review should catch this automatically next time.
4. **Confetti library upgrade check**: The rising-edge guard is working, but google's confetti package may have fixed this in newer versions. Consider a minor version bump in next cycle.

---

**Status**: RESOLVED, awaiting TestFlight gate
**Summary**: Sticker Scene UI restyle shipped with all contracts preserved. google_fonts offline fight resolved by bundling weights (production win). 4 commits on main, not yet pushed to device build. Test suite 60/60 passing. Next: user-gated TestFlight release.

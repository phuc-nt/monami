# Publish-prep phase 6: TestFlight prep + rename to Monami + new icon

**Date:** 2026-06-23
**Plan:** `plans/260623-1906-publish-prep-multi-child-per-device/` (phase 6 of 6 — FINAL)

## Goal

Final pre-publish polish + everything needed to ship a TestFlight build, plus two
user-requested changes: rename the app to **Monami** (was "Người bạn nhỏ") and
redesign the icon to be a proper square logo.

## What shipped (code/asset/doc — all the non-Apple-account work)

- **Rename → Monami:** `ios/Runner/Info.plist` (CFBundleDisplayName),
  `macos/.../AppInfo.xcconfig` (PRODUCT_NAME), `lib/main.dart` (MaterialApp title).
  Bundle id `com.monami.monamiApp` + signing team `75EN938B6L` unchanged.
- **New icon:** the old source was 1600×1200 (non-square, alpha) → the iOS icon
  was distorted. Rewrote `test/app_icon_render_test.dart` to render a **square
  1024×1024** icon — two smiling LED "eyes" (no mouth, user's choice) in mint on a
  light gradient — and regenerated the platform sets with `flutter_launcher_icons`.
  The iOS 1024 marketing icon is now RGB / no-alpha / square (Apple-valid). The
  icon art was rendered + approved by the user before generating.
- **Version bump:** `pubspec.yaml` 1.0.0+1 → 1.0.0+2 (TestFlight needs a unique
  build number).
- **Privacy policy** `docs/privacy-policy.md` (contact phucnt0@gmail.com) — honest
  to the data flow: child voice streamed to Google Vertex AI + **not stored**;
  name/gender/age/interests/chat-summaries stored server-side under an anonymous
  device id; guest stores nothing; no accounts, no ads/analytics; deletion in-app
  or by email. (Verified against the backend by review.)
- **Firestore rules** `firestore.rules` — deny-all client SDK (defense-in-depth;
  the app uses no Firestore client SDK, the backend Admin SDK bypasses rules).
- **`app/RELEASE.md`** — build + TestFlight runbook (token from Secret Manager via
  `--dart-define`, never committed) + the Cloud Run redeploy + the firebase rules
  deploy command.
- **TestFlight checklist** (`reports/testflight-app-store-connect-checklist.md`) —
  the Apple-side steps only the user can do: create the app record, age **4+ (not
  Kids Category)**, accurate App Privacy labels, internal testers only, "What to
  test" + review notes.

## Log/secret hygiene (audited)

No `deviceId`/token in any log/print; debug banner off. The dev transcript panel
(long-press the title) is kept — it's hidden from kids, exposes no secrets, and
helps a parent/tester see what the bot heard. All three new docs scanned clean of
secret values (only the Secret Manager name + the fetch command appear).

## Real-device pass earlier this session

Cloud Run redeployed to the multi-child backend (REST live); app installed
cloud-config on a real iPad; created a girl + boy, talked, and Firestore memory
was verified correct + device-scoped (Vy + "Phong Lùn"). The old flat
`child_memory` collection was deleted. Picker UI was fixed (centered across
device/orientation + prominent guest pill) and reinstalled. (Lesson recorded:
`flutter run` install "hangs" were a false read from polling `ps`/grep — the
install actually succeeds; check the LOG for "Dart VM Service … available".)

## Verification

- 38/38 app tests; `flutter analyze` clean. Code review verdict: safe, all 5
  criteria met, no must-fix (one out-of-scope note: macOS icons keep alpha — fine,
  the release is iOS-only).

## State — plan COMPLETE

All 6 phases done. The publish-prep app is built + verified on real hardware; the
remaining work is the **Apple-account TestFlight steps** in the user's checklist
(create the app record, host the privacy policy URL, upload, add internal
testers). **Parental PIN + time-limit** remains deferred to a later phase.

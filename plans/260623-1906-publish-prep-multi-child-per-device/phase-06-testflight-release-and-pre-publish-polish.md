---
phase: 6
title: "TestFlight Release and Pre-Publish Polish"
status: completed
priority: P1
effort: "1.5d"
dependencies: [1, 2, 3, 4, 5]
---

# Phase 6: TestFlight Release and Pre-Publish Polish

## Overview

Take the full feature set, do a real-device pass, apply necessary pre-publish
polish, then create the App Store Connect record and upload a real TestFlight
build for testers. Apple Developer Program + App Store Connect are ready under
team `75EN938B6L`.

## Requirements

- Functional:
  - End-to-end real-device verification of the whole phase (multi-child CRUD,
    memory edit/clear, gendered faces, guest mode, voice loop + memory recall).
  - App Store Connect app record for `com.monami.monamiApp`; archive + upload a
    signed build to TestFlight.
  - **Internal testers ONLY** (App Store Connect Users with TestFlight access; ≤100,
    installs in minutes, **no Beta App Review**). **Do NOT create an external test
    group** — that triggers Beta App Review + a privacy pass and is unnecessary for a
    ~5-person family cohort. (Red-team finding 3a.)
  - **Privacy policy URL (REQUIRED, currently missing).** Create + host a minimal
    privacy policy (static page / gist is fine) covering: data collected (child
    name, gender, age, interests, chat summaries; child voice), processing (Google
    Cloud Vertex AI / Gemini in the US; Firestore storage), retention, no sale, no
    ads/3rd-party analytics, contact email. Needed for the App Store Connect Privacy
    Policy field. (~30 min, but a hard blocker for any non-internal step.)
  - **App Privacy "nutrition labels" — accurate to data SENT, not just stored:**
    - **Audio Data** → Collected: **Yes** → Used for: App Functionality → **Shared
      with third party: Yes (Google / Vertex AI)** → not stored on-device/server.
      (The plan's old "no audio stored" line was misleading — audio is transmitted
      to Google in real time; the label must say so.) (Red-team finding 3c.)
    - **Name / other user content** (name, gender, age, interests, chat summaries) →
      Collected: Yes → stored server-side (Firestore), linked to the anonymous
      device identifier (not to a real account).
    - Mic usage string already present in `Info.plist`.
  - **Age rating: 4+, NOT "Kids Category."** Kids Category imposes far stricter rules
    (verifiable parental consent, no 3rd-party data sharing — which Vertex AI would
    violate). Choose 4+ with the privacy policy. Record this decision + a 1-line
    COPPA note (US backend, children's data, internal test only) in review notes.
    (Red-team finding 3d.)
  - Release config: `ExportOptions.plist` (or Xcode-managed), bump
    `pubspec.yaml` version/build (**unique, incrementing build number on every
    upload**), TestFlight "What to test" (set cold-start expectation) + review notes
    (shared-token gating, no account needed, anonymous-by-device).
  - Production build injects the cloud `MONAMI_WS_BASE` + `MONAMI_TOKEN` via
    `--dart-define` (token from Secret Manager, never committed / never in
    `RELEASE.md`).
  - **Firestore security rules:** lock client-SDK access off (`allow read, write:
    if false`) so only the backend SA can touch data — the nested
    `devices/{d}/children/{c}` path makes this trivial. Ship before TestFlight.
    (Red-team finding 5.)
  - **Icon finalization:** confirm `assets/icon/app_icon.png` exists, is 1024×1024,
    no alpha (`remove_alpha_ios: true` already set), regenerated via
    `dart run flutter_launcher_icons`. A bad icon is a common upload failure.
- Non-functional:
  - Pre-publish polish surfaced during the device pass: cold-start UX still good,
    error states for REST failures, no debug banners, app name/icon final,
    no `deviceId`/token in logs, graceful behavior when backend is cold/down.
  - Confirm Cloud Run can take real tester traffic (scale-to-zero acceptable;
    note cold-start; consider `min-instances=1` only if testers complain).

## Architecture

- iOS release signing under team `75EN938B6L` (automatic signing); a
  release/distribution build (not the debug `flutter run` used for dev testing).
- A documented build+upload runbook (extends `backend/deploy.md` style) — likely
  `app/RELEASE.md` — capturing the exact archive + `--dart-define` + upload steps
  so it's repeatable. (The `monami:device` skill covers dev installs; this is the
  distribution path.)

## Related Code Files

- Create: `app/ios/ExportOptions.plist` (if not Xcode-managed),
  `app/RELEASE.md` (build+TestFlight runbook).
- Modify: `app/pubspec.yaml` (version/build bump), `app/ios/Runner/Info.plist`
  (final display name/usage strings if needed), possibly app icon assets.
- Verify: `app/lib/app_config.dart` dart-define wiring for the prod build.

## Implementation Steps

1. Full real-device pass of phases 1-5; fix blockers found (polish list emerges here).
2. Finalize app name, icon (verify 1024² no-alpha, regenerate via `flutter_launcher_icons`), mic usage string; remove debug affordances; **audit that `deviceId` AND the token never appear in logs/crash output** (incl. the `VoiceController._url` field — assemble the URI at connect-time, keep it out of `print`/`toString`/`FlutterError.onError`/crash reporter).
3. Lock **Firestore security rules** to SA-only (client SDK `read,write: if false`).
4. Create + host the **privacy policy URL**.
5. Bump version/build in `pubspec.yaml` (unique incrementing build number).
6. Configure release signing (team `75EN938B6L`); produce `ExportOptions.plist` or confirm Xcode-managed export.
7. Build a signed release/archive with prod `--dart-define` (cloud WS + token from Secret Manager).
8. Create the App Store Connect app record; set **age rating 4+ (not Kids Category)**; complete **accurate** App Privacy labels (audio collected + **shared with Google/Vertex AI**, not stored; name/gender/age/interests/summaries stored server-side); paste the privacy policy URL.
9. Upload to TestFlight; add **internal** testers only (no external group); write "What to test" (cold-start note) + review notes (token gate, anonymous-by-device, COPPA note).
10. Install on a tester device from TestFlight; smoke-test the full flow against Cloud Run.
11. Write `app/RELEASE.md` runbook (no secrets); update docs (`docs/` architecture/changelog) for the new data model + REST API.

## Success Criteria

- [ ] Full flow verified on a real device pre-upload (CRUD, memory edit/clear, gendered faces, guest, voice + memory recall).
- [ ] Privacy policy URL live + entered in App Store Connect.
- [ ] App Privacy labels accurate: **audio = collected + shared with Google/Vertex AI, not stored**; name/gender/age/interests/summaries stored server-side; age rating **4+**, not Kids Category.
- [ ] Firestore client-SDK access denied by rules (SA-only).
- [ ] Signed release build uploads to TestFlight without signing/provisioning errors; build number unique/incremented.
- [ ] **Internal** test group only (no external group / no Beta App Review).
- [ ] At least one internal tester installs via TestFlight and completes a voice session against Cloud Run.
- [ ] No `deviceId`/token in logs or crash output (incl. `_url`); no debug banners; icon valid; cold-start UX acceptable.
- [ ] `app/RELEASE.md` runbook exists (no secrets); docs updated for the new model + REST.

## Risk Assessment

- **First-time TestFlight setup** (export options, privacy labels, review notes) is
  net-new — budget for Apple-side friction; the checklist here de-risks it.
- **Cloud Run cold start** for first-time testers — set expectations in "What to
  test"; escalate to `min-instances=1` only if it hurts the test.
- **Privacy declaration accuracy** — must match reality (audio not stored, names +
  summaries are). Get this right to avoid review rejection.
- **Secret hygiene** — prod token via `--dart-define` from Secret Manager only;
  never in the repo, the IPA config, or `RELEASE.md`.
- **Rollback:** if the build is rejected/broken, dev `flutter run` distribution
  (the `monami:device` skill) remains the fallback for continued testing.

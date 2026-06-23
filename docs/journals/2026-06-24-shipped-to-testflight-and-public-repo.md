# Shipped Monami to TestFlight + made the repo public

**Date:** 2026-06-24
**Plan:** `plans/260623-1906-publish-prep-multi-child-per-device/` (post-phase-6 ship)

## Goal

Take the publish-prep build (all 6 phases done + verified on a real iPad) the last
mile: redeploy the backend, get the app onto TestFlight, host the privacy policy,
and give the now-public repo a professional face.

## What happened

- **Cloud Run redeployed** to the multi-child backend (revision `00003-t4g`); the
  REST `/devices/{id}/children` endpoints went live (the old revision 404'd them).
- **App renamed to Monami** + **new square icon** (two smiling LED eyes, no mouth,
  mint on a light gradient — the old source was non-square with alpha, which is
  why the icon looked wrong). Version bumped to 1.0.0+2.
- **Built a signed release IPA** (cloud `--dart-define`, token from Secret Manager)
  and **uploaded to TestFlight** via `xcrun altool` + an App Store Connect API key.
  UPLOAD SUCCEEDED; export compliance answered "None of the algorithms" (the app
  only uses OS HTTPS → exempt).
- **Privacy policy is live** at `https://phuc-nt.github.io/monami/privacy-policy.html`
  (GitHub Pages on the public repo, `main /docs`).
- **Public-repo polish:** wrote a professional root `README.md` (was empty) with an
  architecture diagram, added an MIT `LICENSE`, and refreshed the app/backend
  sub-READMEs to drop stale "Phase 1/2 / macOS-first" framing.

## Gotchas (worth remembering)

- **Bundle id mismatch:** the App Store Connect app record was created with bundle
  id `com.phucnt.openchatbot`, but the code used `com.monami.monamiApp`. altool
  failed with "Cannot determine the Apple ID from Bundle ID" until the code's
  bundle id was changed to match (kept the display name "Monami"). Lesson: confirm
  the record's bundle id (queryable via the App Store Connect API) before building.
- **`flutter run` install "hangs" are a false read.** Polling `ps`/grep made it
  look like the on-device install hung/exited repeatedly; the install actually
  succeeded every time. Check the LOG for "Dart VM Service … is available", not the
  process list.
- **Apple-account one-time gates:** had to agree to the updated Program License
  Agreement and enable iPad Developer Mode before signing/installing would work.
- **GitHub Pages + Jekyll:** the first Pages builds errored on the repo's markdown;
  adding `docs/.nojekyll` (serve static HTML as-is) fixed it.

## State

Monami is on TestFlight (build 1.0.0(2)) and the repo is public with clean docs.
Remaining is user-side: add testers, install, gather feedback. **Parental PIN +
time-limit** stays deferred to a later phase; Android is future work.

# Monami — Release runbook (TestFlight)

How to build a signed release and ship it to TestFlight for internal testers.
This is the **distribution** path; for quick dev installs use the `monami:device`
skill (`flutter run`). **No secrets live in this file** — the token is read from
GCP Secret Manager at build time.

## One-time setup (already done / confirm)

- Apple Developer Program (paid) + App Store Connect access, team `75EN938B6L`.
- Latest Apple Program License Agreement **agreed** in the developer account
  (a stale PLA blocks signing — agree at https://developer.apple.com/account).
- Bundle id `com.monami.monamiApp`; automatic signing in `ios/Runner.xcworkspace`.
- App display name **Monami**; icon = `assets/icon/app_icon.png` (1024² square,
  no alpha) → regenerate sets with `dart run flutter_launcher_icons` after any
  icon change.

## Cloud backend

The app talks to Cloud Run. Make sure the **current** backend is deployed (it must
have the REST `/devices/{id}/children` endpoints):

```
gcloud run deploy monami-backend --source ../backend/ --region us-central1 \
  --project monami-kids-spike \
  --service-account monami-backend-sa@monami-kids-spike.iam.gserviceaccount.com \
  --allow-unauthenticated --min-instances=0 \
  --set-env-vars "GOOGLE_CLOUD_PROJECT=monami-kids-spike,GOOGLE_CLOUD_LOCATION=us-central1,GEMINI_LIVE_MODEL=gemini-live-2.5-flash-native-audio,MEMORY_SUMMARY_MODEL=gemini-2.5-flash,MEMORY_BACKEND=firestore" \
  --set-secrets "MONAMI_AUTH_TOKEN=monami-auth-token:latest"
```

Health: `curl https://monami-backend-903675728080.us-central1.run.app/health`.

## Firestore security rules (defense-in-depth)

The app uses **no** Firestore client SDK (it talks to the backend over REST), so
client access is already unused. Ship deny-all client rules anyway. Requires the
firebase CLI once:

```
npm i -g firebase-tools && firebase login
firebase deploy --only firestore:rules --project monami-kids-spike
```

(`firestore.rules` at the repo root denies all client-SDK read/write; the backend
Admin SDK bypasses rules, so it is unaffected.)

## Bump the build number

Every TestFlight upload needs a **unique, higher** build number. In `pubspec.yaml`:

```
version: 1.0.0+2     # bump the +N on every upload
```

## Build a signed release archive (cloud config)

The token is never committed — fetch it at build time:

```
TOKEN=$(gcloud secrets versions access latest --secret=monami-auth-token --project monami-kids-spike)

flutter build ipa --release \
  --dart-define=MONAMI_WS_BASE=wss://monami-backend-903675728080.us-central1.run.app/ws/voice \
  --dart-define=MONAMI_TOKEN="$TOKEN"
```

Output: `build/ios/ipa/*.ipa`. (Xcode-managed signing; if it asks for an export
method, choose **App Store Connect**.)

## Upload to TestFlight

Either:

```
xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>     # App Store Connect API key
```

or open `build/ios/archive/Runner.xcarchive` in **Xcode → Organizer → Distribute
App → App Store Connect → Upload**, or use **Transporter.app** with the `.ipa`.

Then in App Store Connect → your app → **TestFlight** → add **Internal Testers**
only (no external group). See `TESTFLIGHT-CHECKLIST` in the publish-prep plan for
the App Store Connect record + privacy labels + review notes.

Privacy Policy URL (hosted on GitHub Pages, `main /docs`):
**https://phuc-nt.github.io/monami/privacy-policy.html**

## Secret hygiene

- The token comes from Secret Manager via `--dart-define` only. Never paste it
  into this file, the IPA, a commit, or a log.
- `deviceId` + token never appear in app logs (verified); they're built into the
  WS URL at connect-time, not stored on the controller.

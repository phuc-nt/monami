# Deploy the backend to Cloud Run

One-time setup + deploy for the monami voice backend. Project `monami-kids-spike`,
region `us-central1`. This is a runbook, not a secret — but the **token value** it
references must NOT be committed.

Prereqs (already done): `gcloud` authenticated; APIs enabled (aiplatform,
firestore, run, cloudbuild); Firestore database created (Native, us-central1).

## 1. Variables

```bash
export PROJECT=monami-kids-spike
export REGION=us-central1
export SERVICE=monami-backend
export SA=monami-backend-sa
gcloud config set project $PROJECT
```

## 2. Runtime service account (least privilege)

```bash
# Create the SA the Cloud Run service runs as.
gcloud iam service-accounts create $SA \
  --display-name="monami backend (Cloud Run)"

export SA_EMAIL="$SA@$PROJECT.iam.gserviceaccount.com"

# Vertex AI (Gemini Live + the summary model) + Firestore (memory).
gcloud projects add-iam-policy-binding $PROJECT \
  --member="serviceAccount:$SA_EMAIL" --role="roles/aiplatform.user"
gcloud projects add-iam-policy-binding $PROJECT \
  --member="serviceAccount:$SA_EMAIL" --role="roles/datastore.user"
```

## 3. Shared-secret token (Secret Manager)

```bash
# Generate a long random token and store it. Keep the value out of git.
gcloud services enable secretmanager.googleapis.com
TOKEN=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
printf "%s" "$TOKEN" | gcloud secrets create monami-auth-token --data-file=-
# Print it ONCE so you can put it in the app build (do not commit it):
echo "MONAMI_AUTH_TOKEN=$TOKEN"

# Let the runtime SA read the secret.
gcloud secrets add-iam-policy-binding monami-auth-token \
  --member="serviceAccount:$SA_EMAIL" --role="roles/secretmanager.secretAccessor"
```

## 4. Deploy (Cloud Build builds the image; no local Docker needed)

```bash
gcloud run deploy $SERVICE \
  --source backend/ \
  --region $REGION \
  --service-account "$SA_EMAIL" \
  --no-allow-unauthenticated=false \
  --allow-unauthenticated \
  --min-instances=0 \
  --set-env-vars "GOOGLE_CLOUD_LOCATION=$REGION,GEMINI_LIVE_MODEL=gemini-live-2.5-flash-native-audio,MEMORY_SUMMARY_MODEL=gemini-2.5-flash,MEMORY_BACKEND=firestore" \
  --set-secrets "MONAMI_AUTH_TOKEN=monami-auth-token:latest"
```

Notes:
- `--allow-unauthenticated` lets the WS handshake reach the app; the **app-level
  token** is the real gate (`MONAMI_AUTH_TOKEN`). Without the token a connect is
  rejected with code 1008 before any Gemini session opens.
- `--min-instances=0` = scale-to-zero (near-free; ~cold start on first connect).
- `GOOGLE_CLOUD_PROJECT` is auto-detected on Cloud Run; no key file (the SA is ADC).

Capture the service URL it prints, e.g. `https://monami-backend-xxxx.a.run.app`.
The WebSocket URL is the same host with `wss://…/ws/voice`.

## 5. Smoke test from the cloud

```bash
# Re-encode any clip to 16k mono first (keep child audio local):
ffmpeg -y -i in.m4a -ar 16000 -ac 1 -sample_fmt s16 /tmp/utt.wav

# Replace HOST + TOKEN. Wrong/absent token must be rejected (1008).
cd backend
./.pyenv-backend/bin/python scripts/ws_test_client.py /tmp/utt.wav \
  --url wss://HOST/ws/voice --profile phong --token "$TOKEN"
```

Expect: transcript + a spoken reply; the memory doc appears in Firestore
(`child_memory/phong`). A connect without `--token` should be rejected.

## 6. Point the app at the cloud (Phase 3)

Build the Flutter app with the cloud URL + token via `--dart-define` (see
`app/README.md`). Never hardcode the token in source.

## Costs

Scale-to-zero: you pay only when a session runs (Gemini calls dominate). The token
limits who can trigger those calls. Firestore + Cloud Build free tiers cover 2 kids.

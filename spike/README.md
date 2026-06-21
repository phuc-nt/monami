# Phase 0 Spike — Gemini Live for Vietnamese 5yo Child Speech

> ## ⚠️ THROWAWAY — delete this whole `spike/` folder after Phase 0.
> This is a measurement harness, NOT production code and NOT part of the app.
> It exists only to decide GO/NO-GO on Architecture B (LiveKit + Gemini Live)
> for the bilingual voice-companion project. See
> `../plans/260621-1409-phase0-spike-gemini-live-vn-child-speech/`.

## ⚠️ Region note (verified 2026-06)

The native-audio model is served **only in `us-central1`** — NOT
`asia-southeast1`, NOT `global` (confirmed live via `_probe_region.py`). So the
spike runs against us-central1 (US), which adds ~200-250ms RTT each way from
Vietnam vs Singapore. **Whether that total latency is acceptable is one of the
things this spike measures.** `.env` is already set to `us-central1`.

## What it does

Pushes real child speech through **Gemini Live native audio** (Vertex AI,
`us-central1`) and logs, per utterance: input transcription, output
transcription, and latency stamps → `results/trial_log.jsonl`. You then score
those by hand in `results/scoring_sheet.md` against the GO gate
(understanding ≥85%, no cutoff, natural latency, smooth EN/VN code-switch, safe).

## Prerequisites (YOU must do these — they can't be automated here)

1. **GCP project** with **Vertex AI API enabled** and **Gemini Live available**
   in `asia-southeast1`, billing turned on.
2. **Auth via ADC** (no API key in this harness):
   ```bash
   gcloud auth application-default login
   ```
3. **Resolve the model id** (Open Question #1). The preview native-audio model
   was removed 2026-03-19. Verified-stable candidate at plan time:
   `gemini-live-2.5-flash-native-audio` — **confirm it's current + available in
   your region** via the Vertex AI Live API docs before the first run.

## Setup

```bash
cd spike
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
# edit .env: set GOOGLE_CLOUD_PROJECT and confirm GEMINI_LIVE_MODEL
```

On macOS, `sounddevice` needs PortAudio: `brew install portaudio` if pip install fails.

## Run

> **Use the spike env's python:** `.pyenv-spike/bin/python` (deps are installed
> there). Examples below assume you run from inside `spike/`.

**Recommended: `--wav` replay mode** (no mic needed; better for kids — record
once on a phone, replay repeatably, delete after scoring):
```bash
# convert a phone recording to the required format first:
ffmpeg -i recording.m4a -ar 16000 -ac 1 -sample_fmt s16 samples/u1.wav
.pyenv-spike/bin/python gemini_live_direct_probe.py --wav samples/u1.wav --id U1
```

Live mic (push-to-talk; press Enter when child finishes). **Needs an input
device** — on a Mac mini with no built-in/connected mic this won't work; use
`--wav` instead:
```bash
.pyenv-spike/bin/python gemini_live_direct_probe.py --mic --id smoke
```

Options:
- `--save-audio` — also write Gemini's RESPONSE audio to `results/audio_out/`
  (off by default; delete after scoring).

### Suggested flow
1. **Smoke test (adult, you):** one VN, one EN, one mixed sentence. Confirm
   `trial_log.jsonl` gets lines with sane latency numbers and correct transcripts.
2. **Real trials:** work through `trial_scenarios.md` with the child's voice.
3. **Score:** fill `results/scoring_sheet.md`, then **delete raw child audio**.
4. **Decide:** Phase 3 turns the tally into GO / Conditional GO / NO-GO.

## Child data & privacy (important)

- This script **never writes child INPUT audio**. If you pre-record samples,
  keep them in a local scratch folder (e.g. `samples/`, gitignored) and
  **delete after scoring**.
- `trial_log.jsonl` contains transcribed text of what the child said — it's
  gitignored; treat it as private and prune it when done.
- Nothing here uploads beyond the live API call needed to get a response.

## Files

| File | Purpose |
|------|---------|
| `gemini_live_direct_probe.py` | Harness A — direct Gemini Live probe (start here) |
| `requirements.txt` | deps (harness B deps commented out) |
| `.env.example` | config template (copy to `.env`) |
| `trial_scenarios.md` | the fixed trial list to run |
| `results/scoring_sheet.md` | human scoring template |
| `results/trial_log.jsonl` | machine log (created at runtime, gitignored) |

## Escalation to Harness B (only if needed)

If trials show Gemini **cutting off slow children**, the plan's decision rule
says to test whether a LiveKit turn-detector (`min_endpointing_delay` ~1.2–1.5s)
fixes it — that's the only thing justifying Architecture B's extra hop. Uncomment
the LiveKit deps in `requirements.txt` and build `livekit_agent_probe.py` then.
Don't build B unless cutoff is the deciding question.

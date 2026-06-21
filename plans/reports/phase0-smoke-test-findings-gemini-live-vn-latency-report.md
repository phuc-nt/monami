---
type: phase0-smoke-test-findings
date: 2026-06-21
slug: gemini-live-vn-latency
status: interim
plan: ../260621-1409-phase0-spike-gemini-live-vn-child-speech/
---

# Phase 0 Interim Findings — Gemini Live Smoke Test (VN → us-central1)

> Interim. Smoke test with a SYNTHETIC adult Vietnamese voice. The riskiest
> question (real 5yo child-speech understanding) is still UNTESTED — needs real
> recordings. User decision so far: latency acceptable, proceed with Architecture B.

## What was tested

- Harness A (`spike/gemini_live_direct_probe.py`) end-to-end against the real
  Live API on Vertex AI.
- One utterance, macOS `say` (voice "Linh") VN TTS → 16kHz mono WAV → replayed.
- Model: `gemini-live-2.5-flash-native-audio`.

## Key findings (measured, not assumed)

1. **Region: native-audio model is served ONLY in `us-central1`.**
   Live-probed `asia-southeast1` and `global` → both rejected (error 1008,
   "Publisher model … was not found"). us-central1 → connected OK.
   → Brief's "co-locate in Singapore" assumption is INVALID for this model.
   `.env` set to `us-central1`.

2. **Latency (VN → us-central1), idealized conditions:**
   - first-audio: **~1254 ms** (800ms trailing silence) / ~1387 ms (500ms silence)
   - complete: ~3.2–4.1 s
   - Lowering trailing silence did NOT reduce first-audio latency → the ~1.25–1.4s
     is dominated by model processing + VN→US RTT, not our turn-end padding.
   - Above the <1.2s "feels natural" target, but close. Real child voice + home
     wifi will likely be higher. **User accepted this and chose to proceed with B.**

3. **Understanding (synthetic adult VN):** transcribed perfectly —
   `"Chào bạn. Hôm nay mình muốn nghe kể chuyện con mèo."` ✅
   (NOT representative of real 5yo speech — still the #1 open risk.)

4. **Persona/safety:** warm, child-appropriate, engaged with a follow-up
   question. Sample response:
   `"Chào bạn nhỏ! Nghe kể chuyện con mèo là vui lắm đây. Bạn có muốn nghe về
   một chú mèo tinh nghịch hay hiền lành nhỉ?"` ✅

5. **Model constraint:** native-audio model supports AUDIO output ONLY; TEXT
   output rejected (error 1007). Fine for our use.

## Bugs found & fixed during the spike (the point of Phase 0)

1. **`audio_stream_end=True` is ignored by the native-audio model** → it returns
   nothing and `receive()` hangs forever. FIX: append trailing silence
   (`END_SILENCE_MS`, default 800ms) and let server-side VAD detect end-of-turn.
   This is the end-of-turn mechanism for this model. (Would have cost a day of
   blind debugging if discovered during app build.)
2. ADC missing quota project → `gcloud auth application-default
   set-quota-project monami-kids-spike`.

## Environment / setup done

- GCP project `monami-kids-spike`: Vertex AI enabled, billing on, ADC + quota project set.
- Spike env `spike/.pyenv-spike` (python 3.14): `google-genai 2.9.0`, `python-dotenv`, `sounddevice`.
- `spike/.env` written (project, location=us-central1, model).
- NOTE: this machine has NO microphone input device (Mac mini) → `--mic` mode
  unusable here; use `--wav` replay mode (also better for kids).

## Still UNTESTED (blocks GO/NO-GO)

- **Real 5-year-old Vietnamese child speech** understanding (slow/hesitant/mispronounced) — THE deciding risk.
- EN↔VN code-switching with real child utterances.
- Cutoff behavior on slow children (whether trailing-silence VAD cuts them off).
- Latency under real home-wifi conditions with child voice.

## Next steps

1. Record short real clips of the kids on a phone.
2. `ffmpeg -i clip.m4a -ar 16000 -ac 1 -sample_fmt s16 spike/samples/u1.wav`
3. `spike/.pyenv-spike/bin/python spike/gemini_live_direct_probe.py --wav spike/samples/u1.wav --id U1`
4. Run the `trial_scenarios.md` set, score in `results/scoring_sheet.md`, delete audio.
5. Phase 3: apply GO gate (understanding ≥85%, no systematic cutoff, latency
   acceptable, code-switch smooth, safe) → GO (B) / NO-GO (pivot C).

## Unresolved questions

1. Will real 5yo speech hit the ≥85% understanding gate? (untested)
2. Does the 800ms trailing-silence VAD cut off slow/pausing children? (tune `END_SILENCE_MS` if so)
3. Is ~1.25–1.4s+ latency genuinely acceptable to the kids in practice, or only on paper? (user accepted on paper for now)

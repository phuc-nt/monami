#!/usr/bin/env python3
"""Direct Gemini Live native-audio probe (Harness A) for the Phase 0 spike.

THROWAWAY spike code — see spike/README.md. Goal: push real Vietnamese
5-year-old speech through Gemini Live native audio (Vertex AI, asia-southeast1)
and measure understanding / latency / code-switch / cutoff / safety.

It does NOT decide go/no-go — it only records what happened. Scoring is a human
step in spike/results/scoring_sheet.md.

Two input modes:
  --mic            : talk live from the default microphone (push-to-talk style;
                     press Enter to mark "I finished speaking" = t_user_end).
  --wav PATH       : replay a pre-recorded utterance (16 kHz mono PCM WAV).

Each utterance produces one JSONL line in results/trial_log.jsonl:
  {utterance_id, mode, in_text, out_text,
   t_user_end, t_first_audio, t_complete,
   latency_first_audio_ms, latency_complete_ms,
   response_audio_path}

Audio handling: response audio is written to results/audio_out/ ONLY when
--save-audio is passed. Child INPUT audio is never written by this script — if
you record samples, keep them in a local scratch folder and delete after
scoring (see README).
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import json
import os
import sys
import time
import wave
from pathlib import Path

# google-genai SDK (see requirements.txt). Imported lazily-friendly so --help
# works without the dependency installed.
try:
    from google import genai
    from google.genai import types
except ImportError:  # pragma: no cover - guidance path only
    genai = None
    types = None

# Optional .env loading (python-dotenv). Falls back to plain os.environ.
with contextlib.suppress(ImportError):
    from dotenv import load_dotenv

    load_dotenv(Path(__file__).parent / ".env")

# --- Audio format constants (Gemini Live expects 16 kHz mono PCM input,
#     emits 24 kHz mono PCM output). ---
INPUT_SAMPLE_RATE = 16_000
OUTPUT_SAMPLE_RATE = 24_000
CHANNELS = 1
SAMPLE_WIDTH_BYTES = 2  # 16-bit PCM
CHUNK_MS = 20  # mic capture chunk size
# Trailing silence appended after an utterance so the native-audio model's
# server-side VAD detects end-of-turn. ~800ms is enough; tune if it cuts off
# slow speech in trials.
END_SILENCE_MS = 800

HERE = Path(__file__).parent
RESULTS_DIR = HERE / "results"
LOG_PATH = RESULTS_DIR / "trial_log.jsonl"
AUDIO_OUT_DIR = RESULTS_DIR / "audio_out"

# Bilingual EN/VN "friend for a 5-year-old" spike persona. This is a SPIKE
# prompt to exercise behavior, not the final production prompt.
SYSTEM_PROMPT = """\
Bạn là một người bạn ảo thân thiện, ấm áp, kiên nhẫn của một em bé 5 tuổi.
You are a warm, friendly, patient imaginary friend for a 5-year-old child.

Cách nói chuyện / How you talk:
- Nói câu NGẮN, từ ĐƠN GIẢN. Use SHORT sentences and SIMPLE words.
- Nói CHẬM RÃI và DỪNG lại để bé kịp trả lời. Speak slowly; pause so the child can respond.
- Mặc định dùng ngôn ngữ mà bé đang dùng. Default to whatever language the child uses.
- Chêm/chuyển sang tiếng Anh một cách TỰ NHIÊN, không ép. Mix in English naturally; never force it.
- Giọng vui vẻ, khích lệ, KHÔNG phán xét. Be cheerful and encouraging; never judgmental.

An toàn / Safety:
- Chỉ nói nội dung phù hợp với trẻ 5 tuổi. Only ever say things appropriate for a 5-year-old.
- Nếu gặp chủ đề không phù hợp hay đáng sợ, từ chối NHẸ NHÀNG và chuyển hướng sang
  điều vui vẻ, an toàn. If a topic is unsafe or scary, gently decline and redirect to
  something cheerful and safe.
"""

# Strict safety: block at the lowest threshold across configurable categories.
# Child-safety harms (e.g. CSAM) are always blocked by the platform regardless.
SAFETY_CATEGORIES = [
    "HARM_CATEGORY_HARASSMENT",
    "HARM_CATEGORY_HATE_SPEECH",
    "HARM_CATEGORY_SEXUALLY_EXPLICIT",
    "HARM_CATEGORY_DANGEROUS_CONTENT",
]


def _require_sdk() -> None:
    if genai is None:
        sys.exit(
            "google-genai SDK not installed. Run:\n"
            "  pip install -r spike/requirements.txt"
        )


def _build_config():
    """Build LiveConnectConfig: audio out, both transcriptions, strict safety."""
    return types.LiveConnectConfig(
        response_modalities=["AUDIO"],
        system_instruction=types.Content(
            parts=[types.Part(text=SYSTEM_PROMPT)]
        ),
        # Enable transcription of BOTH sides so we can score understanding
        # without retaining audio.
        input_audio_transcription=types.AudioTranscriptionConfig(),
        output_audio_transcription=types.AudioTranscriptionConfig(),
        safety_settings=[
            types.SafetySetting(category=cat, threshold="BLOCK_LOW_AND_ABOVE")
            for cat in SAFETY_CATEGORIES
        ],
    )


def _make_client():
    """Vertex AI client pinned to the spike project + region from env."""
    project = os.environ.get("GOOGLE_CLOUD_PROJECT")
    location = os.environ.get("GOOGLE_CLOUD_LOCATION", "asia-southeast1")
    if not project:
        sys.exit("GOOGLE_CLOUD_PROJECT not set. Copy .env.example to .env first.")
    return genai.Client(vertexai=True, project=project, location=location)


def _model_id() -> str:
    model = os.environ.get("GEMINI_LIVE_MODEL")
    if not model:
        sys.exit(
            "GEMINI_LIVE_MODEL not set. See .env.example — resolve the current "
            "stable native-audio model id from Vertex AI docs before running."
        )
    return model


def _read_wav_pcm(path: Path) -> bytes:
    """Read a 16 kHz mono 16-bit PCM WAV into raw bytes; validate format."""
    with wave.open(str(path), "rb") as wf:
        if wf.getframerate() != INPUT_SAMPLE_RATE or wf.getnchannels() != CHANNELS:
            sys.exit(
                f"{path}: expected {INPUT_SAMPLE_RATE} Hz mono; got "
                f"{wf.getframerate()} Hz / {wf.getnchannels()} ch. Re-encode with:\n"
                f"  ffmpeg -i in.wav -ar 16000 -ac 1 -sample_fmt s16 out.wav"
            )
        return wf.readframes(wf.getnframes())


def _write_wav(path: Path, pcm: bytes, sample_rate: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(SAMPLE_WIDTH_BYTES)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm)


def _append_log(record: dict) -> None:
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")


async def _run_turn(
    session, audio_in: bytes, utterance_id: str, mode: str, save_audio: bool
) -> dict:
    """Send one utterance, collect transcripts + response audio + timings.

    The native-audio model detects end-of-turn from server-side VAD (a stretch
    of silence) — NOT from an audio_stream_end signal (which this model ignores,
    returning nothing). So we stream the utterance paced ~real-time, then append
    trailing silence to make the model commit to a turn. The latency anchor
    (t_user_end) is the moment the child's real audio ends, before the silence.
    """
    bytes_per_chunk = int(
        INPUT_SAMPLE_RATE * SAMPLE_WIDTH_BYTES * CHUNK_MS / 1000
    )
    chunk_dt = CHUNK_MS / 1000

    # Stream the real utterance at ~real-time pace so server VAD behaves.
    for i in range(0, len(audio_in), bytes_per_chunk):
        chunk = audio_in[i : i + bytes_per_chunk]
        await session.send_realtime_input(
            audio=types.Blob(data=chunk, mime_type=f"audio/pcm;rate={INPUT_SAMPLE_RATE}")
        )
        await asyncio.sleep(chunk_dt)

    # Anchor: child's speech has now ended. Measure latency from here.
    t_user_end = time.monotonic()

    # Trailing silence → triggers server VAD end-of-turn (no audio_stream_end).
    silence = b"\x00\x00" * int(INPUT_SAMPLE_RATE * END_SILENCE_MS / 1000)
    for i in range(0, len(silence), bytes_per_chunk):
        await session.send_realtime_input(
            audio=types.Blob(data=silence[i : i + bytes_per_chunk],
                             mime_type=f"audio/pcm;rate={INPUT_SAMPLE_RATE}")
        )
        await asyncio.sleep(chunk_dt)

    in_text_parts: list[str] = []
    out_text_parts: list[str] = []
    audio_chunks: list[bytes] = []
    t_first_audio: float | None = None

    async for response in session.receive():
        sc = response.server_content
        if sc is None:
            continue
        if sc.input_transcription and sc.input_transcription.text:
            in_text_parts.append(sc.input_transcription.text)
        if sc.output_transcription and sc.output_transcription.text:
            out_text_parts.append(sc.output_transcription.text)
        if sc.model_turn:
            for part in sc.model_turn.parts:
                if part.inline_data and part.inline_data.data:
                    if t_first_audio is None:
                        t_first_audio = time.monotonic()
                    audio_chunks.append(part.inline_data.data)
        if sc.turn_complete:
            break

    t_complete = time.monotonic()

    audio_path = None
    if save_audio and audio_chunks:
        audio_path = str(AUDIO_OUT_DIR / f"{utterance_id}.wav")
        _write_wav(Path(audio_path), b"".join(audio_chunks), OUTPUT_SAMPLE_RATE)

    def _ms(start: float, end: float | None) -> float | None:
        return None if end is None else round((end - start) * 1000, 1)

    return {
        "utterance_id": utterance_id,
        "mode": mode,
        "in_text": "".join(in_text_parts).strip(),
        "out_text": "".join(out_text_parts).strip(),
        "t_user_end": round(t_user_end, 4),
        "t_first_audio": round(t_first_audio, 4) if t_first_audio else None,
        "t_complete": round(t_complete, 4),
        "latency_first_audio_ms": _ms(t_user_end, t_first_audio),
        "latency_complete_ms": _ms(t_user_end, t_complete),
        "response_audio_path": audio_path,
    }


async def _capture_mic(stop_event: asyncio.Event) -> bytes:
    """Capture mic audio until stop_event is set. Requires sounddevice."""
    try:
        import sounddevice as sd
    except ImportError:
        sys.exit(
            "Mic mode needs sounddevice. Install it or use --wav instead:\n"
            "  pip install sounddevice"
        )

    loop = asyncio.get_running_loop()
    frames: list[bytes] = []
    q: asyncio.Queue[bytes] = asyncio.Queue()

    def _callback(indata, _frames, _t, _status):  # runs in PortAudio thread
        loop.call_soon_threadsafe(q.put_nowait, bytes(indata))

    with sd.RawInputStream(
        samplerate=INPUT_SAMPLE_RATE,
        channels=CHANNELS,
        dtype="int16",
        callback=_callback,
        blocksize=int(INPUT_SAMPLE_RATE * CHUNK_MS / 1000),
    ):
        while not stop_event.is_set():
            with contextlib.suppress(asyncio.TimeoutError):
                frames.append(await asyncio.wait_for(q.get(), timeout=0.1))
    # Drain anything left.
    while not q.empty():
        frames.append(q.get_nowait())
    return b"".join(frames)


async def _mic_turn(session, utterance_id: str, save_audio: bool) -> dict:
    stop = asyncio.Event()
    print("🎙  Speak now. Press Enter when the child has finished speaking...")
    capture_task = asyncio.create_task(_capture_mic(stop))
    await asyncio.get_running_loop().run_in_executor(None, sys.stdin.readline)
    stop.set()
    audio_in = await capture_task
    if not audio_in:
        print("   (no audio captured — skipping)")
        return {}
    return await _run_turn(session, audio_in, utterance_id, "mic", save_audio)


async def main_async(args: argparse.Namespace) -> None:
    _require_sdk()
    client = _make_client()
    model = _model_id()
    config = _build_config()

    print(f"Connecting to {model} (project={os.environ.get('GOOGLE_CLOUD_PROJECT')}, "
          f"location={os.environ.get('GOOGLE_CLOUD_LOCATION', 'asia-southeast1')})...")

    async with client.aio.live.connect(model=model, config=config) as session:
        print("Connected. Log -> results/trial_log.jsonl\n")

        if args.wav:
            for idx, wav in enumerate(args.wav, start=1):
                uid = args.id or f"{Path(wav).stem}"
                if len(args.wav) > 1:
                    uid = f"{uid}-{idx}"
                print(f"▶ {uid}: replaying {wav}")
                pcm = _read_wav_pcm(Path(wav))
                record = await _run_turn(session, pcm, uid, "wav", args.save_audio)
                _append_log(record)
                _print_summary(record)
        else:  # --mic loop
            n = 0
            while True:
                n += 1
                uid = f"{args.id or 'mic'}-{n:03d}"
                record = await _mic_turn(session, uid, args.save_audio)
                if record:
                    _append_log(record)
                    _print_summary(record)
                cont = input("Another utterance? [Y/n] ").strip().lower()
                if cont == "n":
                    break

    print("\nDone. Score the results in results/scoring_sheet.md.")


def _print_summary(record: dict) -> None:
    print(f"   in : {record.get('in_text') or '(none)'}")
    print(f"   out: {record.get('out_text') or '(none)'}")
    print(
        f"   latency: first_audio="
        f"{record.get('latency_first_audio_ms')}ms "
        f"complete={record.get('latency_complete_ms')}ms\n"
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--mic", action="store_true", help="capture live from microphone")
    src.add_argument("--wav", nargs="+", metavar="PATH", help="replay 16kHz mono PCM WAV file(s)")
    p.add_argument("--id", help="utterance id prefix for the log")
    p.add_argument(
        "--save-audio",
        action="store_true",
        help="save Gemini's RESPONSE audio to results/audio_out/ (off by default)",
    )
    return p.parse_args(argv)


if __name__ == "__main__":
    ns = parse_args()
    try:
        asyncio.run(main_async(ns))
    except KeyboardInterrupt:
        print("\nInterrupted.")

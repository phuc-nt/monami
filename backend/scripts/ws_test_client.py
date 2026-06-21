#!/usr/bin/env python3
"""Local WebSocket test client — proves the backend without Flutter.

Streams a 16 kHz mono PCM WAV to the backend's /ws/voice, sends an end_utterance
control frame, then prints the transcripts + measures latency and (optionally)
saves the companion's response audio.

This is the Phase 1 acceptance check: "a local WS client streams a WAV and
receives transcript + audio + turn_complete."

Usage (backend must be running — see backend/README.md):
  python scripts/ws_test_client.py path/to/utterance_16k_mono.wav
  python scripts/ws_test_client.py utt.wav --url ws://127.0.0.1:8000/ws/voice --save-audio out.wav

The WAV must be 16 kHz mono 16-bit PCM. Re-encode if needed:
  ffmpeg -i in.any -ar 16000 -ac 1 -sample_fmt s16 utt.wav

Child audio stays local — do not commit input WAVs (root .gitignore blocks *.wav).
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time
import wave
from pathlib import Path

import websockets

INPUT_SAMPLE_RATE = 16_000
OUTPUT_SAMPLE_RATE = 24_000
CHANNELS = 1
SAMPLE_WIDTH_BYTES = 2
CHUNK_MS = 20  # pace audio ~real-time so server VAD behaves


def _read_wav_pcm(path: Path) -> bytes:
    """Read a 16 kHz mono 16-bit PCM WAV into raw bytes; validate format."""
    with wave.open(str(path), "rb") as wf:
        if wf.getframerate() != INPUT_SAMPLE_RATE or wf.getnchannels() != CHANNELS:
            sys.exit(
                f"{path}: expected {INPUT_SAMPLE_RATE} Hz mono; got "
                f"{wf.getframerate()} Hz / {wf.getnchannels()} ch. Re-encode:\n"
                f"  ffmpeg -i in.any -ar 16000 -ac 1 -sample_fmt s16 out.wav"
            )
        return wf.readframes(wf.getnframes())


def _write_wav(path: Path, pcm: bytes) -> None:
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(SAMPLE_WIDTH_BYTES)
        wf.setframerate(OUTPUT_SAMPLE_RATE)
        wf.writeframes(pcm)


async def _stream_audio(ws, pcm: bytes) -> float:
    """Send the WAV paced ~real-time, then end_utterance. Returns t_user_end."""
    bytes_per_chunk = int(INPUT_SAMPLE_RATE * SAMPLE_WIDTH_BYTES * CHUNK_MS / 1000)
    dt = CHUNK_MS / 1000
    for i in range(0, len(pcm), bytes_per_chunk):
        await ws.send(pcm[i : i + bytes_per_chunk])
        await asyncio.sleep(dt)
    t_user_end = time.monotonic()  # child speech ended; latency anchored here
    await ws.send(json.dumps({"type": "end_utterance"}))
    return t_user_end


async def _collect_response(ws, t_user_end: float) -> dict:
    """Read frames until turn_complete; gather transcripts, audio, latency."""
    in_text: list[str] = []
    out_text: list[str] = []
    audio = bytearray()
    t_first_audio: float | None = None

    async for message in ws:
        if isinstance(message, bytes):
            if t_first_audio is None:
                t_first_audio = time.monotonic()
            audio.extend(message)
            continue
        evt = json.loads(message)
        etype = evt.get("type")
        if etype == "in_transcript":
            in_text.append(evt["text"])
        elif etype == "out_transcript":
            out_text.append(evt["text"])
        elif etype == "error":
            sys.exit(f"backend error: {evt.get('message')}")
        elif etype == "turn_complete":
            break

    t_complete = time.monotonic()

    def _ms(end: float | None) -> float | None:
        return None if end is None else round((end - t_user_end) * 1000, 1)

    return {
        "in_text": "".join(in_text).strip(),
        "out_text": "".join(out_text).strip(),
        "latency_first_audio_ms": _ms(t_first_audio),
        "latency_complete_ms": _ms(t_complete),
        "audio": bytes(audio),
    }


async def run(args: argparse.Namespace) -> None:
    pcm = _read_wav_pcm(Path(args.wav))
    print(f"Connecting to {args.url} …")
    async with websockets.connect(args.url, max_size=None) as ws:
        print(f"Streaming {args.wav} ({len(pcm)} bytes)…")
        t_user_end = await _stream_audio(ws, pcm)
        result = await _collect_response(ws, t_user_end)

    print(f"  in : {result['in_text'] or '(none)'}")
    print(f"  out: {result['out_text'] or '(none)'}")
    print(
        f"  latency: first_audio={result['latency_first_audio_ms']}ms "
        f"complete={result['latency_complete_ms']}ms"
    )
    if args.save_audio and result["audio"]:
        _write_wav(Path(args.save_audio), result["audio"])
        print(f"  saved response audio -> {args.save_audio}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument("wav", help="16 kHz mono 16-bit PCM WAV to stream")
    p.add_argument(
        "--url", default="ws://127.0.0.1:8000/ws/voice", help="backend WS URL"
    )
    p.add_argument(
        "--save-audio", metavar="OUT.wav", help="save the response audio to this path"
    )
    return p.parse_args(argv)


if __name__ == "__main__":
    try:
        asyncio.run(run(parse_args()))
    except KeyboardInterrupt:
        print("\nInterrupted.")

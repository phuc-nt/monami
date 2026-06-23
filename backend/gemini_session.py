"""Per-connection Gemini Live relay: one WebSocket <-> one Live session.

run_session(ws) opens a Gemini Live native-audio session and runs two concurrent
pumps over the lifetime of the connection:

  - uplink   (client -> Gemini): forward raw 16 kHz PCM frames; on an
    "end_utterance" control frame, append trailing silence so the native-audio
    model's server VAD commits to a turn (it ignores audio_stream_end).
  - downlink (Gemini -> client): forward response audio (24 kHz PCM) as binary
    frames and transcripts / turn_complete as JSON.

The GCP credential lives only in this process (ADC / env). The client protocol
carries audio + text only — no credential ever crosses the WebSocket.

Wire protocol (client <-> backend):
  client -> server:
    - binary frame                          = raw 16 kHz mono PCM audio chunk
    - {"type": "end_utterance"}             = push-to-talk released; flush turn
  server -> client:
    - binary frame                          = 24 kHz mono PCM response audio
    - {"type": "in_transcript",  "text": …} = transcript of the child
    - {"type": "out_transcript", "text": …} = transcript of the companion
    - {"type": "turn_complete"}             = companion finished this turn
    - {"type": "error", "message": …}       = session error (then close)
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging

from google import genai
from google.genai import types

import gemini_session_config as cfg
from child_profile import GUEST_PROFILE, profile_from_record
from child_store import get_child, load_memory, save_memory
from memory_summarizer import summarize

logger = logging.getLogger("gemini_session")

# Frame size for streaming trailing silence (~20 ms). Matches the client's
# capture chunking so pacing into the server VAD stays smooth.
_SILENCE_CHUNK_MS = 20
_SILENCE_CHUNK_BYTES = int(
    cfg.INPUT_SAMPLE_RATE * cfg.SAMPLE_WIDTH_BYTES * _SILENCE_CHUNK_MS / 1000
)
_SILENCE_CHUNK_DT = _SILENCE_CHUNK_MS / 1000


def _make_client() -> genai.Client:
    """Vertex AI client pinned to the project + region from env (ADC auth)."""
    project, location = cfg.project_and_location()
    return genai.Client(vertexai=True, project=project, location=location)


async def _send_trailing_silence(session) -> None:
    """Stream END_SILENCE_MS of silence so server VAD detects end-of-turn.

    Paced ~real-time in small chunks (not one big blob) so the VAD treats it as a
    genuine pause rather than a discontinuity.
    """
    total = int(
        cfg.INPUT_SAMPLE_RATE * cfg.SAMPLE_WIDTH_BYTES * cfg.END_SILENCE_MS / 1000
    )
    silence = b"\x00" * total
    mime = cfg.input_audio_mime_type()
    for i in range(0, len(silence), _SILENCE_CHUNK_BYTES):
        await session.send_realtime_input(
            audio=types.Blob(data=silence[i : i + _SILENCE_CHUNK_BYTES], mime_type=mime)
        )
        await asyncio.sleep(_SILENCE_CHUNK_DT)


async def _uplink(ws, session) -> None:
    """Client -> Gemini: forward PCM; on end_utterance, flush with silence.

    Reads frames from the WebSocket: bytes = audio, text = JSON control. Exits
    when the client disconnects (the receive raises), letting run_session tear
    the whole session down.
    """
    mime = cfg.input_audio_mime_type()
    async for kind, payload in ws.iter_messages():
        if kind == "bytes":
            await session.send_realtime_input(
                audio=types.Blob(data=payload, mime_type=mime)
            )
        elif kind == "text":
            try:
                ctrl = json.loads(payload)
            except json.JSONDecodeError:
                logger.warning("uplink: ignoring non-JSON text frame")
                continue
            if ctrl.get("type") == "end_utterance":
                await _send_trailing_silence(session)


async def _downlink(ws, session, transcript: list[tuple[str, str]]) -> None:
    """Gemini -> client: forward audio (binary) + transcripts / turn_complete (JSON).

    Appends each transcript line (speaker, text) to `transcript` so the session
    can be summarized into memory on teardown.

    The SDK's session.receive() generator yields one turn then ends at the first
    turn_complete. For a long-lived multi-turn conversation we re-enter it per
    turn, looping until the session/socket closes (receive() yielding nothing or
    raising a disconnect-shaped error, which propagates to run_session).
    """
    while True:
        got_response = False
        async for response in session.receive():
            got_response = True
            sc = response.server_content
            if sc is None:
                continue
            if sc.input_transcription and sc.input_transcription.text:
                text = sc.input_transcription.text
                transcript.append(("Bé/Child", text))
                await _send_json(ws, {"type": "in_transcript", "text": text})
            if sc.output_transcription and sc.output_transcription.text:
                text = sc.output_transcription.text
                transcript.append(("Bạn/Companion", text))
                await _send_json(ws, {"type": "out_transcript", "text": text})
            if sc.model_turn:
                for part in sc.model_turn.parts:
                    if part.inline_data and part.inline_data.data:
                        await ws.send_bytes(part.inline_data.data)
            if sc.turn_complete:
                await _send_json(ws, {"type": "turn_complete"})
        # receive() ended without yielding => the Live session has closed.
        if not got_response:
            return


async def run_session(
    ws,
    device_id: str | None = None,
    child_id: str | None = None,
    is_guest: bool = False,
) -> None:
    """Open a Gemini Live session for one client connection and relay both ways.

    `is_guest` MUST be computed by the caller from the RAW connection params
    (before any profile resolution) — a guest session loads and saves NO memory.
    For a registered child, (device_id, child_id) locate the child doc; if it
    can't be resolved we fall back to the neutral GUEST profile and treat the
    session as guest (no persistence), never another child's memory.

    Spawns the uplink + downlink pumps; when either finishes (client disconnect or
    session end) the other is cancelled and the Live session is closed.
    """
    persist = not is_guest and bool(device_id) and bool(child_id)
    record = get_child(device_id, child_id) if persist else None
    if persist and record is None:
        # Unknown child under this device: don't write to anyone — go guest.
        logger.warning("child not found for device; running as guest (no memory)")
        persist = False
    profile = profile_from_record(record) if record else GUEST_PROFILE
    memory_text = load_memory(device_id, child_id) if persist else ""

    client = _make_client()
    model = cfg.model_id()
    config = cfg.build_live_connect_config(profile, memory_text)

    logger.info(
        "opening Gemini Live session: model=%s persist=%s (memory=%s)",
        model, persist, "yes" if memory_text else "none",
    )
    transcript: list[tuple[str, str]] = []
    try:
        async with client.aio.live.connect(model=model, config=config) as session:
            uplink = asyncio.create_task(_uplink(ws, session), name="uplink")
            downlink = asyncio.create_task(
                _downlink(ws, session, transcript), name="downlink"
            )
            done, pending = await asyncio.wait(
                {uplink, downlink}, return_when=asyncio.FIRST_COMPLETED
            )
            for task in pending:
                task.cancel()
            await asyncio.gather(*pending, return_exceptions=True)
            # Surface a pump's real error (not a benign disconnect) for logging.
            for task in done:
                exc = task.exception()
                if exc is not None and not isinstance(exc, _DISCONNECT_ERRORS_T):
                    raise exc
    except Exception:  # noqa: BLE001 - report then close
        # Full detail (which may include project id / region) goes to the server
        # log only; the client gets a generic message — nothing internal crosses
        # the wire. Best-effort: the socket may already be closing.
        logger.exception("session error")
        with contextlib.suppress(Exception):
            await _send_json(ws, {"type": "error", "message": "session error"})
    finally:
        logger.info("Gemini Live session closed")
        # Best-effort: fold this session into the child's memory. Bounded by a
        # timeout so teardown can't hang. The client has already disconnected by
        # now; this lingers the server task up to the timeout — fine at this
        # app's scale. Detach it if concurrency ever grows.
        # GUEST INVARIANT: only persist when this is a real, resolved child —
        # never for a guest/unknown session (which would otherwise leak into some
        # other child's memory).
        if persist:
            await _update_memory(client, device_id, child_id, memory_text, transcript)


# A session shorter than this (few transcript lines) isn't worth summarizing —
# avoids overwriting a good memory with an empty/greeting-only exchange.
_MIN_TRANSCRIPT_LINES = 2
_SUMMARY_TIMEOUT_S = 20


async def _update_memory(
    client: genai.Client,
    device_id: str,
    child_id: str,
    prior_summary: str,
    transcript: list[tuple[str, str]],
) -> None:
    """Summarize the session into the child's memory and save it. Best-effort.

    Only ever called for a resolved (device_id, child_id) — guests are gated out
    by the caller, so this never falls back to a default child.
    """
    if len(transcript) < _MIN_TRANSCRIPT_LINES:
        return
    transcript_text = "\n".join(f"{who}: {text}" for who, text in transcript)
    try:
        # summarize() already returns the prior summary on its own errors; the
        # only thing that can raise here is the outer timeout.
        new_summary = await asyncio.wait_for(
            summarize(client, prior_summary, transcript_text),
            timeout=_SUMMARY_TIMEOUT_S,
        )
    except asyncio.TimeoutError:
        logger.warning("memory summary timed out; keeping prior")
        return
    if new_summary and new_summary != prior_summary:
        save_memory(device_id, child_id, new_summary, updated_at=_now_iso())
        logger.info("memory updated")


def _now_iso() -> str:
    # Imported lazily so the module has no import-time clock dependency.
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).isoformat()


# --- WebSocket abstraction --------------------------------------------------
# run_session is written against a tiny duck-typed interface so it is testable
# and not hard-bound to Starlette. The adapter in main.py provides:
#   await ws.send_bytes(b)   await ws.send_text(s)
#   async for (kind, payload) in ws.iter_messages(): ...

# Disconnect-shaped errors we treat as a normal end-of-connection, not failures.
# The Starlette adapter (main.py) translates WebSocketDisconnect -> ConnectionError
# at the boundary, so the core stays framework-agnostic. ConnectionClosed covers a
# direct `websockets` transport (e.g. the standalone test client).
_DISCONNECT_ERRORS: list[type[BaseException]] = [
    asyncio.CancelledError,
    ConnectionError,
]
try:  # optional: only present if `websockets` is installed
    from websockets.exceptions import ConnectionClosed as _ConnectionClosed

    _DISCONNECT_ERRORS.append(_ConnectionClosed)
except ImportError:  # pragma: no cover
    pass
_DISCONNECT_ERRORS_T: tuple[type[BaseException], ...] = tuple(_DISCONNECT_ERRORS)


async def _send_json(ws, obj: dict) -> None:
    await ws.send_text(json.dumps(obj, ensure_ascii=False))

"""FastAPI app: WebSocket voice relay + health check.

Routes:
  GET  /health     -> {"status": "ok"} liveness probe.
  WS   /ws/voice   -> one Gemini Live session per connection (see gemini_session).

Run:
  uvicorn main:app --host 127.0.0.1 --port 8000   (from the backend/ dir)

GCP auth is Application Default Credentials (gcloud auth application-default
login) read by the google-genai Vertex client — never sent to the client.
"""

from __future__ import annotations

import logging
import os
import secrets
from pathlib import Path

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from starlette.websockets import WebSocketState

# Load backend/.env before reading config (no-op if python-dotenv absent).
try:
    from dotenv import load_dotenv

    load_dotenv(Path(__file__).parent / ".env")
except ImportError:  # pragma: no cover - optional dependency
    pass

from gemini_session import run_session

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("backend")

app = FastAPI(title="monami voice backend", version="0.1.0")


@app.on_event("startup")
async def _log_startup_config() -> None:
    # Surface the memory backend at boot so a misconfig (e.g. on Cloud Run) is
    # obvious in the logs rather than silently losing memory.
    import profile_store

    logger.info(
        "startup: memory_backend=%s auth=%s",
        profile_store._backend(),
        "on" if os.environ.get("MONAMI_AUTH_TOKEN") else "off (open)",
    )


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


def _token_ok(supplied: str | None) -> bool:
    """Constant-time check of the shared-secret token.

    If MONAMI_AUTH_TOKEN is unset (local dev), allow all (the WS isn't exposed).
    In the cloud it MUST be set so a stranger with the URL can't open a session.
    """
    expected = os.environ.get("MONAMI_AUTH_TOKEN")
    if not expected:
        return True  # local dev: no gate (warned at startup)
    return secrets.compare_digest(supplied or "", expected)


@app.websocket("/ws/voice")
async def ws_voice(websocket: WebSocket) -> None:
    await websocket.accept()
    # Reject an unauthorized connect BEFORE opening any Gemini session (so a
    # stranger with the URL can't burn quota or touch a child's memory). 1008 =
    # policy violation.
    if not _token_ok(websocket.query_params.get("token")):
        logger.warning("rejected connect: bad/missing token (%s)", websocket.client)
        await websocket.close(code=1008)
        return
    # Which child is talking, e.g. ws://…/ws/voice?profile=vy (defaults if absent).
    profile_id = websocket.query_params.get("profile")
    logger.info("client connected: %s (profile=%s)", websocket.client, profile_id)
    try:
        await run_session(_StarletteWsAdapter(websocket), profile_id)
    except WebSocketDisconnect:
        logger.info("client disconnected")
    finally:
        if websocket.client_state != WebSocketState.DISCONNECTED:
            await websocket.close()


class _StarletteWsAdapter:
    """Adapt Starlette's WebSocket to the interface gemini_session expects.

    Provides send_bytes / send_text and an async iter_messages() yielding
    (kind, payload) tuples where kind is 'bytes' or 'text'. Keeps the relay
    decoupled from the web framework.
    """

    def __init__(self, ws: WebSocket) -> None:
        self._ws = ws

    async def send_bytes(self, data: bytes) -> None:
        try:
            await self._ws.send_bytes(data)
        except WebSocketDisconnect as exc:  # client dropped mid-turn
            raise ConnectionError("client disconnected") from exc

    async def send_text(self, text: str) -> None:
        try:
            await self._ws.send_text(text)
        except WebSocketDisconnect as exc:
            raise ConnectionError("client disconnected") from exc

    async def iter_messages(self):
        """Yield ('bytes', b) or ('text', s) until the client disconnects.

        A clean websocket.disconnect ends the iteration; a mid-receive
        disconnect surfaces as ConnectionError so the relay treats it as a
        normal end-of-connection (see gemini_session._DISCONNECT_ERRORS).
        """
        while True:
            try:
                message = await self._ws.receive()
            except WebSocketDisconnect as exc:
                raise ConnectionError("client disconnected") from exc
            if message["type"] == "websocket.disconnect":
                return
            if (data := message.get("bytes")) is not None:
                yield ("bytes", data)
            elif (text := message.get("text")) is not None:
                yield ("text", text)

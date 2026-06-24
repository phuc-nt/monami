"""Session-level guest invariant: a guest run_session writes NOTHING; a real
child DOES persist. Proves the `persist` gate (the one invariant phase 5 lives
or dies on) from both sides, exercising the actual downlink → transcript →
`finally` summarizer path (not a crash path).

We mock the Gemini client + live session (no network): the fake session yields
one in/out transcript turn then ends, so `transcript` is non-empty and the
`finally` block's `_update_memory` would run IFF `persist` is true. We patch
`save_memory` (the real persistence sink) and assert whether it's reached.
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


class _Resp:
    """A minimal server_content carrying one in + out transcript line."""

    class _T:
        def __init__(self, text):
            self.text = text

    def __init__(self):
        self.input_transcription = _Resp._T("Bé: con thích khủng long")
        self.output_transcription = _Resp._T("Bạn: khủng long thật tuyệt!")
        self.model_turn = None
        self.turn_complete = True

    @property
    def server_content(self):
        return self


class _FakeSession:
    """Stands in for a Gemini Live session: one turn, then the stream ends."""

    def __init__(self):
        self._yielded = False

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False

    async def send_realtime_input(self, **kw):  # pragma: no cover - uplink unused
        pass

    def receive(self):
        # An async generator: yield ONE response on the first call, nothing after
        # (so _downlink's outer while-loop exits cleanly without an error path).
        async def gen():
            if not self._yielded:
                self._yielded = True
                yield _Resp()

        return gen()


class _FakeWs:
    """A ws that closes immediately (uplink ends), and records sends."""

    def __init__(self):
        self.sent = []

    async def send_bytes(self, data):  # pragma: no cover
        self.sent.append(("bytes", data))

    async def send_text(self, text):
        self.sent.append(("text", text))

    async def iter_messages(self):
        return
        yield  # async generator that yields nothing → uplink ends at once


def _patched_client():
    client = mock.MagicMock()
    client.aio.live.connect.return_value = _FakeSession()
    return client


def _run(monkeypatch, *, device, profile, is_guest, child_record=None, mode=None):
    import gemini_session

    monkeypatch.setattr(gemini_session, "_make_client", _patched_client)
    monkeypatch.setattr(gemini_session.cfg, "model_id", lambda: "fake-model")
    monkeypatch.setattr(
        gemini_session.cfg, "build_live_connect_config", lambda *a, **k: object()
    )
    # Real summarizer is mocked to return a fixed summary so we can assert the
    # SINK (save_memory) is/isn't reached — the gate is what we're testing.
    monkeypatch.setattr(
        gemini_session, "summarize", mock.AsyncMock(return_value="a new summary")
    )
    # Control child resolution: a real record (persist) or None (guest/unknown).
    monkeypatch.setattr(gemini_session, "get_child", lambda d, c: child_record)
    monkeypatch.setattr(gemini_session, "load_memory", lambda d, c: "")
    save_spy = mock.MagicMock()
    monkeypatch.setattr(gemini_session, "save_memory", save_spy)

    asyncio.run(
        gemini_session.run_session(
            _FakeWs(), device_id=device, child_id=profile, is_guest=is_guest,
            mode=mode,
        )
    )
    return save_spy


def test_guest_session_never_persists(monkeypatch):
    save_spy = _run(monkeypatch, device=None, profile="guest", is_guest=True)
    save_spy.assert_not_called()


def test_guest_LEARNING_session_never_persists(monkeypatch):
    # The phase-4 invariant: a guest in a learning mode must STILL write nothing —
    # adding mode/topic context must not cause a guest persist.
    save_spy = _run(
        monkeypatch, device=None, profile="guest", is_guest=True, mode="english"
    )
    save_spy.assert_not_called()


def test_old_build_no_device_runs_as_guest(monkeypatch):
    # Cutover shim: ?profile=vy with no device → guest, no write.
    save_spy = _run(monkeypatch, device=None, profile="vy", is_guest=True)
    save_spy.assert_not_called()


def test_unknown_child_under_device_does_not_persist(monkeypatch):
    # get_child returns None → treated as guest (no write).
    save_spy = _run(
        monkeypatch, device="devX", profile="ghost", is_guest=False, child_record=None
    )
    save_spy.assert_not_called()


def test_registered_child_DOES_persist(monkeypatch):
    # The positive side of the gate: a real child + a non-empty transcript writes.
    record = {
        "id": "c1",
        "name": "Vy",
        "gender": "girl",
        "age": 5,
        "interests": [],
        "memory": {"summary": "", "updated_at": None},
    }
    save_spy = _run(
        monkeypatch, device="devX", profile="c1", is_guest=False, child_record=record
    )
    save_spy.assert_called_once()
    # Saved under the right (device, child), with the new summary.
    args, kwargs = save_spy.call_args
    assert args[0] == "devX" and args[1] == "c1"
    assert args[2] == "a new summary"


def test_registered_child_learning_session_records_done_note(monkeypatch):
    # A registered child in a learning mode saves a memory that includes the
    # "đã học: <mode>:<id>" note (appended deterministically).
    import curriculum

    record = {
        "id": "c1", "name": "Vy", "gender": "girl", "age": 5, "interests": [],
        "memory": {"summary": "", "updated_at": None},
    }
    save_spy = _run(
        monkeypatch, device="devX", profile="c1", is_guest=False,
        child_record=record, mode="english",
    )
    save_spy.assert_called_once()
    saved = save_spy.call_args.args[2]
    # The first english topic is "animals" (empty memory → not done).
    assert curriculum.done_note("english", "animals") in saved

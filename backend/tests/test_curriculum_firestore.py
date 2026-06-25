"""Phase 2 — curriculum from Firestore (cache-on-success-only + JSON fallback).

Mocks the Firestore client so no GCP is touched. The fake records how many times
`.stream()` runs per mode, so we can assert:
  - a successful read is cached (second call does NOT re-hit Firestore);
  - a failed read falls back to bundled JSON and is NOT cached (next call retries);
  - enabled=false topics are skipped; `order` controls sequence; prefix is honored;
  - Phase-1 done_topics still skip Firestore-sourced topics.
"""

from __future__ import annotations

import importlib
import sys
from pathlib import Path
from unittest import mock

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


class _Snap:
    def __init__(self, doc_id: str, data: dict):
        self.id = doc_id
        self._data = data

    def to_dict(self) -> dict:
        return dict(self._data)


class _FakeTopicsCollection:
    """Stands in for `.collection(...).document(mode).collection("topics")`.

    `stream()` returns the configured snaps and bumps a shared call counter so a
    test can prove a cached read does NOT re-hit Firestore. If `raise_on_stream`
    is set, stream() raises (the Firestore-outage path).
    """

    def __init__(self, snaps, counter, raise_on_stream=False):
        self._snaps = snaps
        self._counter = counter
        self._raise = raise_on_stream

    def stream(self):
        self._counter["n"] += 1
        if self._raise:
            raise RuntimeError("firestore down")
        return list(self._snaps)


class _FakeClient:
    """Routes collection(prefixed_name).document(mode).collection('topics') to the
    configured fake topics collection; records the prefixed collection name used."""

    def __init__(self, snaps_by_mode, counter, raise_on_stream=False):
        self._snaps_by_mode = snaps_by_mode
        self._counter = counter
        self._raise = raise_on_stream
        self.collection_names = []

    def collection(self, name):
        self.collection_names.append(name)
        return _FakeMode(self._snaps_by_mode, self._counter, self._raise)


class _FakeMode:
    def __init__(self, snaps_by_mode, counter, raise_on_stream):
        self._snaps_by_mode = snaps_by_mode
        self._counter = counter
        self._raise = raise_on_stream

    def document(self, mode):
        self._mode = mode
        return self

    def collection(self, _topics):
        return _FakeTopicsCollection(
            self._snaps_by_mode.get(self._mode, []), self._counter, self._raise
        )


@pytest.fixture()
def curriculum(monkeypatch):
    monkeypatch.setenv("MEMORY_BACKEND", "firestore")
    monkeypatch.delenv("FIRESTORE_PREFIX", raising=False)
    import child_store

    importlib.reload(child_store)
    import curriculum as _curriculum

    importlib.reload(_curriculum)
    _curriculum._cache.clear()
    yield _curriculum
    _curriculum._cache.clear()


def _wire(curriculum, monkeypatch, snaps_by_mode, *, raise_on_stream=False):
    counter = {"n": 0}
    client = _FakeClient(snaps_by_mode, counter, raise_on_stream)
    monkeypatch.setattr(curriculum.child_store, "_client", lambda: client)
    return client, counter


def test_reads_topics_from_firestore(curriculum, monkeypatch):
    snaps = {"english": [_Snap("animals", {"title_vi": "Con vật", "words": []})]}
    client, counter = _wire(curriculum, monkeypatch, snaps)
    topics = curriculum._load_topics("english")
    assert [t["id"] for t in topics] == ["animals"]
    assert counter["n"] == 1


def test_successful_read_is_cached(curriculum, monkeypatch):
    snaps = {"english": [_Snap("animals", {"title_vi": "A", "words": []})]}
    client, counter = _wire(curriculum, monkeypatch, snaps)
    curriculum._load_topics("english")
    curriculum._load_topics("english")  # second call: must hit the cache
    assert counter["n"] == 1, "a cached read must not re-hit Firestore"


def test_firestore_error_falls_back_to_json_and_is_not_cached(curriculum, monkeypatch):
    # stream() raises → JSON fallback. The fallback must NOT be cached, so the
    # next call re-hits Firestore (counter increments again).
    _, counter = _wire(curriculum, monkeypatch, {}, raise_on_stream=True)
    first = curriculum._load_topics("english")
    assert first and first[0]["id"], "JSON fallback should serve real topics"
    assert counter["n"] == 1
    curriculum._load_topics("english")  # retries Firestore (not pinned to JSON)
    assert counter["n"] == 2, "fallback must not be cached"


def test_empty_firestore_falls_back_to_json_uncached(curriculum, monkeypatch):
    # An unseeded mode (no docs) is treated as "no content" → JSON fallback, also
    # uncached so a later seed is picked up.
    _, counter = _wire(curriculum, monkeypatch, {"english": []})
    topics = curriculum._load_topics("english")
    assert topics, "empty Firestore should fall back to bundled JSON"
    curriculum._load_topics("english")
    assert counter["n"] == 2, "empty-read fallback must not be cached"


def test_enabled_false_is_skipped(curriculum, monkeypatch):
    snaps = {
        "english": [
            _Snap("animals", {"title_vi": "A", "words": [], "enabled": True}),
            _Snap("food", {"title_vi": "F", "words": [], "enabled": False}),
        ]
    }
    _wire(curriculum, monkeypatch, snaps)
    ids = [t["id"] for t in curriculum._load_topics("english")]
    assert ids == ["animals"], "enabled=false topic must be skipped"


def test_order_controls_sequence(curriculum, monkeypatch):
    snaps = {
        "english": [
            _Snap("food", {"title_vi": "F", "words": [], "order": 2}),
            _Snap("animals", {"title_vi": "A", "words": [], "order": 1}),
        ]
    }
    _wire(curriculum, monkeypatch, snaps)
    ids = [t["id"] for t in curriculum._load_topics("english")]
    assert ids == ["animals", "food"], "topics must sort by `order`"


def test_prefix_is_honored(curriculum, monkeypatch):
    monkeypatch.setenv("FIRESTORE_PREFIX", "dev_")
    snaps = {"english": [_Snap("animals", {"title_vi": "A", "words": []})]}
    client, _ = _wire(curriculum, monkeypatch, snaps)
    curriculum._load_topics("english")
    assert "dev_curriculum" in client.collection_names
    assert "curriculum" not in client.collection_names


def test_done_topics_skip_firestore_sourced_topics(curriculum, monkeypatch):
    snaps = {
        "english": [
            _Snap("animals", {"title_vi": "A", "words": [], "order": 1}),
            _Snap("food", {"title_vi": "F", "words": [], "order": 2}),
        ]
    }
    _wire(curriculum, monkeypatch, snaps)
    # Phase-1 done_topics array marks "animals" done → loader advances to "food".
    t = curriculum.load_topic("english", "", done_topics=["english:animals"])
    assert t["id"] == "food"

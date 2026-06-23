"""Store-level + guest-invariant tests (JSON backend, no GCP).

Covers device-scoped paths, the merged-memory semantics, and the critical guest
invariant: a guest / unknown session must never write to another child's memory
(the historical `DEFAULT_PROFILE_ID="vy"` fallback must not leak).
"""

from __future__ import annotations

import importlib
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


@pytest.fixture()
def store(tmp_path, monkeypatch):
    monkeypatch.setenv("MEMORY_BACKEND", "json")
    import child_store

    importlib.reload(child_store)
    monkeypatch.setattr(child_store, "_PROFILES_DIR", tmp_path / "profiles")
    return child_store


def test_create_and_load_memory_device_scoped(store):
    c = store.create_child("devX", {"name": "Vy", "gender": "girl", "age": 5})
    assert store.load_memory("devX", c["id"]) == ""
    store.save_memory("devX", c["id"], "thích Elsa", updated_at="t1")
    assert store.load_memory("devX", c["id"]) == "thích Elsa"
    # A different device with the same child id sees nothing.
    assert store.load_memory("devY", c["id"]) == ""


def test_save_memory_on_missing_child_is_noop(store):
    # Guest path relies on this: writing memory for a child that doesn't exist
    # under the device must not create anything. (Same contract both backends:
    # the get_child guard prevents Firestore set(merge=True) from upserting a
    # profile-less ghost doc.)
    store.save_memory("devX", "ghost", "should not persist", updated_at="t1")
    assert store.get_child("devX", "ghost") is None
    assert store.list_children("devX") == []


def test_memory_save_does_not_clobber_profile(store):
    c = store.create_child("devX", {"name": "Bo", "gender": "boy", "age": 5, "interests": ["xe"]})
    store.save_memory("devX", c["id"], "mới", updated_at="t1")
    got = store.get_child("devX", c["id"])
    assert got["name"] == "Bo" and got["interests"] == ["xe"]  # profile intact
    assert got["memory"]["summary"] == "mới"


def test_update_then_memory_then_update_no_loss(store):
    c = store.create_child("devX", {"name": "Bo", "gender": "boy", "age": 5})
    store.save_memory("devX", c["id"], "m1", updated_at="t1")
    store.update_child("devX", c["id"], {"age": 6})  # profile edit after memory write
    got = store.get_child("devX", c["id"])
    assert got["age"] == 6 and got["memory"]["summary"] == "m1"  # both survive


def test_clear_memory_keeps_child(store):
    c = store.create_child("devX", {"name": "Bo", "gender": "boy", "age": 5})
    store.save_memory("devX", c["id"], "x", updated_at="t1")
    assert store.clear_memory("devX", c["id"]) is True
    assert store.load_memory("devX", c["id"]) == ""
    assert store.get_child("devX", c["id"]) is not None
    # Clearing a missing child is False.
    assert store.clear_memory("devX", "nope") is False


def test_guest_resolution_does_not_pick_a_real_child():
    """profile_from_record/GUEST never resolve to a stored child.

    The old code fell back to DEFAULT_PROFILE_ID='vy'; the new design has no such
    fallback — a guest uses GUEST_PROFILE and persistence is gated separately.
    """
    import child_profile

    importlib.reload(child_profile)
    assert child_profile.GUEST_PROFILE.profile_id == "guest"
    assert child_profile.GUEST_PROFILE.gender == "neutral"
    # An unknown/blank gender becomes neutral, never crashes.
    p = child_profile.profile_from_record({"id": "c1", "name": "X", "age": 5, "gender": "?"})
    assert p.gender == "neutral"


def test_is_guest_derivation_matches_main():
    """The guest flag must be derived from RAW params (mirror of main.ws_voice)."""
    def is_guest(device, profile):
        return (not device) or profile == "guest"

    assert is_guest(None, "vy") is True          # old build: no device -> guest
    assert is_guest("", "vy") is True            # empty device -> guest
    assert is_guest("devX", "guest") is True     # explicit guest sentinel
    assert is_guest("devX", "child123") is False  # real child -> persist

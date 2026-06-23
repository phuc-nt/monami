"""REST CRUD tests against the JSON backend (no Firestore, no GCP).

Each test uses an isolated temp profiles dir so runs don't touch real data. The
FastAPI app is imported with MEMORY_BACKEND=json and no auth token (open, like
local dev).
"""

from __future__ import annotations

import importlib
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

# Make the backend package importable (tests/ is a sibling of the modules).
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("MEMORY_BACKEND", "json")
    monkeypatch.delenv("MONAMI_AUTH_TOKEN", raising=False)
    # Point the store at a temp dir so tests are hermetic.
    import child_store

    importlib.reload(child_store)
    monkeypatch.setattr(child_store, "_PROFILES_DIR", tmp_path / "profiles")
    import child_rest_api

    importlib.reload(child_rest_api)
    import main

    importlib.reload(main)
    return TestClient(main.app)


def _make(client, device, name="Bo", gender="boy", age=5, interests=None):
    return client.post(
        f"/devices/{device}/children",
        json={"name": name, "gender": gender, "age": age, "interests": interests or []},
    )


def test_create_list_get_roundtrip(client):
    r = _make(client, "dev1", name="Vy", gender="girl", interests=["Elsa"])
    assert r.status_code == 201, r.text
    child = r.json()
    assert child["id"] and child["name"] == "Vy" and child["gender"] == "girl"
    assert child["memory"] == {"summary": "", "updated_at": None}

    listing = client.get("/devices/dev1/children").json()
    assert len(listing) == 1 and listing[0]["id"] == child["id"]


def test_isolation_between_devices_same_name(client):
    a = _make(client, "devA", name="Bo").json()
    b = _make(client, "devB", name="Bo").json()
    assert a["id"] != b["id"]
    # Each device only sees its own child.
    assert {c["id"] for c in client.get("/devices/devA/children").json()} == {a["id"]}
    assert {c["id"] for c in client.get("/devices/devB/children").json()} == {b["id"]}


def test_update_profile_partial_merge_keeps_other_fields(client):
    c = _make(client, "dev1", name="Bo", age=5, interests=["xe"]).json()
    r = client.patch(f"/devices/dev1/children/{c['id']}", json={"age": 6})
    assert r.status_code == 200
    updated = r.json()
    assert updated["age"] == 6
    assert updated["name"] == "Bo" and updated["interests"] == ["xe"]  # untouched


def test_memory_edit_then_clear(client):
    c = _make(client, "dev1").json()
    r = client.patch(
        f"/devices/dev1/children/{c['id']}/memory", json={"summary": "thích khủng long"}
    )
    assert r.status_code == 200 and r.json()["memory"]["summary"] == "thích khủng long"
    # Clear keeps the child but empties the summary.
    r = client.delete(f"/devices/dev1/children/{c['id']}/memory")
    assert r.status_code == 200 and r.json()["memory"]["summary"] == ""
    assert client.get(f"/devices/dev1/children").json()[0]["id"] == c["id"]


def test_memory_edit_does_not_clobber_profile(client):
    c = _make(client, "dev1", name="Vy", interests=["Elsa"]).json()
    client.patch(f"/devices/dev1/children/{c['id']}/memory", json={"summary": "abc"})
    after = client.get("/devices/dev1/children").json()[0]
    assert after["name"] == "Vy" and after["interests"] == ["Elsa"]  # profile intact
    assert after["memory"]["summary"] == "abc"


def test_delete_child_removes_profile_and_memory(client):
    c = _make(client, "dev1").json()
    r = client.delete(f"/devices/dev1/children/{c['id']}")
    assert r.status_code == 204
    assert client.get("/devices/dev1/children").json() == []
    # Idempotent: deleting again is still 204.
    assert client.delete(f"/devices/dev1/children/{c['id']}").status_code == 204


def test_soft_cap_five(client):
    for i in range(5):
        assert _make(client, "dev1", name=f"k{i}").status_code == 201
    r = _make(client, "dev1", name="sixth")
    assert r.status_code == 409


def test_validation_rejects_bad_input(client):
    assert _make(client, "dev1", gender="robot").status_code == 422
    assert _make(client, "dev1", age=99).status_code == 422
    assert _make(client, "dev1", name="").status_code == 422
    assert _make(client, "dev1", interests=["x" * 40]).status_code == 422


def test_vietnamese_diacritics_roundtrip(client):
    c = _make(client, "dev1", name="Bé Vy", interests=["khủng long"]).json()
    got = client.get("/devices/dev1/children").json()[0]
    assert got["name"] == "Bé Vy" and got["interests"] == ["khủng long"]


def test_get_unknown_device_is_empty_not_error(client):
    assert client.get("/devices/never-seen/children").status_code == 200
    assert client.get("/devices/never-seen/children").json() == []


def test_patch_unknown_child_404(client):
    assert client.patch("/devices/dev1/children/nope", json={"age": 6}).status_code == 404


def test_invalid_ids_rejected_422(client):
    # An id with chars outside [A-Za-z0-9_-] must be rejected at the boundary,
    # never silently sanitized (which could alias two devices to one path).
    # These reach the route (no slash) and must 422, not be stripped + served.
    assert client.get("/devices/a.b/children").status_code == 422
    assert client.get("/devices/a@b/children").status_code == 422
    assert client.patch("/devices/devA/children/c.d", json={"age": 6}).status_code == 422
    # A path separator collapses the route → 404 (safe: never aliases data).
    assert client.get("/devices/a%2Fb/children").status_code == 404
    # A clean UUID-ish id is fine.
    assert client.get("/devices/devA-1_2/children").status_code == 200


def test_token_gate_enforced_when_set(tmp_path, monkeypatch):
    monkeypatch.setenv("MEMORY_BACKEND", "json")
    monkeypatch.setenv("MONAMI_AUTH_TOKEN", "secret")
    import child_store

    importlib.reload(child_store)
    monkeypatch.setattr(child_store, "_PROFILES_DIR", tmp_path / "profiles")
    import child_rest_api

    importlib.reload(child_rest_api)
    import main

    importlib.reload(main)
    c = TestClient(main.app)
    assert c.get("/devices/dev1/children").status_code == 401
    assert c.get("/devices/dev1/children?token=wrong").status_code == 401
    assert c.get("/devices/dev1/children?token=secret").status_code == 200

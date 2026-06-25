"""Phase 1 — layered memory (facts + summary + done_topics).

Covers the red-team-hardened invariants:
  - dotted-path writes preserve sibling memory sub-fields (no whole-map replace);
  - load_memory_struct reads legacy + layered docs;
  - clear_memory resets all three layers;
  - summarizer structured output parses fenced/preamble JSON and keeps prior facts
    on failure;
  - build_system_prompt is byte-identical for an empty-facts child, renders facts
    when present;
  - facts merge is a capped/uncapped union.
"""

from __future__ import annotations

import asyncio
import importlib
import sys
from pathlib import Path
from unittest import mock

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


# --- child_store: JSON backend (real deep-merge semantics) ------------------


@pytest.fixture()
def store(tmp_path, monkeypatch):
    monkeypatch.setenv("MEMORY_BACKEND", "json")
    monkeypatch.delenv("FIRESTORE_PREFIX", raising=False)
    import child_store

    importlib.reload(child_store)
    monkeypatch.setattr(child_store, "_PROFILES_DIR", tmp_path / "profiles")
    return child_store


def test_struct_write_preserves_siblings(store):
    c = store.create_child("d", {"name": "Vy", "gender": "girl", "age": 5})
    cid = c["id"]
    # Write facts only.
    store.save_memory_struct("d", cid, facts={"pets": ["Mướp"], "likes": [], "dislikes": []})
    # Write summary only — must NOT drop facts.
    store.save_memory_struct("d", cid, summary="Bé vui.")
    # Write done_topics only — must NOT drop facts or summary.
    store.save_memory_struct("d", cid, done_topics=["english:animals"])

    m = store.load_memory_struct("d", cid)
    assert m["facts"]["pets"] == ["Mướp"]
    assert m["summary"] == "Bé vui."
    assert m["done_topics"] == ["english:animals"]


def test_save_memory_summary_only_preserves_facts(store):
    c = store.create_child("d", {"name": "Bo", "gender": "boy", "age": 5})
    cid = c["id"]
    store.save_memory_struct("d", cid, facts={"pets": ["Rex"], "likes": [], "dislikes": []})
    # The legacy summary-only wrapper must also preserve siblings now.
    store.save_memory("d", cid, "recap", updated_at="t")
    m = store.load_memory_struct("d", cid)
    assert m["facts"]["pets"] == ["Rex"]
    assert m["summary"] == "recap"


def test_clear_memory_resets_all_layers(store):
    c = store.create_child("d", {"name": "Bo", "gender": "boy", "age": 5})
    cid = c["id"]
    store.save_memory_struct(
        "d", cid, summary="s", facts={"pets": ["Rex"], "likes": ["xe"], "dislikes": []},
        done_topics=["english:animals"],
    )
    assert store.clear_memory("d", cid) is True
    m = store.load_memory_struct("d", cid)
    assert m["summary"] == ""
    assert m["facts"] == {"pets": [], "likes": [], "dislikes": []}
    assert m["done_topics"] == []


def test_legacy_doc_loads_empty_layers(store):
    # A doc with only the old text summary still loads; facts/done_topics empty.
    c = store.create_child("d", {"name": "Vy", "gender": "girl", "age": 5})
    cid = c["id"]
    store.save_memory("d", cid, "ghi nhớ cũ", updated_at="t")
    m = store.load_memory_struct("d", cid)
    assert m["summary"] == "ghi nhớ cũ"
    assert m["facts"] == {"pets": [], "likes": [], "dislikes": []}
    assert m["done_topics"] == []


def test_struct_write_noop_on_missing_child(store):
    # Guest / unknown child: writing must not create a ghost doc.
    store.save_memory_struct("d", "ghost", summary="nope", facts={"pets": ["x"]})
    assert store.get_child("d", "ghost") is None
    assert store.list_children("d") == []


def test_prefixed_helper_honors_env(monkeypatch):
    import child_store

    importlib.reload(child_store)
    monkeypatch.setenv("FIRESTORE_PREFIX", "dev_")
    assert child_store.prefixed("devices") == "dev_devices"
    assert child_store.prefixed("curriculum") == "dev_curriculum"
    monkeypatch.delenv("FIRESTORE_PREFIX", raising=False)
    assert child_store.prefixed("devices") == "devices"


# --- child_store: Firestore backend uses DOTTED-PATH update() ----------------


class _FakeDocRef:
    def __init__(self, doc):
        self._doc = doc
        self.update_calls = []

    def get(self):
        snap = mock.MagicMock()
        snap.exists = self._doc is not None
        snap.to_dict.return_value = self._doc
        return snap

    def update(self, paths):
        self.update_calls.append(dict(paths))


def test_firestore_write_uses_dotted_paths(monkeypatch):
    monkeypatch.setenv("MEMORY_BACKEND", "firestore")
    import child_store

    importlib.reload(child_store)
    existing = {"id": "c1", "name": "Vy", "memory": {"summary": "old"}}
    ref = _FakeDocRef(existing)
    monkeypatch.setattr(child_store, "_doc_ref", lambda d, c: ref)

    child_store.save_memory_struct("d", "c1", summary="new")
    # Proves dotted-path update (NOT set(merge=True) on a whole 'memory' map):
    assert ref.update_calls, "expected a Firestore update() call"
    written = ref.update_calls[-1]
    assert "memory.summary" in written
    assert written["memory.summary"] == "new"
    # No whole-map key that would replace siblings.
    assert "memory" not in written


# --- memory_summarizer: structured output, fenced JSON, prior-on-failure -----


def _fake_resp(text=None, parsed=None, truncated=False):
    resp = mock.MagicMock()
    resp.text = text
    resp.parsed = parsed
    cand = mock.MagicMock()
    import gemini_session_config  # noqa: F401
    from google.genai import types

    cand.finish_reason = (
        types.FinishReason.MAX_TOKENS if truncated else types.FinishReason.STOP
    )
    resp.candidates = [cand]
    return resp


def _summarizer_client(resp):
    client = mock.MagicMock()
    client.aio.models.generate_content = mock.AsyncMock(return_value=resp)
    return client


PRIOR = {
    "facts": {"pets": ["Mướp"], "likes": ["khủng long"], "dislikes": []},
    "summary": "prior recap",
}


def test_summarizer_parses_fenced_json():
    import memory_summarizer

    # Model wrapped JSON in a ```json fence (realistic). _parse must still read it.
    fenced = '```json\n{"summary":"new","pets":["Mướp"],"likes":["xe"],"dislikes":[]}\n```'
    resp = _fake_resp(text=fenced, parsed=None)
    out = asyncio.run(
        memory_summarizer.summarize(_summarizer_client(resp), PRIOR, "transcript")
    )
    # NOT "kept prior" — facts/summary actually parsed.
    assert out["summary"] == "new"
    assert out["facts"]["likes"] == ["xe"]


def test_summarizer_uses_sdk_parsed_when_present():
    import memory_summarizer

    resp = _fake_resp(
        parsed={"summary": "p", "pets": [], "likes": ["a"], "dislikes": []}
    )
    out = asyncio.run(
        memory_summarizer.summarize(_summarizer_client(resp), PRIOR, "t")
    )
    assert out["summary"] == "p"
    assert out["facts"]["likes"] == ["a"]


def test_summarizer_failure_keeps_prior_facts():
    import memory_summarizer

    # Non-JSON garbage → unparseable → keep prior facts (NOT reset to empty).
    resp = _fake_resp(text="not json at all", parsed=None)
    out = asyncio.run(
        memory_summarizer.summarize(_summarizer_client(resp), PRIOR, "t")
    )
    assert out["facts"] == PRIOR["facts"]
    assert out["summary"] == PRIOR["summary"]


def test_summarizer_exception_keeps_prior():
    import memory_summarizer

    client = mock.MagicMock()
    client.aio.models.generate_content = mock.AsyncMock(side_effect=RuntimeError("boom"))
    out = asyncio.run(memory_summarizer.summarize(client, PRIOR, "t"))
    assert out["facts"] == PRIOR["facts"]
    assert out["summary"] == PRIOR["summary"]


def test_summarizer_truncated_keeps_prior():
    import memory_summarizer

    resp = _fake_resp(
        parsed={"summary": "x", "pets": [], "likes": [], "dislikes": []},
        truncated=True,
    )
    out = asyncio.run(
        memory_summarizer.summarize(_summarizer_client(resp), PRIOR, "t")
    )
    assert out == {"facts": PRIOR["facts"], "summary": PRIOR["summary"]}


# --- gemini_session: facts merge (union; pets uncapped, tastes capped) -------


def test_merge_facts_union_pets_uncapped():
    import gemini_session

    prior = {"pets": [f"p{i}" for i in range(10)], "likes": ["a"], "dislikes": []}
    new = {"pets": ["p10"], "likes": ["b"], "dislikes": ["x"]}
    out = gemini_session._merge_facts(prior, new)
    assert len(out["pets"]) == 11  # uncapped — no identity fact evicted
    assert out["likes"] == ["a", "b"]
    assert out["dislikes"] == ["x"]


def test_merge_facts_caps_tastes_and_dedups():
    import gemini_session

    prior = {"pets": [], "likes": [f"l{i}" for i in range(8)], "dislikes": []}
    new = {"pets": [], "likes": ["L0", "l8"], "dislikes": []}  # 'L0' dup (case-insens)
    out = gemini_session._merge_facts(prior, new)
    assert len(out["likes"]) == 8  # capped — prior wins, transient bumped
    assert out["likes"][0] == "l0"  # original kept, dup 'L0' dropped


def test_merge_facts_long_prefix_not_collapsed():
    import gemini_session

    # Two distinct long likes sharing a 40-char prefix must NOT dedup to one
    # (dedup on the FULL string, truncate only after).
    a = "x" * 40 + "ALPHA"
    b = "x" * 40 + "BETA"
    out = gemini_session._merge_facts(
        {"pets": [], "likes": [a, b], "dislikes": []}, {"pets": [], "likes": [], "dislikes": []}
    )
    assert len(out["likes"]) == 2  # both kept (distinct facts)
    assert all(len(s) <= 40 for s in out["likes"])  # each still trimmed for the prompt


# --- build_system_prompt: byte-identity + facts rendering --------------------


def _profile():
    import child_profile

    importlib.reload(child_profile)
    return child_profile.profile_from_record(
        {"id": "c", "name": "Vy", "age": 5, "gender": "girl", "interests": ["vẽ"]}
    )


def test_prompt_byte_identical_for_empty_facts():
    import gemini_session_config as cfg

    p = _profile()
    empty = {"pets": [], "likes": [], "dislikes": []}
    base = cfg.build_system_prompt(p, "")
    with_empty = cfg.build_system_prompt(p, "", facts=empty)
    assert with_empty == base  # empty-keys dict must not change a single byte
    none_facts = cfg.build_system_prompt(p, "", facts=None)
    assert none_facts == base


def test_prompt_renders_facts_when_present():
    import gemini_session_config as cfg

    p = _profile()
    facts = {"pets": ["Mướp"], "likes": ["khủng long"], "dislikes": []}
    out = cfg.build_system_prompt(p, "", facts=facts)
    assert "Mướp" in out
    assert "khủng long" in out
    # Dislikes empty → its label is NOT rendered.
    assert "Dislikes" not in out

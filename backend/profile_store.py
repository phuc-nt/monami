"""Per-child memory store: load/save a short AI-generated summary per child.

Two backends behind one interface (`load_memory` / `save_memory`):
  - "json" (default for local dev): one file per child at `backend/profiles/<id>.json`.
  - "firestore" (for Cloud Run): one document per child in a Firestore collection.

Pick with the env var MEMORY_BACKEND ("json" | "firestore"). The session code
(gemini_session.py) only ever calls load_memory/save_memory and is unaware which
backend is active, so swapping is config-only.

Privacy: memory holds a child's name + chat summaries → private. The local
`profiles/` dir is gitignored; Firestore docs are locked to the service account.
No audio is ever stored; only text.
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path

logger = logging.getLogger("profile_store")

# Firestore collection holding one memory doc per child (id = profile_id).
_FIRESTORE_COLLECTION = "child_memory"

_PROFILES_DIR = Path(__file__).parent / "profiles"


_VALID_BACKENDS = {"json", "firestore"}


def _backend() -> str:
    value = os.environ.get("MEMORY_BACKEND", "json").strip().lower()
    if value not in _VALID_BACKENDS:
        # A typo on Cloud Run (e.g. "firstore") would silently fall back to the
        # ephemeral JSON dir and lose memory on each restart — warn loudly once.
        logger.warning(
            "unknown MEMORY_BACKEND %r — falling back to 'json' (memory will NOT "
            "persist on Cloud Run); set it to 'json' or 'firestore'", value,
        )
        return "json"
    return value


# --- Public interface -------------------------------------------------------


def load_memory(profile_id: str) -> str:
    """Return the stored memory summary for a child ("" if none / unreadable)."""
    if _backend() == "firestore":
        return _firestore_load(profile_id)
    return _json_load(profile_id)


def save_memory(profile_id: str, summary: str, updated_at: str | None = None) -> None:
    """Persist the memory summary for a child. Best-effort; logs on failure.

    updated_at is an optional caller-supplied timestamp (stamped outside this
    module so the store stays time-source agnostic).
    """
    if _backend() == "firestore":
        _firestore_save(profile_id, summary, updated_at)
    else:
        _json_save(profile_id, summary, updated_at)


# --- JSON backend (local dev) ----------------------------------------------


def _path_for(profile_id: str) -> Path:
    # Guard against path traversal from an unexpected id.
    safe = "".join(ch for ch in profile_id if ch.isalnum() or ch in ("-", "_"))
    return _PROFILES_DIR / f"{safe or 'unknown'}.json"


def _json_load(profile_id: str) -> str:
    path = _path_for(profile_id)
    if not path.exists():
        return ""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return str(data.get("summary", "")).strip()
    except (json.JSONDecodeError, OSError) as exc:
        logger.warning("could not read memory for %s: %s", profile_id, exc)
        return ""


def _json_save(profile_id: str, summary: str, updated_at: str | None) -> None:
    path = _path_for(profile_id)
    record = {
        "profile_id": profile_id,
        "summary": summary.strip(),
        "updated_at": updated_at,
    }
    try:
        _PROFILES_DIR.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8"
        )
    except OSError as exc:
        logger.warning("could not save memory for %s: %s", profile_id, exc)


# --- Firestore backend (Cloud Run) -----------------------------------------

# Lazily created so importing this module never requires Firestore (local dev
# with MEMORY_BACKEND=json doesn't touch GCP).
_firestore_client = None


def _client():
    global _firestore_client
    if _firestore_client is None:
        from google.cloud import firestore

        # Uses ADC: the Cloud Run service account in prod, local ADC in dev.
        _firestore_client = firestore.Client()
    return _firestore_client


def _doc_id(profile_id: str) -> str:
    # Firestore doc ids can't contain '/'; profile ids are a fixed small set, but
    # sanitize defensively to mirror the JSON path guard.
    return "".join(ch for ch in profile_id if ch.isalnum() or ch in ("-", "_")) or "unknown"


def _firestore_load(profile_id: str) -> str:
    try:
        snap = _client().collection(_FIRESTORE_COLLECTION).document(_doc_id(profile_id)).get()
        if not snap.exists:
            return ""
        return str((snap.to_dict() or {}).get("summary", "")).strip()
    except Exception as exc:  # noqa: BLE001 - storage must never break the session
        logger.warning("firestore load failed for %s: %s", profile_id, exc)
        return ""


def _firestore_save(profile_id: str, summary: str, updated_at: str | None) -> None:
    try:
        _client().collection(_FIRESTORE_COLLECTION).document(_doc_id(profile_id)).set(
            {
                "profile_id": profile_id,
                "summary": summary.strip(),
                "updated_at": updated_at,
            }
        )
    except Exception as exc:  # noqa: BLE001 - best-effort; a save failure isn't fatal
        logger.warning("firestore save failed for %s: %s", profile_id, exc)

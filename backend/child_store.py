"""Device-scoped child store: per-device children with merged profile + memory.

Data model (one doc per child, scoped under its device):

    devices/{device_id}/children/{child_id}
        name, gender, age, interests[], created_at        <- profile
        memory: { summary, updated_at }                   <- merged memory

The device is an anonymous per-install identity (a UUID the app self-declares);
children live under it so two devices never collide on a child id. This module
owns child CRUD (create/list/get/update/delete) and the merged memory sub-field.

Two backends behind one interface, picked by MEMORY_BACKEND ("json" | "firestore"):
  - "json"      (local dev): nested files under backend/profiles/devices/...
  - "firestore" (Cloud Run): the subcollection path above.

Privacy: a child doc holds a name + chat summaries -> private. The local dir is
gitignored; Firestore docs are locked to the service account. No audio is stored.

Memory writes use a MERGE (never a full overwrite) so a concurrent profile edit
and an end-of-session memory save can't clobber each other.
"""

from __future__ import annotations

import json
import logging
import os
import uuid
from pathlib import Path

logger = logging.getLogger("child_store")

_DEVICES_COLLECTION = "devices"
_CHILDREN_SUBCOLLECTION = "children"
_PROFILES_DIR = Path(__file__).parent / "profiles"

# Soft cap on children per device (also enforced at the API layer).
MAX_CHILDREN_PER_DEVICE = 5

_VALID_BACKENDS = {"json", "firestore"}


def _backend() -> str:
    value = os.environ.get("MEMORY_BACKEND", "json").strip().lower()
    if value not in _VALID_BACKENDS:
        logger.warning(
            "unknown MEMORY_BACKEND %r — falling back to 'json' (data will NOT "
            "persist on Cloud Run); set it to 'json' or 'firestore'", value,
        )
        return "json"
    return value


def _sanitize(token: str) -> str:
    """Path/doc-id-safe id: alnum + dash + underscore, never empty, never reserved.

    Mirrors the historical guard so a surprising id can't traverse paths (JSON) or
    hit Firestore's reserved '__name__' shape.
    """
    safe = "".join(ch for ch in token if ch.isalnum() or ch in ("-", "_"))
    if safe.startswith("__") and safe.endswith("__"):
        safe = safe.strip("_")
    return safe or "unknown"


def new_child_id() -> str:
    """Server-generated child id (clients never supply their own)."""
    return uuid.uuid4().hex


# --- Public interface -------------------------------------------------------
#
# A "child" dict has shape:
#   {id, name, gender, age, interests: [..], created_at,
#    memory: {summary, updated_at}}
# Memory is always present (defaults to {"summary": "", "updated_at": None}).


def list_children(device_id: str) -> list[dict]:
    """All children for a device (empty list if the device has none)."""
    if _backend() == "firestore":
        return _fs_list(device_id)
    return _json_list(device_id)


def get_child(device_id: str, child_id: str) -> dict | None:
    """A single child dict, or None if it doesn't exist."""
    if _backend() == "firestore":
        return _fs_get(device_id, child_id)
    return _json_get(device_id, child_id)


def create_child(device_id: str, profile: dict) -> dict:
    """Create a child under a device. `profile` holds name/gender/age/interests.

    Returns the stored child dict (with the server-assigned id + created_at +
    empty memory). Caller is responsible for the soft-cap check (the API layer
    does it so it can return a clean 409); this writes unconditionally.
    """
    child_id = new_child_id()
    record = {
        "id": child_id,
        "name": profile["name"],
        "gender": profile["gender"],
        "age": profile["age"],
        "interests": list(profile.get("interests", [])),
        "created_at": profile.get("created_at"),
        "memory": {"summary": "", "updated_at": None},
    }
    if _backend() == "firestore":
        _fs_set(device_id, child_id, record)
    else:
        _json_set(device_id, child_id, record)
    return record


def update_child(device_id: str, child_id: str, fields: dict) -> dict | None:
    """Partial-merge update of profile fields (name/gender/age/interests).

    Never touches `memory`. Returns the updated child, or None if missing.
    """
    child = get_child(device_id, child_id)
    if child is None:
        return None
    allowed = {k: fields[k] for k in ("name", "gender", "age", "interests") if k in fields}
    if not allowed:
        return child
    child.update(allowed)
    # A full rewrite of the profile keys is safe here because we read-merged
    # above; memory is preserved because `child` already carries it.
    if _backend() == "firestore":
        _fs_merge(device_id, child_id, allowed)
    else:
        _json_set(device_id, child_id, child)
    return child


def delete_child(device_id: str, child_id: str) -> bool:
    """Delete a child (and its merged memory). True if it existed, else False.

    Memory is merged into the child doc, so deleting the doc removes memory
    atomically — no orphan rows.
    """
    if _backend() == "firestore":
        return _fs_delete(device_id, child_id)
    return _json_delete(device_id, child_id)


def load_memory(device_id: str, child_id: str) -> str:
    """The child's stored memory summary ("" if none / unreadable)."""
    child = get_child(device_id, child_id)
    if not child:
        return ""
    return str((child.get("memory") or {}).get("summary", "")).strip()


def save_memory(device_id: str, child_id: str, summary: str, updated_at: str | None) -> None:
    """Merge-write only the memory sub-field (never clobbers profile fields).

    No-op if the child doesn't exist — same contract on BOTH backends. (Firestore
    `set(merge=True)` would otherwise upsert a profile-less ghost doc, diverging
    from the JSON backend; we guard against that so a guest/deleted-child write
    never creates anything.)
    """
    if get_child(device_id, child_id) is None:
        return  # guest / deleted child: nothing to write
    payload = {"memory": {"summary": summary.strip(), "updated_at": updated_at}}
    if _backend() == "firestore":
        _fs_merge(device_id, child_id, payload)
    else:
        child = get_child(device_id, child_id)
        child["memory"] = {"summary": summary.strip(), "updated_at": updated_at}
        _json_set(device_id, child_id, child)


def clear_memory(device_id: str, child_id: str) -> bool:
    """Empty the memory summary but keep the child + profile. True if it existed."""
    if get_child(device_id, child_id) is None:
        return False
    save_memory(device_id, child_id, "", updated_at=None)
    return True


# --- JSON backend (local dev) ----------------------------------------------


def _child_dir(device_id: str) -> Path:
    return _PROFILES_DIR / "devices" / _sanitize(device_id) / "children"


def _child_path(device_id: str, child_id: str) -> Path:
    return _child_dir(device_id) / f"{_sanitize(child_id)}.json"


def _json_list(device_id: str) -> list[dict]:
    d = _child_dir(device_id)
    if not d.exists():
        return []
    out = []
    for path in sorted(d.glob("*.json")):
        try:
            out.append(json.loads(path.read_text(encoding="utf-8")))
        except (json.JSONDecodeError, OSError) as exc:
            logger.warning("could not read child %s: %s", path.name, exc)
    return out


def _json_get(device_id: str, child_id: str) -> dict | None:
    path = _child_path(device_id, child_id)
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        logger.warning("could not read child %s: %s", child_id, exc)
        return None


def _json_set(device_id: str, child_id: str, record: dict) -> None:
    path = _child_path(device_id, child_id)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    except OSError as exc:
        logger.warning("could not save child %s: %s", child_id, exc)


def _json_delete(device_id: str, child_id: str) -> bool:
    path = _child_path(device_id, child_id)
    if not path.exists():
        return False
    try:
        path.unlink()
        return True
    except OSError as exc:
        logger.warning("could not delete child %s: %s", child_id, exc)
        return False


# --- Firestore backend (Cloud Run) -----------------------------------------

_firestore_client = None


def _client():
    global _firestore_client
    if _firestore_client is None:
        from google.cloud import firestore

        _firestore_client = firestore.Client()
    return _firestore_client


def _doc_ref(device_id: str, child_id: str):
    return (
        _client()
        .collection(_DEVICES_COLLECTION)
        .document(_sanitize(device_id))
        .collection(_CHILDREN_SUBCOLLECTION)
        .document(_sanitize(child_id))
    )


def _fs_list(device_id: str) -> list[dict]:
    try:
        col = (
            _client()
            .collection(_DEVICES_COLLECTION)
            .document(_sanitize(device_id))
            .collection(_CHILDREN_SUBCOLLECTION)
        )
        return [snap.to_dict() for snap in col.stream() if snap.exists]
    except Exception as exc:  # noqa: BLE001 - storage must never break a request
        logger.warning("firestore list failed for device %s: %s", _sanitize(device_id), exc)
        return []


def _fs_get(device_id: str, child_id: str) -> dict | None:
    try:
        snap = _doc_ref(device_id, child_id).get()
        return snap.to_dict() if snap.exists else None
    except Exception as exc:  # noqa: BLE001
        logger.warning("firestore get failed for %s: %s", _sanitize(child_id), exc)
        return None


def _fs_set(device_id: str, child_id: str, record: dict) -> None:
    try:
        _doc_ref(device_id, child_id).set(record)
    except Exception as exc:  # noqa: BLE001
        logger.warning("firestore set failed for %s: %s", _sanitize(child_id), exc)


def _fs_merge(device_id: str, child_id: str, fields: dict) -> None:
    """Merge-write: only the given keys change; everything else is preserved."""
    try:
        _doc_ref(device_id, child_id).set(fields, merge=True)
    except Exception as exc:  # noqa: BLE001
        logger.warning("firestore merge failed for %s: %s", _sanitize(child_id), exc)


def _fs_delete(device_id: str, child_id: str) -> bool:
    try:
        ref = _doc_ref(device_id, child_id)
        existed = ref.get().exists
        ref.delete()
        return existed
    except Exception as exc:  # noqa: BLE001
        logger.warning("firestore delete failed for %s: %s", _sanitize(child_id), exc)
        return False

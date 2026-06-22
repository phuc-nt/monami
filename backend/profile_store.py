"""Per-child memory store: local JSON, one file per child.

The companion's memory of a child (a short, AI-generated summary of past
sessions) lives in `backend/profiles/<id>.json`. This is a deliberately thin
layer — load/save text only — so it can be swapped for a DB/cloud later without
touching the session code.

Privacy: these files hold a child's name + chat summaries → private. The
`profiles/` directory is gitignored and must never be committed. No audio is
stored; only text.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path

logger = logging.getLogger("profile_store")

_PROFILES_DIR = Path(__file__).parent / "profiles"


def _path_for(profile_id: str) -> Path:
    # Guard against path traversal from an unexpected id.
    safe = "".join(ch for ch in profile_id if ch.isalnum() or ch in ("-", "_"))
    return _PROFILES_DIR / f"{safe or 'unknown'}.json"


def load_memory(profile_id: str) -> str:
    """Return the stored memory summary for a child ("" if none / unreadable)."""
    path = _path_for(profile_id)
    if not path.exists():
        return ""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return str(data.get("summary", "")).strip()
    except (json.JSONDecodeError, OSError) as exc:
        logger.warning("could not read memory for %s: %s", profile_id, exc)
        return ""


def save_memory(profile_id: str, summary: str, updated_at: str | None = None) -> None:
    """Persist the memory summary for a child. Best-effort; logs on failure.

    updated_at is an optional caller-supplied timestamp (stamped outside this
    module so the store stays time-source agnostic).
    """
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

#!/usr/bin/env python3
"""Seed Firestore curriculum from the bundled JSON files (IDs preserved).

Pushes every topic in `backend/curriculum/{english,science}.json` to
`{PREFIX}curriculum/{mode}/topics/{id}`, where {id} is the topic's existing `id`
so a child's recorded `done_topics` keep matching. The resolved collection honors
FIRESTORE_PREFIX (dev → `dev_curriculum`, prod → `curriculum`), the SAME helper
the backend reads through (child_store.prefixed) — one source of truth.

Idempotent: each topic is a set()-by-id, so re-running overwrites in place and
never duplicates or deletes. To DISABLE a topic, set `enabled: false` on its doc
(the loader skips it); this script only ever writes the JSON-present topics.

Safety: prints the resolved collection, then — when the collection is NOT
dev-prefixed (i.e. a prod write) — REQUIRES an explicit confirm (`--yes` or typing
the collection name) before writing. Seed dev first, verify, then prod.

Usage:
    # dev (FIRESTORE_PREFIX=dev_ in env or below):
    FIRESTORE_PREFIX=dev_ .pyenv-backend/bin/python scripts/seed_curriculum.py
    # prod (must confirm):
    .pyenv-backend/bin/python scripts/seed_curriculum.py --yes
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Make the backend modules importable (scripts/ is a sibling of them).
_BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_BACKEND))

# Load backend/.env so FIRESTORE_PREFIX / GOOGLE_CLOUD_PROJECT are picked up the
# same way the running backend does (no-op if python-dotenv is absent).
try:
    from dotenv import load_dotenv

    load_dotenv(_BACKEND / ".env")
except ImportError:  # pragma: no cover
    pass

import child_store  # noqa: E402

_CURRICULUM_DIR = _BACKEND / "curriculum"
_MODES = ("english", "science")


def _load_json(mode: str) -> list[dict]:
    path = _CURRICULUM_DIR / f"{mode}.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise SystemExit(f"{path.name}: expected a JSON list of topics")
    topics = [t for t in data if isinstance(t, dict) and t.get("id")]
    if not topics:
        raise SystemExit(f"{path.name}: no topics with an id")
    return topics


def _confirm_prod(collection: str, assume_yes: bool) -> None:
    """Block a non-dev (prod) write unless the user explicitly confirms.

    A dev-prefixed collection (`dev_curriculum`) writes without a prompt. Anything
    else is treated as prod: require --yes OR typing the collection name back.
    """
    if collection.startswith("dev_"):
        return
    if assume_yes:
        print(f"--yes given: writing to PROD collection {collection!r}.")
        return
    if not sys.stdin.isatty():
        raise SystemExit(
            f"Refusing to write to non-dev collection {collection!r} without "
            f"--yes (no interactive TTY to confirm)."
        )
    typed = input(
        f"About to write to PROD collection {collection!r}.\n"
        f"Type the collection name to confirm (or anything else to abort): "
    ).strip()
    if typed != collection:
        raise SystemExit("Aborted (confirmation did not match).")


def main() -> None:
    parser = argparse.ArgumentParser(description="Seed Firestore curriculum from JSON.")
    parser.add_argument(
        "--yes",
        action="store_true",
        help="confirm a PROD (non-dev_) write without an interactive prompt",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print what would be written; touch nothing",
    )
    args = parser.parse_args()

    collection = child_store.prefixed("curriculum")
    print(f"Resolved curriculum collection: {collection!r}")
    if not args.dry_run:
        _confirm_prod(collection, args.yes)

    client = None if args.dry_run else child_store._client()
    total = 0
    for mode in _MODES:
        topics = _load_json(mode)
        print(f"  {mode}: {len(topics)} topics", end="")
        if args.dry_run:
            print("  (dry-run, not written)")
            total += len(topics)
            continue
        col = client.collection(collection).document(mode).collection("topics")
        for index, topic in enumerate(topics):
            # Stamp `order` from the JSON array index so the curated sequence is
            # preserved (the loader sorts by `order` then id; without this it would
            # fall back to alphabetical-by-id and reorder the lessons). Don't
            # clobber an explicit `order` already in the JSON.
            doc = {**topic, "order": topic.get("order", index)}
            col.document(str(topic["id"])).set(doc)  # set-by-id: idempotent
        print("  ✓ written")
        total += len(topics)

    verb = "would seed" if args.dry_run else "seeded"
    print(f"Done: {verb} {total} topics into {collection!r}.")


if __name__ == "__main__":
    main()

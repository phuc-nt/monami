"""REST API for per-device child profiles + memory edit/clear.

Mounted on the same FastAPI app as the WS voice relay and gated by the SAME
shared token (query param `token`, like the WS). All data is scoped under a
device the app self-declares (`device_id` path segment).

Endpoints:
  GET    /devices/{device_id}/children                      -> list
  POST   /devices/{device_id}/children                      -> create (201)
  PATCH  /devices/{device_id}/children/{child_id}           -> update profile
  DELETE /devices/{device_id}/children/{child_id}           -> delete (204, idempotent)
  PATCH  /devices/{device_id}/children/{child_id}/memory    -> set memory text
  DELETE /devices/{device_id}/children/{child_id}/memory    -> clear memory (keep child)

Validation rejects bad input with 422; the soft cap returns 409. childId is
server-generated — clients never supply it.
"""

from __future__ import annotations

import logging
import os
import re
import secrets
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query, status
from pydantic import BaseModel, Field, field_validator

import child_store
from child_profile import VALID_GENDERS

logger = logging.getLogger("child_rest_api")

router = APIRouter(tags=["children"])

_MAX_NAME = 20
_MAX_INTEREST = 30
_MAX_INTERESTS = 10
_MIN_AGE, _MAX_AGE = 1, 12

# device/child ids are opaque tokens (app-generated UUIDs / server uuid4 hex).
# Reject anything outside this charset at the boundary rather than silently
# sanitizing — two ids that differ only by stripped chars must NOT alias to the
# same storage path (cross-device data bleed).
_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,128}$")


def _require_token(token: str | None) -> None:
    """Same shared-token gate as the WS. Open in local dev (token unset)."""
    expected = os.environ.get("MONAMI_AUTH_TOKEN")
    if not expected:
        return
    if not secrets.compare_digest(token or "", expected):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="bad token")


def _check_ids(*ids: str) -> None:
    """422 on any id that isn't a safe opaque token (prevents path aliasing)."""
    for i in ids:
        if not _ID_RE.match(i):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="invalid id"
            )


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# --- Schemas ---------------------------------------------------------------


class ChildCreate(BaseModel):
    name: str = Field(min_length=1, max_length=_MAX_NAME)
    gender: str
    age: int = Field(ge=_MIN_AGE, le=_MAX_AGE)
    interests: list[str] = Field(default_factory=list, max_length=_MAX_INTERESTS)

    @field_validator("name")
    @classmethod
    def _name_not_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("name must not be blank")
        return v

    @field_validator("gender")
    @classmethod
    def _gender_valid(cls, v: str) -> str:
        if v not in VALID_GENDERS:
            raise ValueError(f"gender must be one of {VALID_GENDERS}")
        return v

    @field_validator("interests")
    @classmethod
    def _interests_clean(cls, v: list[str]) -> list[str]:
        cleaned = [s.strip() for s in v if s and s.strip()]
        for s in cleaned:
            if len(s) > _MAX_INTEREST:
                raise ValueError(f"each interest must be <= {_MAX_INTEREST} chars")
        return cleaned


class ChildUpdate(BaseModel):
    """All fields optional (partial PATCH). Same constraints as create."""

    name: str | None = Field(default=None, min_length=1, max_length=_MAX_NAME)
    gender: str | None = None
    age: int | None = Field(default=None, ge=_MIN_AGE, le=_MAX_AGE)
    interests: list[str] | None = Field(default=None, max_length=_MAX_INTERESTS)

    @field_validator("name")
    @classmethod
    def _name_not_blank(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        if not v:
            raise ValueError("name must not be blank")
        return v

    @field_validator("gender")
    @classmethod
    def _gender_valid(cls, v: str | None) -> str | None:
        if v is not None and v not in VALID_GENDERS:
            raise ValueError(f"gender must be one of {VALID_GENDERS}")
        return v

    @field_validator("interests")
    @classmethod
    def _interests_clean(cls, v: list[str] | None) -> list[str] | None:
        if v is None:
            return None
        cleaned = [s.strip() for s in v if s and s.strip()]
        for s in cleaned:
            if len(s) > _MAX_INTEREST:
                raise ValueError(f"each interest must be <= {_MAX_INTEREST} chars")
        return cleaned


class MemoryUpdate(BaseModel):
    summary: str = Field(max_length=4000)


# --- Endpoints -------------------------------------------------------------


@router.get("/devices/{device_id}/children")
def list_children(device_id: str, token: str | None = Query(default=None)) -> list[dict]:
    _require_token(token)
    _check_ids(device_id)
    return child_store.list_children(device_id)


@router.post(
    "/devices/{device_id}/children", status_code=status.HTTP_201_CREATED
)
def create_child(
    device_id: str, body: ChildCreate, token: str | None = Query(default=None)
) -> dict:
    _require_token(token)
    _check_ids(device_id)
    existing = child_store.list_children(device_id)
    if len(existing) >= child_store.MAX_CHILDREN_PER_DEVICE:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"max {child_store.MAX_CHILDREN_PER_DEVICE} children per device",
        )
    profile = body.model_dump()
    profile["created_at"] = _now_iso()
    return child_store.create_child(device_id, profile)


@router.patch("/devices/{device_id}/children/{child_id}")
def update_child(
    device_id: str,
    child_id: str,
    body: ChildUpdate,
    token: str | None = Query(default=None),
) -> dict:
    _require_token(token)
    _check_ids(device_id, child_id)
    fields = {k: v for k, v in body.model_dump().items() if v is not None}
    updated = child_store.update_child(device_id, child_id, fields)
    if updated is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="child not found")
    return updated


@router.delete(
    "/devices/{device_id}/children/{child_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def delete_child(
    device_id: str, child_id: str, token: str | None = Query(default=None)
) -> None:
    _require_token(token)
    _check_ids(device_id, child_id)
    # Idempotent: 204 whether or not it existed (delete is a no-op on absence).
    child_store.delete_child(device_id, child_id)


@router.patch("/devices/{device_id}/children/{child_id}/memory")
def set_memory(
    device_id: str,
    child_id: str,
    body: MemoryUpdate,
    token: str | None = Query(default=None),
) -> dict:
    _require_token(token)
    _check_ids(device_id, child_id)
    if child_store.get_child(device_id, child_id) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="child not found")
    child_store.save_memory(device_id, child_id, body.summary, updated_at=_now_iso())
    return child_store.get_child(device_id, child_id)


@router.delete("/devices/{device_id}/children/{child_id}/memory")
def clear_memory(
    device_id: str, child_id: str, token: str | None = Query(default=None)
) -> dict:
    _require_token(token)
    _check_ids(device_id, child_id)
    if not child_store.clear_memory(device_id, child_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="child not found")
    return child_store.get_child(device_id, child_id)

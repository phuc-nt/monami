---
title: "Red Team: Backend / Data / Security — Publish Prep Multi-Child Plan"
date: 2026-06-23
axis: backend, data model, security, contract migration
plan: 260623-1906-publish-prep-multi-child-per-device
severity_summary: 1 CRITICAL, 2 HIGH, 2 MEDIUM, 1 LOW
---

# Red Team Report: Backend / Data / Security

Adversarial review of the publish-prep plan on 5 attack axes.
Evidence = exact file:line refs. No manufactured concerns.

---

## FINDING 1 — CRITICAL: Guest session WILL write to Firestore via the DEFAULT_PROFILE_ID fallback

### Failure

`gemini_session.py:run_session` calls `get_profile(profile_id)` (line 145),
which for `profile_id="guest"` falls back to `PROFILES[DEFAULT_PROFILE_ID]`
(child_profile.py:65) because `"guest"` is not a key in `PROFILES`.
`DEFAULT_PROFILE_ID = "vy"` (child_profile.py:54).

So `profile.profile_id` becomes `"vy"`, not `"guest"`.

Then in the `finally` block (gemini_session.py:189):

```python
await _update_memory(client, profile.profile_id, memory_text, transcript)
```

`_update_memory` is called with `profile_id = "vy"` — not with a guest sentinel.
The transcript length check (`_MIN_TRANSCRIPT_LINES = 2`, line 194) is the ONLY
guard that prevents a write. If the guest says anything at all (≥ 2 lines),
`save_memory("vy", …)` fires and **overwrites Vy's real memory with junk from
a guest session**. On Cloud Run with `MEMORY_BACKEND=firestore` this writes to
`child_memory/vy` in Firestore.

The new plan says "phase 1 creates the guest/no-persist seam" but the plan's
proposed guard (`if not device_id or child_id == "guest": no-persist`, phase-01
risk section) compares `child_id`, yet the ACTUAL value flowing into
`_update_memory` is `profile.profile_id` — which is ALREADY normalized to `"vy"`.
The check `child_id == "guest"` will NEVER be true at the save site because
`get_profile` has already rewritten it.

### Proof

- `child_profile.py:54` — `DEFAULT_PROFILE_ID = "vy"`
- `child_profile.py:57–65` — `get_profile` returns `PROFILES[DEFAULT_PROFILE_ID]` for any unknown id
- `gemini_session.py:145` — `profile = get_profile(profile_id)` — profile_id="guest" → profile_id becomes "vy"
- `gemini_session.py:189` — `_update_memory(client, profile.profile_id, …)` — calls with "vy"
- `profile_store.py:57` — `save_memory("vy", …)` fires on Cloud Run Firestore

### Fix (mandatory for phase 1)

The guest guard MUST sit BEFORE `get_profile`, on the raw `profile_id` string,
not after resolution. The plan's proposed single-branch check must be at the
top of `run_session`, not inside `_update_memory`:

```python
async def run_session(ws, device_id: str | None, child_id: str | None) -> None:
    is_guest = not device_id or child_id == "guest"
    profile = get_profile_from_store(device_id, child_id) if not is_guest else guest_profile()
    memory_text = "" if is_guest else load_memory(device_id, child_id)
    …
    finally:
        if not is_guest:
            await _update_memory(client, device_id, child_id, memory_text, transcript)
```

`is_guest` must be computed ONCE from the raw params and carried through. Never
check it against `profile.profile_id` after resolution.

---

## FINDING 2 — HIGH: Hard cutover breaks the currently installed dev build

### Failure

The live backend on Cloud Run currently reads:
- `main.py:84` — `profile_id = websocket.query_params.get("profile")`
- `main.py:87` — `run_session(ws, profile_id)`
- `profile_store.py:133` — reads `child_memory/{doc_id}` flat collection

The existing app build connects with `?profile=vy` (no `device` param).

Phase 1 changes the WS handler to require `?device=<uuid>&profile=<childId>`.
When phase 1 deploys to Cloud Run:

**(a) Does the old build instantly break?** YES for memory, MAYBE for audio.
- If phase 1 removes `profile_id` fallback to old `get_profile` and mandates device-scoped
  `load_memory(device_id, child_id)`, a connect with `?profile=vy&token=…` that has
  no `device` param will either: hit the guest branch (no memory), OR crash if the
  code doesn't gracefully handle `device_id=None` in the store.
- Audio relay itself doesn't depend on memory — sessions still work unless the code 500s.

**(b) Is there a window?** YES — there's a window between Cloud Run deploy and app
update where the old build connects. On Cloud Run revisions are swapped atomically
(traffic cut-over is fast), but the old app stays on the user's phone indefinitely
until they install the new build.

**(c) Stranded Vy/Phong docs?** YES. The old flat `child_memory/vy` and `child_memory/phong`
docs in Firestore are never read by the new code (which reads `devices/{d}/children/{c}/memory`
merged field). Those docs become orphans — no cleanup plan, no migration. Profile
data is throwaway test data per the plan decision, but the plan doesn't say "old
memory is irrelevant too" — if the solo dev cares about Vy's accumulated memory,
it's silently abandoned.

### Is this a REAL production problem?

It's solo dev + throwaway test data. The risk of stranded docs is actually zero in
practice. BUT the risk of the old build getting a broken session (500 or no-memory
guest mode instead of named session) IS real if the dev tries to test the old build
against the new backend during the transition.

### Fix

Phase 1 must document a hard-cutover policy explicitly:

1. Accept old build is broken against new backend — stop using old build before deploying phase 1.
2. OR: Keep a compat shim in the WS handler for 1 deploy cycle:
   ```python
   device_id = websocket.query_params.get("device")
   child_id = websocket.query_params.get("profile")
   # compat: old ?profile=vy with no device → guest path (no memory)
   ```
   This is 3 lines and costs nothing. Recommended.
3. Explicitly note "old vy/phong memory is abandoned" so there's no ambiguity.

The plan currently says "don't migrate vy/phong" for profiles but is silent on
whether old flat memory docs matter. Make this explicit.

---

## FINDING 3 — HIGH: Device-ID trust model has a real gap for TestFlight cohort

### Failure

`deviceId` is a UUID self-declared by the app. The shared token in every distributed
build is the only gate (`main.py:61–70`, `secrets.compare_digest`). The new REST
endpoints give any valid-token caller:

```
GET    /devices/{deviceId}/children        → list all children for ANY deviceId
PATCH  /devices/{deviceId}/children/{c}   → edit ANY child's profile
DELETE /devices/{deviceId}/children/{c}   → delete ANY child + memory
PATCH  /devices/{deviceId}/children/{c}/memory → overwrite ANY memory
```

**Can tester A enumerate tester B's deviceId?**

The token is embedded in the TestFlight build — every tester has it. `deviceId` is
a UUIDv4 (128-bit random, per the plan). A UUIDv4 is NOT enumerable by brute force
(2^122 search space). HOWEVER:

1. **Log exposure**: phase-1 risk section says "keep deviceId out of logs." If Cloud Run
   logs ever emit `deviceId` (e.g. in a request path, structured log, or an unguarded
   `logger.info("WS connect: device=%s", device_id)`), then another tester with Cloud Run
   log access (or the dev reviewing logs) can see all deviceIds.
2. **Collusion**: 5 friends/family testers — the risk is negligible. If tester B tells
   tester A their deviceId, A can read/edit B's children. This is social, not a technical
   attack.
3. **The token does NOT protect against a tester calling the REST API directly** with
   their own UUID set to someone else's. But without log exposure, there's no way to
   discover another UUID.

### Realistic threat model for ~5-person cohort

Effective threat: ZERO from outsiders (token gates the endpoint). Near-zero from
insiders (UUIDs unguessable without log exposure). The gap is log hygiene, not auth
architecture.

### Fix (LOW effort, HIGH value)

1. Never log `device_id` in request paths or info-level logs. Structured log the path
   AFTER token check as `device=<redacted>` or omit it. One line in the WS handler
   and REST router.
2. In the REST router, confirm the path param `{deviceId}` is the one in the
   request (not hardcoded) — this is inherent but confirm tests cover cross-device
   isolation (phase-1 success criteria already mentions this: two devices, same child
   name → separate docs).
3. No per-device JWT needed for this cohort — explicitly state "deviceId is a
   capability bearer; keep it secret in client storage (Keychain) and out of logs"
   as a comment in `device_identity.dart`.

---

## FINDING 4 — MEDIUM: Firestore structure — race condition on PATCH profile + session end

### Failure

The plan merges profile + memory into a single child doc:
```
devices/{d}/children/{c} → { profile: {…}, memory: {summary, updatedAt} }
```

`_firestore_save` (profile_store.py:144) currently calls `.set(…)` which does a
FULL REPLACE of the document. The new `PATCH /…/children/{c}` endpoint will
presumably also update the profile fields. If:

1. User taps "edit child name" → REST PATCH fires → writes `{profile: {name: "Bé Mới", …}}`
2. Simultaneously, an ongoing voice session ends → `save_memory` fires → writes
   `{memory: {summary: "…"}}`

With `.set()` semantics, whichever write lands second OVERWRITES the other's fields
(Firestore `.set()` without `merge=True` replaces the entire document).

Result: profile edit succeeds → session memory write fires with the OLD profile
fields (or vice versa) → one of the two writes is silently lost.

### Proof

- `profile_store.py:144–152` — `_client().collection(…).document(…).set({…})` — full replace, no merge
- The race window: memory save fires in the session `finally` block
  (`gemini_session.py:189`) which runs after `WebSocketDisconnect`; REST PATCH
  could fire at any time including during teardown.

### Fix

Use `set(data, merge=True)` for BOTH the memory save and the profile PATCH, or use
`update({"memory.summary": …, "memory.updatedAt": …})` for the memory write so only
the `memory` sub-key is touched. Add this to phase-1 architecture notes. This is a
one-word fix (`merge=True`) but must be explicit in the plan.

---

## FINDING 5 — MEDIUM: Firestore security rules — SA is the only gate

### Failure

The brainstorm notes "backend uses an SA (server-side) so rules aren't the gate
today." This means Firestore security rules are likely in open/default state. If the
SA key or ADC token is ever leaked (e.g. in a CI log, a GitHub secret accidentally
exposed), the entire Firestore is open — not just the `devices/` subtree but
everything in the project.

This is a defense-in-depth gap, not an immediate exploitable bug, since the SA
private key lives in Secret Manager / Cloud Run env, not in the app binary.

The new `devices/{d}/children/{c}` structure is IDEAL for per-device rules:
```javascript
match /devices/{deviceId}/children/{childId} {
  allow read, write: if false; // SA only; no client SDK access
}
```
But the plan doesn't call this out.

### Fix (LOW effort)

Add a task in phase 1 or phase 6: "Set Firestore security rules to deny all client
SDK access — the backend SA is the only accessor." This is a single rules file
change and prevents leaked-SA blast radius from expanding via client SDK calls.
Not blocking for phase 1, but must ship before TestFlight.

---

## FINDING 6 — LOW: Underspecified acceptance criteria / footguns

The following are unspecified in phase 1/2/5 and will cause silently wrong behavior
or integration friction:

| Gap | Risk | Fix |
|-----|------|-----|
| `gender` enum not validated — backend accepts `"robot"`, `""`, `null` | Wrong gender → wrong robot face | Pydantic `Literal["male", "female"]` or `Literal["nam", "nữ"]` on the POST/PATCH model |
| `age` bounds not specified — `age=-1` or `age=100` are valid | Prompt injection via age field | `age: int = Field(ge=1, le=12)` |
| `interests` array size not capped — 100 interests → huge system prompt | Prompt bloat, token cost | `max_items=10` on the Pydantic field |
| `childId` format not specified — phase 1 says "server assigns UUID" but PATCH/DELETE accept ANY string in path | Path traversal via path param | Document that path params are sanitized; the existing `_doc_id` sanitizer in `profile_store.py:123` handles Firestore but the REST router must reject malformed ids with a 400 before they hit the store |
| PATCH semantics not specified — does it merge or replace profile fields? | Partial update erases unset fields | Explicitly document as "merge" (only provided fields updated); use Pydantic `Optional` fields |
| GET `/devices/{d}/children` for a nonexistent device — 200+empty or 404? | App shows empty picker vs. error state | Specify: 200+`[]` (device unknown = zero children, not an error). Document this. |
| DELETE idempotency — DELETE nonexistent child → 404 or 200? | App retries → confusion | Specify 404 (standard REST); app must handle gracefully |
| Vietnamese name encoding — `name="Nguyễn Thị Vy"` with diacritics through Firestore → Pydantic → JSON → system prompt | Unicode garbling in Gemini prompt | Verify `ensure_ascii=False` end-to-end; `json.dumps` in `profile_store.py:100` already has it, confirm Pydantic serialization does too |
| CORS — plan says "app calls from mobile (no CORS issue)" but if any web debugging tool hits the REST | Silent CORS block in browser devtools | Add `CORSMiddleware` with explicit origins or `*` for dev; document it |
| Request body size limit — FastAPI default is 1 MB; no explicit limit stated | Not a real concern for this payload size | Non-issue; skip |

---

## Must-Change Before Coding (Top 3)

**1. Fix the guest guard in `run_session` before phase 1 code is written.**
The plan's proposed check (`child_id == "guest"`) is wrong — it checks AFTER
`get_profile` has rewritten the id to "vy". The guard must use the raw `child_id`
param before profile resolution, and `is_guest=True` must prevent BOTH `load_memory`
and `_update_memory`. Write this explicitly in the phase-1 architecture section.

**2. Specify `merge=True` for Firestore memory writes in phase 1 architecture.**
The current `_firestore_save` does a full-replace `.set()`. With memory merged into
the child doc, every memory write must use `set(merge=True)` or `update()` on the
`memory.*` fields only. Without this, a concurrent PATCH profile + session-end memory
write will silently clobber one of them. Add this as an explicit implementation note.

**3. State the hard-cutover policy for the WS contract change.**
The plan is silent on what happens to the existing dev build during phase 1 deploy.
Add an explicit statement: "old build is incompatible with the new backend; stop
using old build before deploying phase 1" AND add the 3-line compat shim (old
`?profile=vy` with no `device` → treated as guest) to absorb the transition window.

---

## Fine As-Is (Do Not Manufacture Problems)

- **UUIDv4 deviceId as a capability** — for 5 testers, this is genuinely sufficient.
  No per-device JWT needed. The threat model is realistic, not hand-wavy.
- **Soft cap 5 children** — server-side enforcement on POST is correct. No race
  condition concern (Firestore's subcollection query + count is not transactional,
  but off-by-one on the cap is tolerable for a soft limit).
- **DELETE child deletes memory** — because memory is merged INTO the child doc,
  `delete_child` deletes both atomically. Zero orphan risk. Good design choice.
- **Firestore subcollection query for listing children** — no composite index needed
  for a simple `collection_group` or direct subcollection query under a known `deviceId`.
  `db.collection("devices").document(d).collection("children").stream()` is a
  direct path query — no index required.
- **Path sanitization** — `profile_store.py:123–129` already has a Firestore doc-id
  sanitizer; phase 1 must ensure both `device_id` and `child_id` pass through it.
  The existing pattern is sound.
- **Token constant-time compare** — `secrets.compare_digest` at `main.py:70` is
  correct. No timing attack risk.
- **Memory summarizer best-effort** — `memory_summarizer.py:79–80` catches all
  exceptions and returns prior summary. Teardown can't hang the session.

---

## Unresolved Questions

1. Does the solo dev care about preserving Vy's existing `child_memory/vy` Firestore
   memory across the cutover? If yes, a one-time manual copy is needed and should be
   called out. If no (throwaway), the plan should say so explicitly.
2. Will TestFlight testers share the same Cloud Run backend, or will there be a
   staging instance? If shared, deviceId log hygiene becomes more important sooner.
3. The plan mentions `childId` is "server-assigned UUID" — confirm: is `childId`
   generated in `child_rest_api.py` on POST (server-side) or passed by the client?
   Server-side is safer (prevents a client from injecting a chosen id); the plan
   implies server-side but doesn't specify it explicitly in the implementation steps.

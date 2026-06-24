---
phase: 1
title: Drop stories + rename label
status: completed
priority: P1
effort: 1-2h
dependencies: []
---

# Phase 1: Drop stories + rename label

## Overview
Remove the `stories` mode end-to-end (backend + app + JSON) and rename the science button
label "Vì sao?" → "Khoa học". Mechanical, low-risk; lands a clean 2-mode set (english +
science) before the script rewrite in P2.

## Requirements
- Functional: `stories` no longer a valid mode anywhere; science label reads "Khoa học".
- Non-functional (HARD backward-compat): an old app build sending `?mode=stories` must resolve
  to free-chat via `parse_mode` returning `None` — no crash, no error frame.

## Architecture
`stories` lives in 4 places: backend `learning_modes.py` (const + VALID_MODES + _SCRIPTS),
backend `curriculum.py` (`_render_story` + the STORIES branch in `render_lesson`), the JSON file
`curriculum/stories.json`, and app `learning_mode.dart` (enum value + 3 switch arms). The mode
key `science` is NOT touched — only its app-side display `label` changes.

## Related Code Files
- Modify: `backend/learning_modes.py` — delete `STORIES` const; drop from `VALID_MODES`; remove
  the `STORIES` entry in `_SCRIPTS`.
- Modify: `backend/curriculum.py` — delete `_render_story`; remove the `learning_modes.STORIES`
  branch in `render_lesson`.
- Delete: `backend/curriculum/stories.json`.
- Modify: `app/lib/learning_mode.dart` — remove `LearningMode.stories` from the enum and from
  the `wsValue`/`label`/`icon` switches; change `science` label `'Vì sao?'` → `'Khoa học'`.
- Modify (tests): `backend/tests/*` and `app/test/*` — drop story-specific cases; ADD/keep a test
  that `parse_mode("stories") is None` (backward-compat); keep the free-chat byte-identical test.

## Implementation Steps
1. Backend `learning_modes.py`: remove `STORIES`, its `VALID_MODES` membership, its `_SCRIPTS`
   entry. `parse_mode("stories")` now returns `None` automatically (not in the frozenset).
2. Backend `curriculum.py`: delete `_render_story`; in `render_lesson` remove the STORIES branch
   so only english/science remain (the `else` no-op stays as a safety net).
3. `rm backend/curriculum/stories.json`.
4. App `learning_mode.dart`: delete the `stories` enum value + its 3 switch arms; switch
   statements become exhaustive over `{chat, english, science}`. Change science label to "Khoa học".
5. Update tests: remove story assertions; add explicit `parse_mode("stories") is None` test;
   run both suites.

## Success Criteria
- [ ] `grep -ri "stories\|STORIES" backend/ app/lib/` returns no live references (comments noting
      the removal are fine).
- [ ] `parse_mode("stories") is None` — covered by a test.
- [ ] App `flutter analyze` clean; switch statements exhaustive without `stories`.
- [ ] Science button label renders "Khoa học"; `wsValue` for science is still `'science'`.
- [ ] backend `pytest tests/ -q` green; app `flutter test` green.

## Risk Assessment
- **Risk:** a non-exhaustive Dart switch after removing the enum value → compile error.
  *Mitigation:* `flutter analyze` + `flutter test` catch it immediately.
- **Risk:** an old TestFlight build still sends `?mode=stories`. *Mitigation:* `parse_mode`
  already treats unknown values as free-chat; the added test locks this in.
- Rollback: revert the commit; nothing persisted changes (no schema/migration).

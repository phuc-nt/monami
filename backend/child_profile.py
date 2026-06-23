"""Child profile: the fixed facts the companion should feel in its replies.

A profile is who the child is (name/age/gender/interests) — the hand-set part.
The changing part (what the companion remembers across sessions) lives in the
child doc's memory field and is loaded by `child_store`.

Profiles are no longer a hardcoded registry: they come from the per-device store
(`child_store`). This module keeps the `ChildProfile` shape, the prompt rendering,
and a neutral GUEST profile used by quick/guest mode (no name, no persistence).
Keep profile text short and concrete: long text makes the system prompt brittle.
"""

from __future__ import annotations

from dataclasses import dataclass, field

# Gender drives the app's face variant; the backend only uses it for a light
# pronoun/tone hint. "neutral" is the guest / unspecified case.
VALID_GENDERS = ("boy", "girl")


@dataclass(frozen=True)
class ChildProfile:
    """Minimal fixed facts the companion should feel in its replies."""

    profile_id: str
    name: str
    age: int
    interests: list[str] = field(default_factory=list)
    gender: str = "neutral"  # "boy" | "girl" | "neutral"

    def to_prompt_text(self) -> str:
        """Render the profile as a short bilingual block for the system prompt."""
        interests = ", ".join(self.interests) if self.interests else "(chưa rõ)"
        gender_line = ""
        if self.gender == "girl":
            gender_line = "- Bé là bạn gái / The child is a girl.\n"
        elif self.gender == "boy":
            gender_line = "- Bé là bạn trai / The child is a boy.\n"
        return (
            "Thông tin về bé / About the child:\n"
            f"- Tên / Name: {self.name}\n"
            f"- Tuổi / Age: {self.age}\n"
            f"{gender_line}"
            f"- Bé thích / Likes: {interests}\n"
            "Hãy gọi tên bé một cách tự nhiên và thỉnh thoảng nhắc tới điều bé thích. "
            "Greet the child by name naturally and occasionally reference what they like."
        )


# Neutral companion used by quick/guest mode: no name, no stored memory. Kept
# warm + age-appropriate so a guest session feels the same minus personalization.
GUEST_PROFILE = ChildProfile(
    profile_id="guest",
    name="bạn nhỏ",  # "little friend" — a gentle generic address
    age=5,
    interests=[],
    gender="neutral",
)


def profile_from_record(record: dict) -> ChildProfile:
    """Build a ChildProfile from a stored child dict (see child_store)."""
    gender = record.get("gender")
    if gender not in VALID_GENDERS:
        gender = "neutral"
    return ChildProfile(
        profile_id=str(record.get("id", "")),
        name=str(record.get("name", "bạn nhỏ")),
        age=int(record.get("age", 5)),
        interests=list(record.get("interests", [])),
        gender=gender,
    )

"""Child profiles: a small registry of the children the companion talks to.

Two children for now (Vy + Phong), each a `ChildProfile`. The profile is the
fixed, hand-set part of who the child is (name/age/interests); the changing part
— what the companion remembers from past sessions — is stored separately and
loaded by `profile_store`. Keep profile text short and concrete: long text makes
the system prompt brittle.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class ChildProfile:
    """Minimal fixed facts the companion should feel in its replies."""

    profile_id: str
    name: str
    age: int
    interests: list[str] = field(default_factory=list)

    def to_prompt_text(self) -> str:
        """Render the profile as a short bilingual block for the system prompt."""
        interests = ", ".join(self.interests) if self.interests else "(chưa rõ)"
        return (
            "Thông tin về bé / About the child:\n"
            f"- Tên / Name: {self.name}\n"
            f"- Tuổi / Age: {self.age}\n"
            f"- Bé thích / Likes: {interests}\n"
            "Hãy gọi tên bé một cách tự nhiên và thỉnh thoảng nhắc tới điều bé thích. "
            "Greet the child by name naturally and occasionally reference what they like."
        )


# The children. Keys are the stable profile ids used by the client + storage.
PROFILES: dict[str, ChildProfile] = {
    "vy": ChildProfile(
        profile_id="vy",
        name="Vy",
        age=5,
        interests=["Elsa", "công chúa / princesses", "kể chuyện / stories"],
    ),
    "phong": ChildProfile(
        profile_id="phong",
        name="Phong",
        age=5,
        interests=["khủng long / dinosaurs", "xe ô tô / cars", "khám phá / exploring"],
    ),
}

# Used when no/unknown profile id is supplied (with a logged warning at the call site).
DEFAULT_PROFILE_ID = "vy"


def get_profile(profile_id: str | None) -> ChildProfile:
    """Resolve a profile id to a ChildProfile, falling back to the default.

    Returns the default profile for None or an unknown id; callers should log a
    warning when they pass something that didn't resolve.
    """
    if profile_id and profile_id in PROFILES:
        return PROFILES[profile_id]
    return PROFILES[DEFAULT_PROFILE_ID]

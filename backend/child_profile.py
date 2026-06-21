"""One hard-coded child profile for Phase 1.

Phase 1 ships a single profile injected into the system prompt at session start
(memory = system-prompt context-stuffing, per the Phase 0 decision). Later phases
replace this with per-child profiles + persisted memory; keep the shape small and
plain so swapping the source out is trivial.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class ChildProfile:
    """Minimal facts the companion should feel in its replies.

    Keep this short and concrete — long profile text makes the system prompt
    brittle. Name + a couple of interests is enough for the companion to greet
    the child and reference something they like.
    """

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


# The single Phase 1 profile. Edit here to change who the companion talks to.
DEFAULT_PROFILE = ChildProfile(
    name="Vy",
    age=5,
    interests=["Elsa", "công chúa / princesses", "kể chuyện / stories"],
)

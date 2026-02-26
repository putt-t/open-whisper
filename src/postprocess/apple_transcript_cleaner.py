from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from typing import Any

logger = logging.getLogger(__name__)


@dataclass(slots=True)
class _CleanerState:
    checked: bool = False
    available: bool = False
    unavailable_reason: str | None = None
    fm: Any | None = None
    model: Any | None = None


class AppleTranscriptCleaner:
    """Optional transcript cleanup using Apple's Foundation Models SDK."""

    def __init__(self, instructions: str, user_dictionary_terms: list[str] | None = None) -> None:
        self.instructions = instructions
        self.user_dictionary_terms = user_dictionary_terms or []
        self._state = _CleanerState()
        self._availability_lock = asyncio.Lock()

    async def clean(self, transcript: str) -> str:
        text = transcript.strip()
        if not text:
            return text

        if not await self._ensure_model():
            return text

        session = self._state.fm.LanguageModelSession(
            instructions=self.instructions,
            model=self._state.model,
        )

        prompt = (
            "Clean this raw speech transcript.\n"
            "Remove disfluencies and resolve self-corrections to the final intended meaning.\n"
            "If no cleanup is needed, return the same text.\n"
            f"{self._dictionary_prompt_section()}"
            "Return only plain cleaned transcript text.\n"
            "No labels, no explanations, no markdown.\n\n"
            "Transcript:\n"
            f"\"\"\"\n{text}\n\"\"\""
        )

        try:
            result = await session.respond(prompt)
        except Exception as exc:
            logger.warning("Apple cleanup respond failed: %s", exc)
            return text

        cleaned = str(result).strip()
        return cleaned or text

    def _dictionary_prompt_section(self) -> str:
        if not self.user_dictionary_terms:
            return ""

        terms = "\n".join(f"- {term}" for term in self.user_dictionary_terms)
        return (
            "User dictionary terms (preferred canonical spellings):\n"
            f"{terms}\n"
            "If context suggests one of these was mis-transcribed, correct it to the canonical spelling.\n"
        )

    async def _ensure_model(self) -> bool:
        if self._state.checked:
            return self._state.available

        async with self._availability_lock:
            if self._state.checked:
                return self._state.available

            try:
                import apple_fm_sdk as fm
            except ImportError:
                self._mark_unavailable("apple_fm_sdk is not installed")
                return False
            self._state.fm = fm

            try:
                if hasattr(fm, "SystemLanguageModelGuardrails"):
                    model = fm.SystemLanguageModel(
                        guardrails=fm.SystemLanguageModelGuardrails.PERMISSIVE_CONTENT_TRANSFORMATIONS
                    )
                else:
                    model = fm.SystemLanguageModel()
                available, reason = model.is_available()
            except Exception as exc:
                self._mark_unavailable(f"availability check failed: {exc}")
                return False

            if not available:
                self._mark_unavailable(reason or "system model unavailable")
                return False

            self._state.checked = True
            self._state.available = True
            self._state.model = model
            logger.info("Apple transcript cleanup enabled (stateless session per request)")
            return True

    def _mark_unavailable(self, reason: str) -> None:
        self._state.checked = True
        self._state.available = False
        self._state.unavailable_reason = reason
        logger.warning("Apple transcript cleanup disabled: %s", reason)

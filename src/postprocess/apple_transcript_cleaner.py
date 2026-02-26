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

    def __init__(self, instructions: str) -> None:
        self.instructions = instructions
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
            "You are a transcript cleanup engine.\n"
            "Apply these rules in order:\n"
            "1) Remove filler words, stutters, and false starts.\n"
            "2) If the speaker revises/retracts earlier content, keep only the final surviving intent.\n"
            "3) If two statements conflict, the latest statement wins.\n"
            "4) Never include discarded alternatives together with the final choice.\n"
            "5) Keep decisive correction cues (e.g. 'actually', 'wait', 'no', 'instead') as signals and resolve to the final choice.\n"
            "6) If no cleanup is needed, return the input unchanged.\n"
            "7) Keep original language and tone, and do not add information.\n"
            "8) Return only the final cleaned text.\n"
            "Example:\n"
            "Raw: We shipped it. Actually, no, not shipped yet.\n"
            "Cleaned: It's not shipped yet.\n"
            "Example:\n"
            "Raw: Use Rust. Wait, use Python.\n"
            "Cleaned: Use Python.\n"
            f"Raw transcript:\n{text}"
        )

        try:
            result = await session.respond(prompt)
        except Exception as exc:
            logger.warning("Apple cleanup respond failed: %s", exc)
            return text

        cleaned = str(result).strip()
        return cleaned or text

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

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
    session: Any | None = None


class AppleTranscriptCleaner:
    """Optional transcript cleanup using Apple's Foundation Models SDK."""

    def __init__(self, instructions: str) -> None:
        self.instructions = instructions
        self._state = _CleanerState()
        self._availability_lock = asyncio.Lock()
        self._respond_lock = asyncio.Lock()

    async def clean(self, transcript: str) -> str:
        text = transcript.strip()
        if not text:
            return text

        if not await self._ensure_session():
            return text

        prompt = (
            "Clean the following raw transcription.\n"
            "Keep only the final intended message.\n"
            "Output only the cleaned text.\n\n"
            f"Raw transcript:\n{text}"
        )

        async with self._respond_lock:
            result = await self._state.session.respond(prompt)

        cleaned = str(result).strip()
        return cleaned or text

    async def _ensure_session(self) -> bool:
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

            try:
                model = fm.SystemLanguageModel()
                available, reason = model.is_available()
            except Exception as exc:
                self._mark_unavailable(f"availability check failed: {exc}")
                return False

            if not available:
                self._mark_unavailable(reason or "system model unavailable")
                return False

            try:
                self._state.session = fm.LanguageModelSession(
                    instructions=self.instructions,
                    model=model,
                )
            except Exception as exc:
                self._mark_unavailable(f"session creation failed: {exc}")
                return False

            self._state.checked = True
            self._state.available = True
            logger.info("Apple transcript cleanup enabled")
            return True

    def _mark_unavailable(self, reason: str) -> None:
        self._state.checked = True
        self._state.available = False
        self._state.unavailable_reason = reason
        logger.warning("Apple transcript cleanup disabled: %s", reason)

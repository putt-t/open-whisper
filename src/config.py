from __future__ import annotations

import re
import tempfile
from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

DEFAULT_ASR_LOCAL_MODEL = Path("models/Qwen3-ASR-1.7B-6bit")
DEFAULT_ASR_REPO = "mlx-community/Qwen3-ASR-1.7B-6bit"
DEFAULT_ASR_TOKEN_FILE = Path.home() / ".dictation" / "asr-token"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(".env", ".env.local"),
        extra="ignore",
    )

    dictation_model: str | None = Field(default=None, alias="DICTATION_MODEL")
    dictation_model_dir: Path = Field(default=DEFAULT_ASR_LOCAL_MODEL, alias="DICTATION_MODEL_DIR")
    dictation_asr_provider: Literal["qwen", "whisperkit"] = Field(
        default="qwen",
        alias="DICTATION_ASR_PROVIDER",
    )
    dictation_tmp_dir: Path = Field(
        default=Path(tempfile.gettempdir()) / "dictation-asr",
        alias="DICTATION_TMP_DIR",
    )
    dictation_whisperkit_endpoint: str = Field(
        default="http://127.0.0.1:50060/v1/audio/transcriptions",
        alias="DICTATION_WHISPERKIT_ENDPOINT",
    )
    dictation_whisperkit_model: str = Field(
        default="large-v3",
        alias="DICTATION_WHISPERKIT_MODEL",
    )
    dictation_whisperkit_timeout_seconds: float = Field(
        default=30.0,
        alias="DICTATION_WHISPERKIT_TIMEOUT_SECONDS",
    )
    dictation_whisperkit_language: str | None = Field(
        default=None,
        alias="DICTATION_WHISPERKIT_LANGUAGE",
    )
    dictation_whisperkit_prompt: str | None = Field(
        default=None,
        alias="DICTATION_WHISPERKIT_PROMPT",
    )
    dictation_log_transcripts: bool = Field(default=True, alias="DICTATION_LOG_TRANSCRIPTS")
    dictation_asr_token_file: Path = Field(
        default=DEFAULT_ASR_TOKEN_FILE,
        alias="DICTATION_ASR_TOKEN_FILE",
    )
    dictation_cleanup_enabled: bool = Field(
        default=False,
        alias="DICTATION_CLEANUP_ENABLED",
    )
    dictation_cleanup_instructions: str = Field(
        default=(
            "You clean raw speech-to-text transcripts into final user-ready text. "
            "Preserve meaning, intent, entities, and factual content. "
            "Remove filler words, false starts, repeated fragments, and disfluencies. "
            "If the speaker revises or retracts earlier content, keep only the latest surviving intent. "
            "When there are corrections, compress to a concise final statement of the surviving intent. "
            "Never include discarded alternatives together with the final chosen option. "
            "If there is no disfluency or correction, keep text unchanged. "
            "Keep the original language and tone. "
            "Return plain text only, with no labels like 'Cleaned:'. "
            "Do not add new information. "
            "Return only the cleaned final text."
        ),
        alias="DICTATION_CLEANUP_INSTRUCTIONS",
    )
    dictation_cleanup_user_dictionary: str = Field(
        default="",
        alias="DICTATION_CLEANUP_USER_DICTIONARY",
    )

    @property
    def resolved_model_id(self) -> str:
        if self.dictation_model:
            return self.dictation_model
        if self.dictation_model_dir.exists():
            return str(self.dictation_model_dir)
        return str(DEFAULT_ASR_LOCAL_MODEL if DEFAULT_ASR_LOCAL_MODEL.exists() else DEFAULT_ASR_REPO)

    @property
    def cleanup_user_dictionary_terms(self) -> list[str]:
        raw = self.dictation_cleanup_user_dictionary.strip()
        if not raw:
            return []
        parts = re.split(r"[,;\n]", raw)
        return [term.strip() for term in parts if term.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()

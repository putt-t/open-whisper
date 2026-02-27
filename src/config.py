from __future__ import annotations

import json
import os
import re
import tempfile
from functools import cached_property, lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

DEFAULT_ASR_LOCAL_MODEL = Path("models/Qwen3-ASR-1.7B-6bit")
DEFAULT_ASR_REPO = "mlx-community/Qwen3-ASR-1.7B-6bit"
DEFAULT_ASR_TOKEN_FILE = Path.home() / ".dictation" / "asr-token"
DEFAULT_APP_SETTINGS_FILE = (
    Path.home() / "Library" / "Application Support" / "OpenWhisper" / "settings.json"
)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(".env", ".env.local"),
        extra="ignore",
    )

    dictation_model: str | None = Field(default=None, alias="DICTATION_MODEL")
    dictation_model_dir: Path = Field(default=DEFAULT_ASR_LOCAL_MODEL, alias="DICTATION_MODEL_DIR")
    dictation_settings_file: Path = Field(
        default=DEFAULT_APP_SETTINGS_FILE,
        alias="DICTATION_SETTINGS_FILE",
    )
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

    @field_validator(
        "dictation_model_dir",
        "dictation_settings_file",
        "dictation_tmp_dir",
        "dictation_asr_token_file",
        mode="before",
    )
    @classmethod
    def _expand_user_path(cls, value: Path | str) -> Path | str:
        if isinstance(value, Path):
            return value.expanduser()
        if isinstance(value, str):
            return Path(value).expanduser()
        return value

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

    @cached_property
    def app_settings(self) -> dict:
        try:
            data = self.dictation_settings_file.read_text(encoding="utf-8")
        except FileNotFoundError:
            return {}
        except OSError:
            return {}

        try:
            parsed = json.loads(data)
        except json.JSONDecodeError:
            return {}
        return parsed if isinstance(parsed, dict) else {}

    def _env_overrides(self, field_name: str) -> bool:
        field = type(self).model_fields.get(field_name)
        if field is None:
            return False

        alias = field.alias
        if alias and alias in os.environ:
            return True
        return field_name in os.environ

    @property
    def effective_asr_provider(self) -> Literal["qwen", "whisperkit"]:
        if self._env_overrides("dictation_asr_provider"):
            return self.dictation_asr_provider

        value = self.app_settings.get("asrProvider")
        if value in {"qwen", "whisperkit"}:
            return value
        return self.dictation_asr_provider

    @property
    def effective_whisperkit_model(self) -> str:
        if self._env_overrides("dictation_whisperkit_model"):
            return self.dictation_whisperkit_model

        value = self.app_settings.get("whisperkitModel")
        if isinstance(value, str) and value.strip():
            return value.strip()
        return self.dictation_whisperkit_model

    @property
    def effective_whisperkit_language(self) -> str | None:
        if self._env_overrides("dictation_whisperkit_language"):
            return self.dictation_whisperkit_language

        value = self.app_settings.get("whisperkitLanguage")
        if isinstance(value, str):
            cleaned = value.strip()
            return cleaned or None
        return self.dictation_whisperkit_language

    @property
    def effective_cleanup_enabled(self) -> bool:
        if self._env_overrides("dictation_cleanup_enabled"):
            return self.dictation_cleanup_enabled

        value = self.app_settings.get("cleanupEnabled")
        if isinstance(value, bool):
            return value
        return self.dictation_cleanup_enabled

    @property
    def effective_cleanup_user_dictionary(self) -> str:
        if self._env_overrides("dictation_cleanup_user_dictionary"):
            return self.dictation_cleanup_user_dictionary

        value = self.app_settings.get("cleanupUserDictionary")
        if isinstance(value, str):
            return value
        return self.dictation_cleanup_user_dictionary

    @property
    def effective_cleanup_user_dictionary_terms(self) -> list[str]:
        raw = self.effective_cleanup_user_dictionary.strip()
        if not raw:
            return []
        parts = re.split(r"[,;\n]", raw)
        return [term.strip() for term in parts if term.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()

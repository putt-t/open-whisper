from __future__ import annotations

import tempfile
from functools import lru_cache
from pathlib import Path

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
    dictation_tmp_dir: Path = Field(
        default=Path(tempfile.gettempdir()) / "dictation-asr",
        alias="DICTATION_TMP_DIR",
    )
    dictation_log_transcripts: bool = Field(default=True, alias="DICTATION_LOG_TRANSCRIPTS")
    dictation_asr_token_file: Path = Field(
        default=DEFAULT_ASR_TOKEN_FILE,
        alias="DICTATION_ASR_TOKEN_FILE",
    )

    @property
    def resolved_model_id(self) -> str:
        if self.dictation_model:
            return self.dictation_model
        if self.dictation_model_dir.exists():
            return str(self.dictation_model_dir)
        return str(DEFAULT_ASR_LOCAL_MODEL if DEFAULT_ASR_LOCAL_MODEL.exists() else DEFAULT_ASR_REPO)


@lru_cache
def get_settings() -> Settings:
    return Settings()

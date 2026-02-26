from __future__ import annotations

import asyncio
import hmac
import logging
import os
import secrets
import shutil
import tempfile
import time
import uuid
from pathlib import Path

from fastapi import UploadFile
from fastapi.concurrency import run_in_threadpool
from mlx_audio.stt.generate import generate_transcription
from mlx_audio.stt.utils import load_model
from src.postprocess.apple_transcript_cleaner import AppleTranscriptCleaner

logger = logging.getLogger(__name__)


class ASRService:
    _LOG_TEXT_PREVIEW_MAX = 220

    def __init__(
        self,
        model_id: str,
        temp_dir: Path,
        auth_token_file: Path,
        log_transcripts: bool = True,
        transcript_cleaner: AppleTranscriptCleaner | None = None,
    ) -> None:
        self.model_id = model_id
        self.temp_dir = temp_dir
        self.auth_token_file = auth_token_file
        self.log_transcripts = log_transcripts
        self.transcript_cleaner = transcript_cleaner
        self._model = None
        self._auth_token: str | None = None
        self._transcription_lock = asyncio.Lock()

    @property
    def is_ready(self) -> bool:
        return self._model is not None

    async def startup(self) -> None:
        self.temp_dir.mkdir(parents=True, exist_ok=True)
        self._auth_token = self._load_or_create_auth_token()
        logger.info("ASR auth token file: %s", self.auth_token_file)
        self._model = await run_in_threadpool(load_model, self.model_id)
        logger.info("ASR model loaded: %s", self.model_id)

    async def shutdown(self) -> None:
        self._model = None
        self._auth_token = None

    def authorize(self, token: str | None) -> bool:
        if not token or not self._auth_token:
            return False
        return hmac.compare_digest(token, self._auth_token)

    async def transcribe(self, audio: UploadFile) -> str:
        if self._model is None:
            raise RuntimeError("model not loaded")

        request_started = time.perf_counter()
        suffix = Path(audio.filename or "audio.wav").suffix or ".wav"
        tmp_audio_path = await run_in_threadpool(self._save_upload_to_temp_sync, audio.file, suffix)
        out_base = self.temp_dir / f"transcript-{uuid.uuid4()}"

        try:
            transcription_started = time.perf_counter()
            async with self._transcription_lock:
                result = await run_in_threadpool(self._transcribe_sync, tmp_audio_path, out_base)
            transcription_ms = (time.perf_counter() - transcription_started) * 1000.0

            raw_text = (getattr(result, "text", "") or "").strip()
            cleanup_started = time.perf_counter()
            text = await self._postprocess_transcript(raw_text)
            cleanup_ms = (time.perf_counter() - cleanup_started) * 1000.0
            total_ms = (time.perf_counter() - request_started) * 1000.0

            if self.log_transcripts:
                logger.info(
                    (
                        "transcribe_result\n"
                        "  transcription_ms: %.1f\n"
                        "  cleanup_ms: %.1f\n"
                        "  total_ms: %.1f\n"
                        "  raw: %s\n"
                        "  final: %s"
                    ),
                    transcription_ms,
                    cleanup_ms,
                    total_ms,
                    self._preview_for_log(raw_text),
                    self._preview_for_log(text),
                )
            return text
        finally:
            self._cleanup_temp_files(tmp_audio_path, out_base)

    def _preview_for_log(self, text: str) -> str:
        normalized = " ".join(text.split())
        if len(normalized) <= self._LOG_TEXT_PREVIEW_MAX:
            return normalized
        return f"{normalized[: self._LOG_TEXT_PREVIEW_MAX - 1]}…"

    async def _postprocess_transcript(self, text: str) -> str:
        if not self.transcript_cleaner or not text:
            return text
        try:
            return await self.transcript_cleaner.clean(text)
        except Exception:
            logger.exception("Transcript cleanup failed, returning raw transcript")
            return text

    def _transcribe_sync(self, tmp_audio_path: Path, out_base: Path):
        return generate_transcription(
            model=self._model,
            audio=str(tmp_audio_path),
            output_path=str(out_base),
            format="txt",
            verbose=False,
        )

    @staticmethod
    def _save_upload_to_temp_sync(file_obj, suffix: str) -> Path:
        file_obj.seek(0)
        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
            shutil.copyfileobj(file_obj, tmp)
            return Path(tmp.name)

    @staticmethod
    def _cleanup_temp_files(tmp_audio_path: Path, out_base: Path) -> None:
        cleanup_paths = [
            tmp_audio_path,
            out_base.with_suffix(".txt"),
            out_base.with_suffix(".json"),
            out_base.with_suffix(".srt"),
            out_base.with_suffix(".vtt"),
        ]
        for path in cleanup_paths:
            try:
                path.unlink(missing_ok=True)
            except Exception:
                logger.debug("Could not remove temp file: %s", path)

    def _load_or_create_auth_token(self) -> str:
        token_dir = self.auth_token_file.parent
        token_dir.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(token_dir, 0o700)
        except OSError:
            logger.debug("Could not set directory permissions: %s", token_dir)

        token = ""
        if self.auth_token_file.exists():
            token = self.auth_token_file.read_text(encoding="utf-8").strip()

        if not token:
            token = secrets.token_urlsafe(32)
            fd = os.open(self.auth_token_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as token_file:
                token_file.write(token)
                token_file.write("\n")

        try:
            os.chmod(self.auth_token_file, 0o600)
        except OSError:
            logger.debug("Could not set file permissions: %s", self.auth_token_file)

        return token

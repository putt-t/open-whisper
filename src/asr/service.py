from __future__ import annotations

import asyncio
import logging
import shutil
import tempfile
import uuid
from pathlib import Path

from fastapi import UploadFile
from fastapi.concurrency import run_in_threadpool
from mlx_audio.stt.generate import generate_transcription
from mlx_audio.stt.utils import load_model

logger = logging.getLogger(__name__)


class ASRService:
    def __init__(self, model_id: str, temp_dir: Path, log_transcripts: bool = True) -> None:
        self.model_id = model_id
        self.temp_dir = temp_dir
        self.log_transcripts = log_transcripts
        self._model = None
        self._transcription_lock = asyncio.Lock()

    @property
    def is_ready(self) -> bool:
        return self._model is not None

    async def startup(self) -> None:
        self.temp_dir.mkdir(parents=True, exist_ok=True)
        self._model = await run_in_threadpool(load_model, self.model_id)
        logger.info("ASR model loaded: %s", self.model_id)

    async def shutdown(self) -> None:
        self._model = None

    async def transcribe(self, audio: UploadFile) -> str:
        if self._model is None:
            raise RuntimeError("model not loaded")

        suffix = Path(audio.filename or "audio.wav").suffix or ".wav"
        tmp_audio_path = await run_in_threadpool(self._save_upload_to_temp_sync, audio.file, suffix)
        out_base = self.temp_dir / f"transcript-{uuid.uuid4()}"

        try:
            async with self._transcription_lock:
                result = await run_in_threadpool(self._transcribe_sync, tmp_audio_path, out_base)
            text = (getattr(result, "text", "") or "").strip()
            if self.log_transcripts:
                logger.info("transcript: %s", text)
            return text
        finally:
            self._cleanup_temp_files(tmp_audio_path, out_base)

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

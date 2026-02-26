from __future__ import annotations

import asyncio
import json
import logging
import uuid
from pathlib import Path
from typing import Protocol
from urllib import error as url_error
from urllib import request as url_request

from fastapi.concurrency import run_in_threadpool
from mlx_audio.stt.generate import generate_transcription
from mlx_audio.stt.utils import load_model

logger = logging.getLogger(__name__)


class Transcriber(Protocol):
    provider_name: str
    model_id: str

    @property
    def is_ready(self) -> bool: ...

    async def startup(self) -> None: ...

    async def shutdown(self) -> None: ...

    async def transcribe(self, audio_path: Path, audio_filename: str | None = None) -> str: ...


class QwenTranscriber:
    provider_name = "qwen"

    def __init__(self, model_id: str, temp_dir: Path) -> None:
        self.model_id = model_id
        self.temp_dir = temp_dir
        self._model = None
        self._transcription_lock = asyncio.Lock()

    @property
    def is_ready(self) -> bool:
        return self._model is not None

    async def startup(self) -> None:
        self.temp_dir.mkdir(parents=True, exist_ok=True)
        self._model = await run_in_threadpool(load_model, self.model_id)
        logger.info("Qwen ASR model loaded: %s", self.model_id)

    async def shutdown(self) -> None:
        self._model = None

    async def transcribe(self, audio_path: Path, audio_filename: str | None = None) -> str:
        if self._model is None:
            raise RuntimeError("Qwen ASR model not loaded")

        out_base = self.temp_dir / f"transcript-{uuid.uuid4()}"
        try:
            async with self._transcription_lock:
                result = await run_in_threadpool(self._transcribe_sync, audio_path, out_base)
            return (getattr(result, "text", "") or "").strip()
        finally:
            self._cleanup_temp_files(out_base)

    def _transcribe_sync(self, audio_path: Path, out_base: Path):
        return generate_transcription(
            model=self._model,
            audio=str(audio_path),
            output_path=str(out_base),
            format="txt",
            verbose=False,
        )

    @staticmethod
    def _cleanup_temp_files(out_base: Path) -> None:
        cleanup_paths = [
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


class WhisperKitTranscriber:
    provider_name = "whisperkit"

    def __init__(
        self,
        endpoint: str,
        model_id: str,
        timeout_seconds: float = 30.0,
        language: str | None = None,
        prompt: str | None = None,
    ) -> None:
        self.endpoint = endpoint
        self.model_id = model_id
        self.timeout_seconds = timeout_seconds
        self.language = language
        self.prompt = prompt
        self._ready = False

    @property
    def is_ready(self) -> bool:
        return self._ready

    async def startup(self) -> None:
        self._ready = True
        logger.info(
            "WhisperKit transcriber configured: endpoint=%s model=%s",
            self.endpoint,
            self.model_id,
        )

    async def shutdown(self) -> None:
        self._ready = False

    async def transcribe(self, audio_path: Path, audio_filename: str | None = None) -> str:
        if not self._ready:
            raise RuntimeError("WhisperKit transcriber not initialized")
        return await run_in_threadpool(self._transcribe_sync, audio_path, audio_filename)

    def _transcribe_sync(self, audio_path: Path, audio_filename: str | None = None) -> str:
        filename = audio_filename or audio_path.name
        content_type = _guess_audio_content_type(audio_path)
        fields: list[tuple[str, str]] = [
            ("model", self.model_id),
            ("response_format", "json"),
        ]
        if self.language:
            fields.append(("language", self.language))
        if self.prompt:
            fields.append(("prompt", self.prompt))

        body, multipart_content_type = _build_multipart_body(
            fields=fields,
            file_field_name="file",
            file_name=filename,
            file_content_type=content_type,
            file_bytes=audio_path.read_bytes(),
        )

        req = url_request.Request(
            self.endpoint,
            data=body,
            method="POST",
            headers={
                "Content-Type": multipart_content_type,
                "Accept": "application/json",
            },
        )

        try:
            with url_request.urlopen(req, timeout=self.timeout_seconds) as response:
                response_text = response.read().decode("utf-8", errors="replace")
        except url_error.HTTPError as exc:
            error_body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(
                f"WhisperKit request failed ({exc.code}): {error_body[:400]}"
            ) from exc
        except url_error.URLError as exc:
            raise RuntimeError(f"WhisperKit request failed: {exc.reason}") from exc

        try:
            payload = json.loads(response_text)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"WhisperKit returned non-JSON response: {response_text[:400]}"
            ) from exc

        text = payload.get("text")
        if isinstance(text, str):
            return text.strip()
        raise RuntimeError(f"WhisperKit response missing 'text': {payload}")


def _build_multipart_body(
    *,
    fields: list[tuple[str, str]],
    file_field_name: str,
    file_name: str,
    file_content_type: str,
    file_bytes: bytes,
) -> tuple[bytes, str]:
    boundary = f"----open-whisper-{uuid.uuid4().hex}"
    body = bytearray()

    for name, value in fields:
        body.extend(f"--{boundary}\r\n".encode("utf-8"))
        body.extend(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("utf-8"))
        body.extend(value.encode("utf-8"))
        body.extend(b"\r\n")

    body.extend(f"--{boundary}\r\n".encode("utf-8"))
    body.extend(
        (
            f'Content-Disposition: form-data; name="{file_field_name}"; '
            f'filename="{file_name}"\r\n'
        ).encode("utf-8")
    )
    body.extend(f"Content-Type: {file_content_type}\r\n\r\n".encode("utf-8"))
    body.extend(file_bytes)
    body.extend(b"\r\n")
    body.extend(f"--{boundary}--\r\n".encode("utf-8"))

    return bytes(body), f"multipart/form-data; boundary={boundary}"


def _guess_audio_content_type(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix == ".wav":
        return "audio/wav"
    if suffix == ".mp3":
        return "audio/mpeg"
    if suffix == ".m4a":
        return "audio/mp4"
    if suffix == ".flac":
        return "audio/flac"
    if suffix in {".ogg", ".oga"}:
        return "audio/ogg"
    return "application/octet-stream"

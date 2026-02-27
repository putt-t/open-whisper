from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from src.asr.providers import QwenTranscriber, Transcriber, WhisperKitTranscriber
from src.asr.router import router as asr_router
from src.asr.service import ASRService
from src.config import get_settings
from src.postprocess.apple_transcript_cleaner import AppleTranscriptCleaner

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


def _build_transcriber(settings) -> Transcriber:
    if settings.effective_asr_provider == "whisperkit":
        return WhisperKitTranscriber(
            endpoint=settings.dictation_whisperkit_endpoint,
            model_id=settings.effective_whisperkit_model,
            timeout_seconds=settings.dictation_whisperkit_timeout_seconds,
            language=settings.effective_whisperkit_language,
            prompt=settings.dictation_whisperkit_prompt,
        )

    return QwenTranscriber(
        model_id=settings.resolved_model_id,
        temp_dir=settings.dictation_tmp_dir,
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    transcriber = _build_transcriber(settings)
    transcript_cleaner = (
        AppleTranscriptCleaner(
            instructions=settings.dictation_cleanup_instructions,
            user_dictionary_terms=settings.effective_cleanup_user_dictionary_terms,
        )
        if settings.effective_cleanup_enabled
        else None
    )
    asr_service = ASRService(
        transcriber=transcriber,
        auth_token_file=settings.dictation_asr_token_file,
        log_transcripts=settings.dictation_log_transcripts,
        transcript_cleaner=transcript_cleaner,
    )
    app.state.asr_service = asr_service
    await asr_service.startup()
    try:
        yield
    finally:
        await asr_service.shutdown()


app = FastAPI(title="Local Dictation ASR", lifespan=lifespan)
app.include_router(asr_router)

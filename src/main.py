from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from src.asr.providers import QwenTranscriber, Transcriber, WhisperKitTranscriber
from src.asr.router import router as asr_router
from src.asr.service import ASRService
from src.config import get_settings
from src.postprocess.apple_transcript_cleaner import AppleTranscriptCleaner
from src.postprocess.lmstudio_transcript_cleaner import LMStudioTranscriptCleaner

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


def _build_transcript_cleaner(settings):
    if not settings.effective_cleanup_enabled:
        return None

    if settings.effective_cleanup_provider == "lmstudio":
        return LMStudioTranscriptCleaner(
            endpoint=settings.dictation_lmstudio_endpoint,
            model=settings.effective_cleanup_model,
            system_prompt=settings.effective_cleanup_instructions,
            user_dictionary_terms=settings.effective_cleanup_user_dictionary_terms,
            temperature=settings.dictation_lmstudio_temperature,
            max_output_tokens=settings.dictation_lmstudio_max_output_tokens,
            timeout_seconds=settings.dictation_lmstudio_timeout_seconds,
            debug=settings.effective_debug_mode,
        )

    return AppleTranscriptCleaner(
        instructions=settings.effective_cleanup_instructions,
        user_dictionary_terms=settings.effective_cleanup_user_dictionary_terms,
        debug=settings.effective_debug_mode,
        temperature=settings.dictation_apple_temperature,
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    logging.getLogger(__name__).info(
        "effective_settings: asr_provider=%s cleanup_enabled=%s cleanup_provider=%s debug_mode=%s",
        settings.effective_asr_provider,
        settings.effective_cleanup_enabled,
        settings.effective_cleanup_provider,
        settings.effective_debug_mode,
    )
    transcriber = _build_transcriber(settings)
    transcript_cleaner = _build_transcript_cleaner(settings)
    asr_service = ASRService(
        transcriber=transcriber,
        auth_token_file=settings.dictation_asr_token_file,
        log_transcripts=settings.dictation_log_transcripts,
        transcript_cleaner=transcript_cleaner,
        debug_mode=settings.effective_debug_mode,
    )
    app.state.asr_service = asr_service
    await asr_service.startup()
    try:
        yield
    finally:
        await asr_service.shutdown()


app = FastAPI(title="Local Dictation ASR", lifespan=lifespan)
app.include_router(asr_router)

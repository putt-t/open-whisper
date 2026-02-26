from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from src.asr.router import router as asr_router
from src.asr.service import ASRService
from src.config import get_settings
from src.postprocess.apple_transcript_cleaner import AppleTranscriptCleaner

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    transcript_cleaner = (
        AppleTranscriptCleaner(instructions=settings.dictation_cleanup_instructions)
        if settings.dictation_cleanup_enabled
        else None
    )
    asr_service = ASRService(
        model_id=settings.resolved_model_id,
        temp_dir=settings.dictation_tmp_dir,
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

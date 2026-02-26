from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from src.asr.router import router as asr_router
from src.asr.service import ASRService
from src.config import get_settings

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    asr_service = ASRService(
        model_id=settings.resolved_model_id,
        temp_dir=settings.dictation_tmp_dir,
        log_transcripts=settings.dictation_log_transcripts,
    )
    app.state.asr_service = asr_service
    await asr_service.startup()
    try:
        yield
    finally:
        await asr_service.shutdown()


app = FastAPI(title="Local Dictation ASR", lifespan=lifespan)
app.include_router(asr_router)


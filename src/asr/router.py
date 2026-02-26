from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, File, Header, HTTPException, UploadFile, status

from src.asr.dependencies import get_asr_service
from src.asr.schemas import HealthResponse, TranscribeResponse
from src.asr.service import ASRService

logger = logging.getLogger(__name__)
router = APIRouter(tags=["asr"])


@router.get("/health", response_model=HealthResponse)
async def health(service: ASRService = Depends(get_asr_service)) -> HealthResponse:
    return HealthResponse(model=service.model_id)


@router.post("/transcribe", response_model=TranscribeResponse)
async def transcribe(
    audio: UploadFile = File(...),
    x_dictation_token: str | None = Header(default=None, alias="X-Dictation-Token"),
    service: ASRService = Depends(get_asr_service),
) -> TranscribeResponse:
    if not service.authorize(x_dictation_token):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid authentication token",
        )

    try:
        text = await service.transcribe(audio)
    except Exception as exc:
        logger.exception("Transcription failed")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"transcription failed: {exc}",
        ) from exc
    return TranscribeResponse(text=text)

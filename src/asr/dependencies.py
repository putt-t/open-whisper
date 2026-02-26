from __future__ import annotations

from fastapi import HTTPException, Request, status

from src.asr.service import ASRService


async def get_asr_service(request: Request) -> ASRService:
    service: ASRService | None = getattr(request.app.state, "asr_service", None)
    if service is None or not service.is_ready:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="model not loaded")
    return service


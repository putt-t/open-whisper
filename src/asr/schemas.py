from __future__ import annotations

from pydantic import BaseModel


class HealthResponse(BaseModel):
    status: str = "ok"
    model: str


class TranscribeResponse(BaseModel):
    text: str


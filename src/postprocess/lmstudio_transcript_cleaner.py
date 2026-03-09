from __future__ import annotations

import asyncio
import json
import logging
from typing import Any
from urllib import request

logger = logging.getLogger(__name__)


class LMStudioTranscriptCleaner:
    """Optional transcript cleanup using a local LM Studio Responses API server."""

    def __init__(
        self,
        endpoint: str,
        model: str,
        system_prompt: str,
        user_dictionary_terms: list[str] | None = None,
        temperature: float = 0.1,
        max_output_tokens: int = 96,
        timeout_seconds: float = 30.0,
        debug: bool = False,
    ) -> None:
        self.endpoint = endpoint
        self.model = model
        self.system_prompt = system_prompt
        self.user_dictionary_terms = user_dictionary_terms or []
        self.temperature = temperature
        self.max_output_tokens = max_output_tokens
        self.timeout_seconds = timeout_seconds
        self.debug = debug
        logger.info(
            "LM Studio transcript cleanup enabled: endpoint=%s model=%s temperature=%.3f max_output_tokens=%d",
            self.endpoint,
            self.model,
            self.temperature,
            self.max_output_tokens,
        )

    async def clean(self, transcript: str) -> str:
        text = transcript.strip()
        if not text:
            return text

        payload = self._build_payload(text)

        try:
            response_data = await asyncio.to_thread(self._post_json, payload)
        except Exception as exc:
            logger.warning("LM Studio cleanup request failed: %s", exc)
            return text

        extracted = self._extract_output_text(response_data)
        if self.debug:
            logger.info("LM Studio cleanup model_output_raw: %s", extracted)
        cleaned = extracted.strip()
        return cleaned or text

    def _build_payload(self, transcript: str) -> dict[str, Any]:
        system_text = (
            f"{self.system_prompt.strip()}\n\n"
            f"{self._dictionary_prompt_section()}"
        )
        user_text = (
            f"{transcript}\n"
        )
        return {
            "model": self.model,
            "temperature": self.temperature,
            "max_output_tokens": self.max_output_tokens,
            "input": [
                {"role": "system", "content": system_text},
                {"role": "user", "content": user_text},
            ],
        }

    def _dictionary_prompt_section(self) -> str:
        if not self.user_dictionary_terms:
            return ""

        terms = "\n".join(f"- {term}" for term in self.user_dictionary_terms)
        return (
            "User dictionary terms (preferred canonical spellings):\n"
            f"{terms}\n"
            "Treat these as high-priority canonical spellings.\n"
            "If transcript words are phonetically similar to a dictionary term, normalize to the dictionary term.\n"
            "This includes split/space-separated ASR variants that sound like one term.\n"
            "Do not force replacements when phonetic/context match is weak.\n\n"
        )

    def _post_json(self, payload: dict[str, Any]) -> dict[str, Any]:
        body = json.dumps(payload).encode("utf-8")
        req = request.Request(
            self.endpoint,
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with request.urlopen(req, timeout=self.timeout_seconds) as resp:
            raw = resp.read().decode("utf-8")
        parsed = json.loads(raw)
        if not isinstance(parsed, dict):
            raise ValueError("LM Studio response is not a JSON object")
        return parsed

    def _extract_output_text(self, response_data: dict[str, Any]) -> str:
        output_text = response_data.get("output_text")
        if isinstance(output_text, str) and output_text.strip():
            return output_text

        output_items = response_data.get("output")
        if isinstance(output_items, list):
            texts: list[str] = []
            for item in output_items:
                if not isinstance(item, dict):
                    continue
                content = item.get("content")
                if isinstance(content, list):
                    for chunk in content:
                        if not isinstance(chunk, dict):
                            continue
                        text = chunk.get("text")
                        if isinstance(text, str) and text.strip():
                            texts.append(text)
                text = item.get("text")
                if isinstance(text, str) and text.strip():
                    texts.append(text)
            if texts:
                return "\n".join(texts)

        choices = response_data.get("choices")
        if isinstance(choices, list) and choices:
            first = choices[0]
            if isinstance(first, dict):
                message = first.get("message")
                if isinstance(message, dict):
                    content = message.get("content")
                    if isinstance(content, str) and content.strip():
                        return content

        content = response_data.get("content")
        if isinstance(content, str) and content.strip():
            return content

        raise ValueError("LM Studio cleanup response did not contain output text")

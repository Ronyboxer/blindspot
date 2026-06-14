from __future__ import annotations

import base64
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import json
import mimetypes
from pathlib import Path
import re
from typing import Any

from .config import DeviceConfig
from .store import RideMetrics


HACKCLUB_CHAT_COMPLETIONS_URL = "https://ai.hackclub.com/proxy/v1/chat/completions"
DEFAULT_QWEN_MODEL = "qwen/qwen3.7-plus"


@dataclass(frozen=True)
class RideSummaryResult:
    ride_id: str
    model: str
    score: int
    rating: str
    summary: str
    labels: list[str]
    observations: list[str]
    recommended_map_tags: list[str]
    potholes_detected: bool
    pothole_count: int | None
    road_hazards: list[str]
    confidence: float | None
    raw_response: dict[str, Any]
    created_at: str
    metrics: RideMetrics

    def to_supabase_update(self) -> dict[str, Any]:
        metrics_payload = asdict(self.metrics)
        qwen_summary = {
            "model": self.model,
            "score": self.score,
            "rating": self.rating,
            "summary": self.summary,
            "labels": self.labels,
            "observations": self.observations,
            "recommended_map_tags": self.recommended_map_tags,
            "potholes_detected": self.potholes_detected,
            "pothole_count": self.pothole_count,
            "road_hazards": self.road_hazards,
            "confidence": self.confidence,
            "metrics": metrics_payload,
            "raw_response": self.raw_response,
        }
        return {
            "distance_m": round(self.metrics.distance_m, 2),
            "duration_s": round(self.metrics.duration_s, 2),
            "photo_count": self.metrics.photo_count,
            "accessibility_score": self.score,
            "accessibility_rating": self.rating,
            "accessibility_summary": self.summary,
            "accessibility_labels": self.labels,
            "accessibility_observations": self.observations,
            "accessibility_map_tags": self.recommended_map_tags,
            "accessibility_model": self.model,
            "potholes_detected": self.potholes_detected,
            "pothole_count": self.pothole_count,
            "road_hazards": self.road_hazards,
            "qwen_summary": qwen_summary,
            "summarized_at": self.created_at,
        }

    def to_ai_summary_insert(
        self,
        user_id: str | None = None,
        device_id: str | None = None,
    ) -> dict[str, Any]:
        metrics_payload = asdict(self.metrics)
        row: dict[str, Any] = {
            "ride_id": self.ride_id,
            "device_id": device_id,
            "model": self.model,
            "summary_type": "ride",
            "summary": self.summary,
            "accessibility_score": self.score,
            "accessibility_rating": self.rating,
            "potholes_detected": self.potholes_detected,
            "pothole_count": self.pothole_count,
            "labels": self.labels,
            "observations": self.observations,
            "road_hazards": self.road_hazards,
            "recommended_map_tags": self.recommended_map_tags,
            "distance_m": round(self.metrics.distance_m, 2),
            "duration_s": round(self.metrics.duration_s, 2),
            "photo_count": self.metrics.photo_count,
            "metrics": metrics_payload,
            "raw_response": self.raw_response,
            "created_at": self.created_at,
        }
        if user_id:
            row["user_id"] = user_id
        return row


class QwenRideSummarizer:
    def __init__(
        self,
        api_key: str | None,
        model: str = DEFAULT_QWEN_MODEL,
        endpoint: str = HACKCLUB_CHAT_COMPLETIONS_URL,
        timeout_s: float = 60.0,
        max_images: int = 24,
    ) -> None:
        self.api_key = api_key
        self.model = model
        self.endpoint = endpoint
        self.timeout_s = timeout_s
        self.max_images = max_images

    @classmethod
    def from_config(cls, config: DeviceConfig) -> QwenRideSummarizer:
        return cls(
            api_key=config.hackclub_ai_api_key,
            model=config.hackclub_ai_model,
            endpoint=config.hackclub_ai_endpoint,
            timeout_s=config.hackclub_ai_timeout_s,
            max_images=config.hackclub_ai_max_images,
        )

    @property
    def enabled(self) -> bool:
        return bool(self.api_key)

    def summarize(
        self,
        metrics: RideMetrics,
        photo_paths: list[Path],
    ) -> RideSummaryResult | None:
        if not self.enabled:
            return None

        selected_paths = _select_photo_paths(photo_paths, self.max_images)
        existing_paths = [path for path in selected_paths if path.exists()]
        payload = self._build_payload(metrics, existing_paths, len(photo_paths))
        response = self._post_chat_completion(payload)
        text = _message_text(response)
        parsed = _extract_json_object(text)
        return _summary_result_from_json(
            ride_id=metrics.ride_id,
            model=self.model,
            metrics=metrics,
            parsed=parsed,
        )

    def _build_payload(
        self,
        metrics: RideMetrics,
        photo_paths: list[Path],
        total_photo_count: int,
    ) -> dict[str, Any]:
        prompt = _ride_prompt(metrics, total_photo_count, len(photo_paths), self.max_images)
        content: list[dict[str, Any]] = [{"type": "text", "text": prompt}]
        content.extend(_image_content(path) for path in photo_paths)
        return {
            "model": self.model,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "You are a bike-infrastructure and road-hazard vision auditor. "
                        "Return compact JSON only."
                    ),
                },
                {"role": "user", "content": content},
            ],
            "temperature": 0.1,
            "max_tokens": 1400,
        }

    def _post_chat_completion(self, payload: dict[str, Any]) -> dict[str, Any]:
        try:
            import requests
        except ImportError as exc:
            raise RuntimeError("Install requests to call Hack Club AI for ride summaries") from exc

        response = requests.post(
            self.endpoint,
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
            json=payload,
            timeout=self.timeout_s,
        )
        if response.status_code >= 400:
            raise RuntimeError(
                f"Hack Club AI request failed with HTTP {response.status_code}: "
                f"{response.text[:400]}"
            )
        return response.json()


def _ride_prompt(
    metrics: RideMetrics,
    total_photo_count: int,
    attached_photo_count: int,
    max_images: int,
) -> str:
    metrics_payload = {
        "ride_id": metrics.ride_id,
        "distance_m": round(metrics.distance_m, 2),
        "distance_miles": round(metrics.distance_m / 1609.344, 3),
        "duration_s": round(metrics.duration_s, 2),
        "avg_speed_mps": round(metrics.avg_speed_mps, 2),
        "gps_point_count": metrics.point_count,
        "event_count": metrics.event_count,
        "total_photo_count": total_photo_count,
        "attached_photo_count": attached_photo_count,
        "max_images_config": max_images,
    }
    return (
        "Analyze these post-ride bike photos and ride metrics for bike accessibility.\n"
        f"Ride metrics JSON: {json.dumps(metrics_payload, separators=(',', ':'))}\n"
        "Look specifically for green bike-lane or bike-path paint, bicycle symbols or signs "
        "painted on the ground, protected bike lanes, painted-only bike lanes, missing bike "
        "lanes, blocked lanes, rough pavement, potholes, cracks, debris, dangerous shoulders, "
        "drain grates, and intersection/crossing quality. Treat potholes and surface defects "
        "as first-class hazards; include clear evidence when they are visible, and say none "
        "detected when the photos do not show them.\n"
        "Rate the ride or segment from 0 to 100 for bike accessibility. Use good for 75-100, "
        "fair for 45-74, and poor for 0-44 unless the image evidence strongly suggests a "
        "different rating.\n"
        "Return only one JSON object with this exact shape: "
        '{"score":number,"rating":"good|fair|poor","summary":"one short sentence",'
        '"labels":["short_snake_case"],"observations":["short evidence strings"],'
        '"recommended_map_tags":["short_snake_case"],"potholes_detected":boolean,'
        '"pothole_count":number,"road_hazards":["short_snake_case"],"confidence":number}'
    )


def _select_photo_paths(photo_paths: list[Path], max_images: int) -> list[Path]:
    if max_images <= 0 or len(photo_paths) <= max_images:
        return photo_paths
    if max_images == 1:
        return [photo_paths[len(photo_paths) // 2]]

    indexes = {
        round(index * (len(photo_paths) - 1) / (max_images - 1))
        for index in range(max_images)
    }
    return [photo_paths[index] for index in sorted(indexes)]


def _image_content(path: Path) -> dict[str, Any]:
    return {"type": "image_url", "image_url": {"url": _image_data_url(path)}}


def _image_data_url(path: Path) -> str:
    mime_type = mimetypes.guess_type(path.name)[0] or "image/jpeg"
    data = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime_type};base64,{data}"


def _message_text(response: dict[str, Any]) -> str:
    choices = response.get("choices")
    if not isinstance(choices, list) or not choices:
        raise RuntimeError("Hack Club AI response did not include choices")
    message = choices[0].get("message", {})
    content = message.get("content", "")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = [
            part.get("text", "")
            for part in content
            if isinstance(part, dict) and part.get("type") in {None, "text"}
        ]
        return "\n".join(parts)
    return str(content)


def _extract_json_object(text: str) -> dict[str, Any]:
    stripped = text.strip()
    fenced = re.search(r"```(?:json)?\s*(.*?)\s*```", stripped, flags=re.DOTALL)
    if fenced:
        stripped = fenced.group(1).strip()
    try:
        parsed = json.loads(stripped)
    except json.JSONDecodeError:
        start = stripped.find("{")
        end = stripped.rfind("}")
        if start < 0 or end < start:
            raise RuntimeError(f"Hack Club AI response was not JSON: {text[:300]}") from None
        parsed = json.loads(stripped[start : end + 1])
    if not isinstance(parsed, dict):
        raise RuntimeError("Hack Club AI JSON response was not an object")
    return parsed


def _summary_result_from_json(
    ride_id: str,
    model: str,
    metrics: RideMetrics,
    parsed: dict[str, Any],
) -> RideSummaryResult:
    score = _clamp_score(parsed.get("score"))
    rating = _normalize_rating(parsed.get("rating"), score)
    return RideSummaryResult(
        ride_id=ride_id,
        model=model,
        score=score,
        rating=rating,
        summary=str(parsed.get("summary") or "No bike accessibility summary returned."),
        labels=_string_list(parsed.get("labels")),
        observations=_string_list(parsed.get("observations")),
        recommended_map_tags=_string_list(parsed.get("recommended_map_tags")),
        potholes_detected=_bool_value(parsed.get("potholes_detected")),
        pothole_count=_optional_int(parsed.get("pothole_count")),
        road_hazards=_string_list(parsed.get("road_hazards")),
        confidence=_optional_float(parsed.get("confidence")),
        raw_response=parsed,
        created_at=datetime.now(timezone.utc).isoformat(),
        metrics=metrics,
    )


def _clamp_score(value: Any) -> int:
    try:
        score = int(round(float(value)))
    except (TypeError, ValueError):
        score = 0
    return max(0, min(100, score))


def _normalize_rating(value: Any, score: int) -> str:
    rating = str(value or "").strip().lower()
    if rating in {"good", "fair", "poor"}:
        return rating
    if score >= 75:
        return "good"
    if score >= 45:
        return "fair"
    return "poor"


def _string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(item).strip() for item in value if str(item).strip()]


def _optional_float(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _optional_int(value: Any) -> int | None:
    if value is None:
        return None
    try:
        return max(0, int(round(float(value))))
    except (TypeError, ValueError):
        return None


def _bool_value(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"true", "yes", "1"}
    return bool(value)

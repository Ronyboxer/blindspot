from __future__ import annotations

import base64
from dataclasses import asdict
from datetime import datetime, timezone
import mimetypes
from pathlib import Path
from typing import Any

from .config import DeviceConfig
from .ride_summary import RideSummaryResult
from .store import RideMetrics


class RideSummaryServiceClient:
    def __init__(
        self,
        base_url: str | None,
        device_id: str,
        token: str | None = None,
        timeout_s: float = 180.0,
    ) -> None:
        self.base_url = base_url.rstrip("/") if base_url else None
        self.device_id = device_id
        self.token = token
        self.timeout_s = timeout_s

    @classmethod
    def from_config(cls, config: DeviceConfig) -> RideSummaryServiceClient:
        return cls(
            base_url=config.summary_service_url,
            device_id=config.device_id,
            token=config.summary_service_token,
            timeout_s=config.summary_service_timeout_s,
        )

    @property
    def enabled(self) -> bool:
        return bool(self.base_url)

    def summarize(
        self,
        metrics: RideMetrics,
        photo_paths: list[Path],
    ) -> RideSummaryResult | None:
        if not self.enabled:
            return None

        try:
            import requests
        except ImportError as exc:
            raise RuntimeError("Install requests on the Pi to use the ride summary service") from exc

        payload = {
            "device_id": self.device_id,
            "metrics": asdict(metrics),
            "photos": [_photo_payload(path) for path in photo_paths if path.exists()],
        }
        headers = {"Content-Type": "application/json", "Accept": "application/json"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"

        response = requests.post(
            f"{self.base_url}/blindspot/summary/ride",
            json=payload,
            headers=headers,
            timeout=self.timeout_s,
        )
        if response.status_code >= 400:
            raise RuntimeError(
                f"Ride summary service request failed with HTTP {response.status_code}: "
                f"{response.text[:400]}"
            )

        parsed = response.json()
        if not isinstance(parsed, dict) or not parsed.get("ok", True):
            raise RuntimeError(f"Ride summary service returned an error: {parsed}")
        summary = parsed.get("summary")
        if summary is None:
            return None
        if not isinstance(summary, dict):
            raise RuntimeError("Ride summary service response summary must be a JSON object")
        return ride_summary_result_from_payload(summary)


def ride_summary_result_to_payload(result: RideSummaryResult) -> dict[str, Any]:
    return {
        "ride_id": result.ride_id,
        "model": result.model,
        "score": result.score,
        "rating": result.rating,
        "summary": result.summary,
        "labels": result.labels,
        "observations": result.observations,
        "recommended_map_tags": result.recommended_map_tags,
        "potholes_detected": result.potholes_detected,
        "pothole_count": result.pothole_count,
        "road_hazards": result.road_hazards,
        "confidence": result.confidence,
        "raw_response": result.raw_response,
        "created_at": result.created_at,
        "metrics": asdict(result.metrics),
    }


def ride_summary_result_from_payload(payload: dict[str, Any]) -> RideSummaryResult:
    metrics_payload = payload.get("metrics")
    if not isinstance(metrics_payload, dict):
        raise RuntimeError("Ride summary service result is missing metrics")
    metrics = RideMetrics(
        ride_id=str(metrics_payload["ride_id"]),
        started_at=str(metrics_payload["started_at"]),
        ended_at=(
            str(metrics_payload["ended_at"]) if metrics_payload.get("ended_at") is not None else None
        ),
        duration_s=float(metrics_payload["duration_s"]),
        distance_m=float(metrics_payload["distance_m"]),
        avg_speed_mps=float(metrics_payload["avg_speed_mps"]),
        point_count=int(metrics_payload["point_count"]),
        event_count=int(metrics_payload["event_count"]),
        photo_count=int(metrics_payload["photo_count"]),
    )
    return RideSummaryResult(
        ride_id=str(payload.get("ride_id") or metrics.ride_id),
        model=str(payload["model"]),
        score=int(payload["score"]),
        rating=str(payload["rating"]),
        summary=str(payload["summary"]),
        labels=_string_list(payload.get("labels")),
        observations=_string_list(payload.get("observations")),
        recommended_map_tags=_string_list(payload.get("recommended_map_tags")),
        potholes_detected=bool(payload.get("potholes_detected")),
        pothole_count=(
            int(payload["pothole_count"]) if payload.get("pothole_count") is not None else None
        ),
        road_hazards=_string_list(payload.get("road_hazards")),
        confidence=float(payload["confidence"]) if payload.get("confidence") is not None else None,
        raw_response=payload.get("raw_response") if isinstance(payload.get("raw_response"), dict) else {},
        created_at=str(payload.get("created_at") or datetime.now(timezone.utc).isoformat()),
        metrics=metrics,
    )


def _photo_payload(path: Path) -> dict[str, str]:
    mime_type = mimetypes.guess_type(path.name)[0] or "image/jpeg"
    return {
        "filename": path.name,
        "content_type": mime_type,
        "data_b64": base64.b64encode(path.read_bytes()).decode("ascii"),
    }


def _string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(item) for item in value]

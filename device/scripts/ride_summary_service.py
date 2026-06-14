from __future__ import annotations

import argparse
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import tempfile
from typing import Any

from device.blindspot_device.summary_service import ride_summary_result_to_payload
from device.blindspot_device.config import DeviceConfig
from device.blindspot_device.ride_summary import QwenRideSummarizer
from device.blindspot_device.store import RideMetrics


class _SummaryState:
    def __init__(self, config: DeviceConfig) -> None:
        self.config = config
        self.summarizer = QwenRideSummarizer.from_config(config)


class _SummaryHandler(BaseHTTPRequestHandler):
    state: _SummaryState

    def do_GET(self) -> None:
        if self.path != "/health":
            self._write_json(404, {"ok": False, "error": "not_found"})
            return
        self._write_json(200, {"ok": True, "service": "blindspot-ride-summary-service"})

    def do_POST(self) -> None:
        if self.path != "/blindspot/summary/ride":
            self._write_json(404, {"ok": False, "error": "not_found"})
            return
        if not self._authorized():
            self._write_json(401, {"ok": False, "error": "unauthorized"})
            return
        if not self.state.summarizer.enabled:
            self._write_json(503, {"ok": False, "error": "missing_hackclub_ai_key"})
            return

        try:
            payload = self._read_json()
            metrics = _metrics_from_payload(payload.get("metrics"))
            photos = payload.get("photos")
            if not isinstance(photos, list):
                raise ValueError("photos must be a list")
            with tempfile.TemporaryDirectory(prefix="blindspot-summary-") as tmp:
                photo_paths = _write_photos(Path(tmp), photos)
                result = self.state.summarizer.summarize(metrics, photo_paths)
            self._write_json(
                200,
                {
                    "ok": True,
                    "summary": ride_summary_result_to_payload(result) if result else None,
                },
            )
        except Exception as exc:
            self._write_json(500, {"ok": False, "error": str(exc)})

    def _authorized(self) -> bool:
        token = self.state.config.summary_service_token
        if not token:
            return True
        return self.headers.get("Authorization") == f"Bearer {token}"

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        data = self.rfile.read(length).decode("utf-8")
        parsed = json.loads(data) if data else {}
        if not isinstance(parsed, dict):
            raise ValueError("request body must be a JSON object")
        return parsed

    def _write_json(self, status: int, payload: dict[str, Any]) -> None:
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"{self.client_address[0]} - {fmt % args}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Run Blind Spot ride summary service")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    config = DeviceConfig()
    _SummaryHandler.state = _SummaryState(config)
    server = ThreadingHTTPServer((args.host, args.port), _SummaryHandler)
    print(f"Blind Spot ride summary service listening on http://{args.host}:{args.port}")
    print("Endpoint: POST /blindspot/summary/ride")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Stopping ride summary service")
    finally:
        server.server_close()


def _metrics_from_payload(payload: Any) -> RideMetrics:
    if not isinstance(payload, dict):
        raise ValueError("metrics must be a JSON object")
    return RideMetrics(
        ride_id=str(payload["ride_id"]),
        started_at=str(payload["started_at"]),
        ended_at=str(payload["ended_at"]) if payload.get("ended_at") is not None else None,
        duration_s=float(payload["duration_s"]),
        distance_m=float(payload["distance_m"]),
        avg_speed_mps=float(payload["avg_speed_mps"]),
        point_count=int(payload["point_count"]),
        event_count=int(payload["event_count"]),
        photo_count=int(payload["photo_count"]),
    )


def _write_photos(directory: Path, photos: list[Any]) -> list[Path]:
    paths: list[Path] = []
    for index, photo in enumerate(photos):
        if not isinstance(photo, dict):
            continue
        name = _safe_name(str(photo.get("filename") or f"photo-{index}.jpg"))
        raw = base64.b64decode(str(photo["data_b64"]))
        path = directory / name
        path.write_bytes(raw)
        paths.append(path)
    return paths


def _safe_name(name: str) -> str:
    safe = "".join(char if char.isalnum() or char in {".", "-", "_"} else "_" for char in name)
    return safe.strip("._") or "photo.jpg"


if __name__ == "__main__":
    main()

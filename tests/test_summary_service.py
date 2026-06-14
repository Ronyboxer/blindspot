from __future__ import annotations

from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
import tempfile
import threading
import unittest

from device.blindspot_device.summary_service import RideSummaryServiceClient
from device.blindspot_device.store import RideMetrics


class _SummaryHandler(BaseHTTPRequestHandler):
    calls: list[dict] = []

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length).decode("utf-8"))
        self.calls.append(payload)
        metrics = payload["metrics"]
        response = {
            "ok": True,
            "summary": {
                "ride_id": metrics["ride_id"],
                "model": "local/test",
                "score": 81,
                "rating": "good",
                "summary": "Bike lane visible.",
                "labels": ["bike_lane"],
                "observations": ["green paint visible"],
                "recommended_map_tags": ["painted_lane"],
                "potholes_detected": False,
                "pothole_count": 0,
                "road_hazards": [],
                "confidence": 0.8,
                "raw_response": {"ok": True},
                "created_at": "2026-06-13T00:00:00+00:00",
                "metrics": metrics,
            },
        }
        data = json.dumps(response).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args) -> None:
        return


class RideSummaryServiceClientTests(unittest.TestCase):
    def setUp(self) -> None:
        _SummaryHandler.calls = []
        self.server = HTTPServer(("127.0.0.1", 0), _SummaryHandler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        host, port = self.server.server_address
        self.base_url = f"http://{host}:{port}"

    def tearDown(self) -> None:
        self.server.shutdown()
        self.thread.join(timeout=2)
        self.server.server_close()

    def test_summarize_uploads_metrics_and_photos_to_summary_service(self) -> None:
        client = RideSummaryServiceClient(
            base_url=self.base_url,
            device_id="pi-test",
            token="token",
            timeout_s=2,
        )
        metrics = RideMetrics(
            ride_id="ride-1",
            started_at="2026-06-13T00:00:00+00:00",
            ended_at="2026-06-13T00:10:00+00:00",
            duration_s=600.0,
            distance_m=1200.0,
            avg_speed_mps=2.0,
            point_count=10,
            event_count=1,
            photo_count=1,
        )
        with tempfile.TemporaryDirectory() as tmp:
            photo = Path(tmp) / "capture.jpg"
            photo.write_bytes(b"jpeg")
            result = client.summarize(metrics, [photo])

        self.assertIsNotNone(result)
        self.assertEqual(result.score if result else None, 81)
        self.assertEqual(result.to_supabase_update()["accessibility_rating"], "good")
        self.assertEqual(_SummaryHandler.calls[0]["device_id"], "pi-test")
        self.assertEqual(_SummaryHandler.calls[0]["metrics"]["ride_id"], "ride-1")
        self.assertEqual(_SummaryHandler.calls[0]["photos"][0]["filename"], "capture.jpg")
        self.assertNotIn("gps", _SummaryHandler.calls[0])

    def test_disabled_without_base_url(self) -> None:
        client = RideSummaryServiceClient(base_url=None, device_id="pi-test")

        self.assertFalse(client.enabled)


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

from pathlib import Path
import tempfile
import unittest

from device.blindspot_device.camera import PLACEHOLDER_JPEG
from device.blindspot_device.ride_summary import QwenRideSummarizer
from device.blindspot_device.store import RideMetrics


class _FakeQwenRideSummarizer(QwenRideSummarizer):
    def __init__(self) -> None:
        super().__init__(api_key="test-key", model="qwen/test", max_images=1)
        self.last_payload = None

    def _post_chat_completion(self, payload):
        self.last_payload = payload
        return {
            "choices": [
                {
                    "message": {
                        "content": """
                        ```json
                        {
                          "score": 91,
                          "rating": "good",
                          "summary": "Green painted bike lane with pavement symbols.",
                          "labels": ["green_bike_lane", "bike_symbol"],
                          "observations": ["clear green paint", "bike icon visible"],
                          "recommended_map_tags": ["comfortable_bike_access"],
                          "potholes_detected": true,
                          "pothole_count": 2,
                          "road_hazards": ["pothole", "rough_pavement"],
                          "confidence": 0.86
                        }
                        ```
                        """,
                    }
                }
            ]
        }


class RideSummaryTests(unittest.TestCase):
    def test_summarize_parses_qwen_json_and_builds_supabase_payload(self) -> None:
        metrics = RideMetrics(
            ride_id="ride-1",
            started_at="2026-06-13T12:00:00+00:00",
            ended_at="2026-06-13T12:10:00+00:00",
            duration_s=600,
            distance_m=2414.0,
            avg_speed_mps=4.02,
            point_count=10,
            event_count=2,
            photo_count=2,
        )

        with tempfile.TemporaryDirectory() as tmp:
            photo = Path(tmp) / "photo.jpg"
            photo.write_bytes(PLACEHOLDER_JPEG)
            summarizer = _FakeQwenRideSummarizer()

            result = summarizer.summarize(metrics, [photo, photo])

        self.assertIsNotNone(result)
        assert result is not None
        self.assertEqual(result.score, 91)
        self.assertEqual(result.rating, "good")
        self.assertIn("green_bike_lane", result.labels)
        self.assertTrue(result.potholes_detected)
        self.assertEqual(result.pothole_count, 2)
        self.assertIn("pothole", result.road_hazards)
        self.assertEqual(result.confidence, 0.86)
        self.assertIsNotNone(summarizer.last_payload)
        image_items = [
            item
            for item in summarizer.last_payload["messages"][1]["content"]
            if item["type"] == "image_url"
        ]
        self.assertEqual(len(image_items), 1)
        self.assertTrue(image_items[0]["image_url"]["url"].startswith("data:image/jpeg;base64,"))

        payload = result.to_supabase_update()
        self.assertEqual(payload["distance_m"], 2414.0)
        self.assertEqual(payload["duration_s"], 600)
        self.assertEqual(payload["accessibility_score"], 91)
        self.assertEqual(payload["accessibility_rating"], "good")
        self.assertTrue(payload["potholes_detected"])
        self.assertEqual(payload["pothole_count"], 2)
        self.assertEqual(payload["qwen_summary"]["metrics"]["photo_count"], 2)

        insert = result.to_ai_summary_insert(user_id="user-1", device_id="pi-test")
        self.assertEqual(insert["ride_id"], "ride-1")
        self.assertEqual(insert["user_id"], "user-1")
        self.assertEqual(insert["device_id"], "pi-test")
        self.assertEqual(insert["summary_type"], "ride")
        self.assertEqual(insert["accessibility_score"], 91)
        self.assertEqual(insert["road_hazards"], ["pothole", "rough_pavement"])


if __name__ == "__main__":
    unittest.main()

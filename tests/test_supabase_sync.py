from __future__ import annotations

from pathlib import Path
import tempfile
import unittest

from device.blindspot_device.supabase_sync import SupabasePhotoUploader


class _Response:
    def __init__(self, data=None) -> None:
        self.data = data


class _Query:
    def __init__(self, table_name: str, calls: list[tuple], response_data=None) -> None:
        self.table_name = table_name
        self.calls = calls
        self.response_data = response_data

    def upsert(self, row: dict):
        self.calls.append(("upsert", self.table_name, row))
        return self

    def select(self, columns: str):
        self.calls.append(("select", self.table_name, columns))
        return self

    def update(self, row: dict):
        self.calls.append(("update", self.table_name, row))
        return self

    def insert(self, row: dict):
        self.calls.append(("insert", self.table_name, row))
        return self

    def eq(self, column: str, value: str):
        self.calls.append(("eq", self.table_name, column, value))
        return self

    def is_(self, column: str, value: str):
        self.calls.append(("is", self.table_name, column, value))
        return self

    def order(self, column: str, desc: bool = False):
        self.calls.append(("order", self.table_name, column, desc))
        return self

    def limit(self, count: int):
        self.calls.append(("limit", self.table_name, count))
        return self

    def execute(self):
        return _Response(data=self.response_data or [{"id": "photo-1"}])


class _Bucket:
    def __init__(self, bucket_name: str, calls: list[tuple]) -> None:
        self.bucket_name = bucket_name
        self.calls = calls

    def upload(self, path: str, file, file_options: dict):
        self.calls.append(("upload", self.bucket_name, path, file.read(), file_options))
        return _Response()

    def get_public_url(self, path: str):
        return f"https://example.test/storage/v1/object/public/{self.bucket_name}/{path}"


class _Storage:
    def __init__(self, calls: list[tuple]) -> None:
        self.calls = calls

    def from_(self, bucket_name: str):
        return _Bucket(bucket_name, self.calls)


class _Client:
    def __init__(self) -> None:
        self.calls: list[tuple] = []
        self.table_responses: dict[str, list[dict]] = {}
        self.storage = _Storage(self.calls)

    def table(self, table_name: str):
        return _Query(table_name, self.calls, self.table_responses.get(table_name))


class SupabasePhotoUploaderTests(unittest.TestCase):
    def test_upload_photo_writes_storage_and_photo_row_with_ride_id(self) -> None:
        client = _Client()
        uploader = SupabasePhotoUploader(
            supabase_url=None,
            supabase_key=None,
            bucket="photos",
            device_id="pi-test",
            client=client,
        )

        with tempfile.TemporaryDirectory() as tmp:
            photo = Path(tmp) / "capture.jpg"
            photo.write_bytes(b"jpeg")
            result = uploader.upload_photo(photo, ride_id="11111111111111111111111111111111")

        self.assertIsNotNone(result)
        upload_call = next(call for call in client.calls if call[0] == "upload")
        self.assertEqual(upload_call[1], "photos")
        self.assertIn("devices/pi-test/rides/11111111111111111111111111111111/", upload_call[2])
        self.assertEqual(upload_call[3], b"jpeg")
        self.assertEqual(upload_call[4]["content-type"], "image/jpeg")

        insert_call = next(call for call in client.calls if call[0] == "insert")
        self.assertEqual(insert_call[1], "photos")
        self.assertEqual(insert_call[2]["ride_id"], "11111111111111111111111111111111")
        self.assertEqual(insert_call[2]["event_type"], "manual_flag")
        self.assertIn("storage/v1/object/public/photos/", insert_call[2]["storage_url"])

    def test_upload_photo_requires_ride_id(self) -> None:
        client = _Client()
        uploader = SupabasePhotoUploader(
            supabase_url=None,
            supabase_key=None,
            bucket="photos",
            device_id="pi-test",
            client=client,
        )

        with tempfile.TemporaryDirectory() as tmp:
            photo = Path(tmp) / "capture.jpg"
            photo.write_bytes(b"jpeg")
            result = uploader.upload_photo(photo, ride_id=None)

        self.assertIsNone(result)
        self.assertEqual(client.calls, [])

    def test_upload_photo_skips_non_manual_capture_types(self) -> None:
        client = _Client()
        uploader = SupabasePhotoUploader(
            supabase_url=None,
            supabase_key=None,
            bucket="photos",
            device_id="pi-test",
            client=client,
        )

        with tempfile.TemporaryDirectory() as tmp:
            photo = Path(tmp) / "qwen-interval.jpg"
            photo.write_bytes(b"jpeg")
            result = uploader.upload_photo(
                photo,
                ride_id="11111111111111111111111111111111",
                event_type="qwen_interval",
            )

        self.assertIsNone(result)
        self.assertEqual(client.calls, [])

    def test_start_and_end_ride_write_rides_table(self) -> None:
        client = _Client()
        uploader = SupabasePhotoUploader(
            supabase_url=None,
            supabase_key=None,
            device_id="pi-test",
            client=client,
        )

        ride_id = "22222222222222222222222222222222"
        uploader.start_ride(ride_id)
        uploader.end_ride(ride_id)

        self.assertEqual(client.calls[0][0], "upsert")
        self.assertEqual(client.calls[0][1], "rides")
        self.assertEqual(client.calls[0][2]["id"], ride_id)
        self.assertEqual(client.calls[1][0], "update")
        self.assertEqual(client.calls[2], ("eq", "rides", "id", ride_id))

    def test_current_ride_prefers_user_active_ride(self) -> None:
        client = _Client()
        client.table_responses["rides"] = [{"id": "active-ride-1"}]
        uploader = SupabasePhotoUploader(
            supabase_url=None,
            supabase_key=None,
            device_id="pi-test",
            user_id="user-1",
            client=client,
        )

        self.assertEqual(uploader.current_ride_id(), "active-ride-1")
        self.assertEqual(client.calls[0], ("select", "rides", "id"))
        self.assertEqual(client.calls[1], ("is", "rides", "ended_at", "null"))
        self.assertEqual(client.calls[2], ("eq", "rides", "user_id", "user-1"))
        self.assertEqual(client.calls[3], ("order", "rides", "started_at", True))
        self.assertEqual(client.calls[4], ("limit", "rides", 1))

    def test_update_ride_summary_writes_filtered_rides_update(self) -> None:
        client = _Client()
        uploader = SupabasePhotoUploader(
            supabase_url=None,
            supabase_key=None,
            device_id="pi-test",
            client=client,
        )

        ride_id = "33333333333333333333333333333333"
        uploader.update_ride_summary(
            ride_id,
            {
                "distance_m": 1200.5,
                "duration_s": 300,
                "photo_count": 4,
                "accessibility_score": 82,
                "accessibility_rating": "good",
                "qwen_summary": {"summary": "Green bike lane visible."},
            },
        )

        self.assertEqual(client.calls[0][0], "update")
        self.assertEqual(client.calls[0][1], "rides")
        self.assertEqual(client.calls[0][2]["accessibility_score"], 82)
        self.assertEqual(client.calls[0][2]["qwen_summary"]["summary"], "Green bike lane visible.")
        self.assertIn("summarized_at", client.calls[0][2])
        self.assertEqual(client.calls[1], ("eq", "rides", "id", ride_id))

    def test_insert_ai_summary_writes_history_table(self) -> None:
        client = _Client()
        uploader = SupabasePhotoUploader(
            supabase_url=None,
            supabase_key=None,
            device_id="pi-test",
            user_id="user-1",
            client=client,
        )

        result = uploader.insert_ai_summary(
            {
                "ride_id": "44444444444444444444444444444444",
                "model": "qwen/test",
                "summary": "Green lane, potholes visible.",
                "accessibility_score": 68,
                "potholes_detected": True,
                "pothole_count": 2,
            }
        )

        self.assertIsNotNone(result)
        self.assertEqual(client.calls[0][0], "insert")
        self.assertEqual(client.calls[0][1], "ai_summary")
        row = client.calls[0][2]
        self.assertEqual(row["device_id"], "pi-test")
        self.assertEqual(row["user_id"], "user-1")
        self.assertEqual(row["model"], "qwen/test")
        self.assertTrue(row["potholes_detected"])
        self.assertEqual(row["pothole_count"], 2)
        self.assertIn("created_at", row)


if __name__ == "__main__":
    unittest.main()

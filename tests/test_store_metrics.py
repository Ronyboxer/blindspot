from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
import tempfile
import unittest

from device.blindspot_device.gps import GpsFix
from device.blindspot_device.store import LocalStore


class LocalStoreMetricsTests(unittest.TestCase):
    def test_ensure_ride_mirrors_external_ride_id_locally(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            store = LocalStore(Path(tmp) / "blindspot.sqlite3")
            try:
                ride_id = "external-ride-1"
                store.ensure_ride(
                    ride_id,
                    "pi-test",
                    started_at="2026-06-13T12:00:00+00:00",
                )
                store.ensure_ride(
                    ride_id,
                    "pi-test",
                    started_at="2026-06-13T12:01:00+00:00",
                )

                metrics = store.ride_metrics(ride_id)

                self.assertEqual(metrics.ride_id, ride_id)
                self.assertEqual(metrics.started_at, "2026-06-13T12:00:00+00:00")
                self.assertEqual(metrics.photo_count, 0)
            finally:
                store.close()

    def test_ride_metrics_include_distance_duration_and_photo_count(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            store = LocalStore(Path(tmp) / "blindspot.sqlite3")
            try:
                ride_id = store.start_ride("pi-test")
                store._conn.execute(
                    "update rides set started_at = ?, ended_at = ? where id = ?",
                    (
                        "2026-06-13T12:00:00+00:00",
                        "2026-06-13T12:05:00+00:00",
                        ride_id,
                    ),
                )
                store._conn.commit()

                store.add_ride_point(
                    ride_id,
                    GpsFix(
                        lat=0.0,
                        lng=0.0,
                        speed_mps=4.0,
                        recorded_at="2026-06-13T12:00:00+00:00",
                    ),
                )
                store.add_ride_point(
                    ride_id,
                    GpsFix(
                        lat=0.0,
                        lng=0.001,
                        speed_mps=4.0,
                        recorded_at="2026-06-13T12:01:00+00:00",
                    ),
                )
                photo_path = Path(tmp) / "capture.jpg"
                photo_path.write_bytes(b"jpeg")
                store.add_event(
                    ride_id=ride_id,
                    event_type="manual_flag",
                    fix=GpsFix(
                        lat=0.0,
                        lng=0.001,
                        speed_mps=0.0,
                        recorded_at=datetime.now(timezone.utc).isoformat(),
                    ),
                    photo_path=photo_path,
                )

                metrics = store.ride_metrics(ride_id)

                self.assertEqual(metrics.duration_s, 300)
                self.assertAlmostEqual(metrics.distance_m, 111.2, delta=1.0)
                self.assertEqual(metrics.point_count, 2)
                self.assertEqual(metrics.event_count, 1)
                self.assertEqual(metrics.photo_count, 1)
                self.assertEqual(store.ride_photo_paths(ride_id), [photo_path])
            finally:
                store.close()


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import time

from .camera import Camera
from .config import DeviceConfig
from .feedback import Feedback
from .gps import GpsReader
from .imu import CrashDetector, IMUSample, ImpactDetector
from .ride_summary import QwenRideSummarizer, RideSummaryResult
from .store import LocalStore
from .sync import SyncClient
from .supabase_sync import SupabasePhotoUploader


class DeviceApp:
    def __init__(
        self,
        config: DeviceConfig,
        camera: Camera,
        gps: GpsReader,
        feedback: Feedback,
        store: LocalStore,
        sync: SyncClient,
        photo_uploader: SupabasePhotoUploader | None = None,
        ride_summarizer: QwenRideSummarizer | None = None,
    ) -> None:
        self.config = config
        self.camera = camera
        self.gps = gps
        self.feedback = feedback
        self.store = store
        self.sync = sync
        self.photo_uploader = photo_uploader
        self.ride_summarizer = ride_summarizer
        self.impact_detector = ImpactDetector(config.impact_threshold_g)
        self.crash_detector = CrashDetector(
            threshold_g=config.crash_threshold_g,
            orientation_delta_deg=config.crash_orientation_delta_deg,
            stillness_g=config.crash_stillness_g,
            stillness_seconds=config.crash_stillness_seconds,
        )

    def run_mock_ride(self, duration_s: float = 10.0) -> str:
        ride_id = self.store.start_ride(self.config.device_id)
        if self.photo_uploader:
            self.photo_uploader.start_ride(ride_id)
        start = time.monotonic()
        tick = 0
        while time.monotonic() - start < duration_s:
            fix = self.gps.read_fix()
            self.store.add_ride_point(ride_id, fix)

            sample = self._mock_imu_sample(time.monotonic() - start, tick)
            if self.impact_detector.observe(sample):
                self.capture_event(ride_id, "impact", sample)
            if self.crash_detector.observe(sample):
                self.feedback.crash_countdown()
                self.capture_event(ride_id, "crash", sample)

            tick += 1
            time.sleep(1)

        self.finish_ride(ride_id)
        if self.sync.sync_pending(self.store):
            self.feedback.synced()
        return ride_id

    def finish_ride(self, ride_id: str) -> RideSummaryResult | None:
        self.store.end_ride(ride_id)
        metrics = self.store.ride_metrics(ride_id)
        if self.photo_uploader:
            self.photo_uploader.end_ride(ride_id, ended_at=metrics.ended_at)

        if not self.ride_summarizer or not self.ride_summarizer.enabled:
            return None
        try:
            result = self.ride_summarizer.summarize(metrics, self.store.ride_photo_paths(ride_id))
        except Exception as exc:
            print(f"[ride-summary] skipped={exc}")
            return None
        if result and self.photo_uploader:
            self.photo_uploader.update_ride_summary(ride_id, result.to_supabase_update())
            self.photo_uploader.insert_ai_summary(
                result.to_ai_summary_insert(
                    user_id=self.config.user_id,
                    device_id=self.config.device_id,
                )
            )
        return result

    def capture_event(self, ride_id: str, event_type: str, sample: IMUSample | None = None) -> None:
        fix = self.gps.read_fix()
        photo_path = self.camera.capture(self.config.photos_dir, prefix=event_type)
        self.store.add_event(
            ride_id=ride_id,
            event_type=event_type,
            fix=fix,
            imu_magnitude=sample.magnitude_g if sample else None,
            photo_path=photo_path,
        )
        if self.photo_uploader:
            self.photo_uploader.upload_photo(
                photo_path=photo_path,
                ride_id=ride_id,
                event_type=event_type,
                lat=fix.lat,
                lng=fix.lng,
            )
        self.feedback.flag_saved()

    @staticmethod
    def _mock_imu_sample(elapsed_s: float, tick: int) -> IMUSample:
        if tick == 3:
            return IMUSample(elapsed_s, 0.2, 0.3, 2.7, 2, 3)
        return IMUSample(elapsed_s, 0.01, 0.02, 1.0, 2, 3)

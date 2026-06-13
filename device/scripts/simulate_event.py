from __future__ import annotations

import argparse

from device.blindspot_device.app import DeviceApp
from device.blindspot_device.camera import MockCamera
from device.blindspot_device.config import DeviceConfig
from device.blindspot_device.feedback import ConsoleFeedback
from device.blindspot_device.gps import MockGpsReader
from device.blindspot_device.ride_summary import QwenRideSummarizer
from device.blindspot_device.store import LocalStore
from device.blindspot_device.sync import SyncClient
from device.blindspot_device.supabase_sync import SupabasePhotoUploader


def main() -> None:
    parser = argparse.ArgumentParser(description="Create one simulated Blind Spot capture event")
    parser.add_argument(
        "event_type",
        nargs="?",
        default="manual_flag",
        choices=["manual_flag", "impact", "hard_brake", "swerve", "crash"],
    )
    args = parser.parse_args()

    config = DeviceConfig()
    config.ensure_dirs()
    store = LocalStore(config.db_path)
    ride_id = store.start_ride(config.device_id)
    uploader = SupabasePhotoUploader.from_config(config)
    uploader.start_ride(ride_id)
    app = DeviceApp(
        config=config,
        camera=MockCamera(),
        gps=MockGpsReader(),
        feedback=ConsoleFeedback(),
        store=store,
        sync=SyncClient(config.backend_url, config.api_key),
        photo_uploader=uploader,
        ride_summarizer=QwenRideSummarizer.from_config(config),
    )
    app.capture_event(ride_id, args.event_type)
    app.finish_ride(ride_id)
    print(f"created {args.event_type} on ride_id={ride_id}")


if __name__ == "__main__":
    main()

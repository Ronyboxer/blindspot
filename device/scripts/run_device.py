from __future__ import annotations

import argparse

from device.blindspot_device.app import DeviceApp
from device.blindspot_device.camera import MockCamera, PiCamera
from device.blindspot_device.config import DeviceConfig
from device.blindspot_device.feedback import ConsoleFeedback
from device.blindspot_device.gps import MockGpsReader, SerialGpsReader
from device.blindspot_device.ride_summary import QwenRideSummarizer
from device.blindspot_device.store import LocalStore
from device.blindspot_device.sync import SyncClient
from device.blindspot_device.supabase_sync import SupabasePhotoUploader


def main() -> None:
    parser = argparse.ArgumentParser(description="Run Blind Spot Raspberry Pi capture loop")
    parser.add_argument("--mock", action="store_true", help="Use mock camera/GPS for development demos")
    parser.add_argument("--duration", type=float, default=10.0, help="Mock ride duration in seconds")
    args = parser.parse_args()

    config = DeviceConfig()
    config.ensure_dirs()

    camera = MockCamera() if args.mock else PiCamera()
    gps = MockGpsReader() if args.mock else SerialGpsReader()
    app = DeviceApp(
        config=config,
        camera=camera,
        gps=gps,
        feedback=ConsoleFeedback(),
        store=LocalStore(config.db_path),
        sync=SyncClient(config.backend_url, config.api_key),
        photo_uploader=SupabasePhotoUploader.from_config(config),
        ride_summarizer=QwenRideSummarizer.from_config(config),
    )
    ride_id = app.run_mock_ride(args.duration)
    print(f"ride_id={ride_id}")


if __name__ == "__main__":
    main()

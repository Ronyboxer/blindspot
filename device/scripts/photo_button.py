from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path

from device.blindspot_device.button import (
    ButtonGesture,
    ButtonTiming,
    ConsoleButton,
    GpioButton,
    run_gesture_loop,
)
from device.blindspot_device.camera import MockCamera, PiCamera
from device.blindspot_device.config import DeviceConfig
from device.blindspot_device.gps import GpsFix
from device.blindspot_device.led_strip import ConsoleLedStrip, NeoPixelStrip
from device.blindspot_device.phone_bridge import PhoneRideClient
from device.blindspot_device.ride_summary import QwenRideSummarizer
from device.blindspot_device.store import LocalStore, RideMetrics
from device.blindspot_device.supabase_sync import SupabasePhotoUploader


def main() -> None:
    parser = argparse.ArgumentParser(description="Take a photo when the handlebar button is pressed")
    parser.add_argument("--mock", action="store_true", help="Use keyboard input and mock JPEG output")
    parser.add_argument("--button-gpio", type=int, default=17, help="BCM GPIO pin for button input")
    parser.add_argument("--led-pin", default="D18", help="board pin name for NeoPixel data, e.g. D18")
    parser.add_argument("--led-count", type=int, default=8, help="number of addressable LEDs")
    parser.add_argument("--once", action="store_true", help="capture one photo and exit")
    parser.add_argument("--double-window", type=float, default=0.45, help="seconds to wait for double click")
    parser.add_argument("--long-press", type=float, default=1.1, help="seconds held to count as long press")
    args = parser.parse_args()

    config = DeviceConfig()
    config.ensure_dirs()

    camera = MockCamera() if args.mock else PiCamera()
    button = ConsoleButton() if args.mock else GpioButton(args.button_gpio)
    leds = ConsoleLedStrip() if args.mock else NeoPixelStrip(args.led_count, args.led_pin)
    timing = ButtonTiming(args.double_window, args.long_press)
    store = LocalStore(config.db_path)
    uploader = SupabasePhotoUploader.from_config(config)
    summarizer = QwenRideSummarizer.from_config(config)
    phone = PhoneRideClient.from_config(config)

    active_ride_id: str | None = None
    active_ride_source: str | None = None

    def display_state() -> None:
        leds.show_state(
            ride_active=active_ride_id is not None,
            video_recording=camera.is_recording_video,
        )

    def handle_gesture(gesture: ButtonGesture) -> None:
        if gesture == ButtonGesture.SINGLE:
            capture_photo()
        elif gesture == ButtonGesture.DOUBLE:
            toggle_video()
        elif gesture == ButtonGesture.LONG:
            toggle_ride()

    def toggle_ride() -> None:
        nonlocal active_ride_id, active_ride_source
        try:
            leds.capturing()
            if active_ride_id is None:
                active_ride_id, active_ride_source = start_ride()
            else:
                ending_ride_id = active_ride_id
                stop_ride(ending_ride_id, active_ride_source)
                active_ride_id = None
                active_ride_source = None
                print(f"gesture=long ride_stopped={ending_ride_id}")
            leds.saved()
        except Exception as exc:
            print(f"gesture=long ride_error={exc}")
            leds.error()
        finally:
            display_state()

    def capture_photo() -> None:
        nonlocal active_ride_id, active_ride_source
        try:
            leds.capturing()
            photo_path: Path = camera.capture(config.photos_dir, prefix="manual_flag")
            print(f"gesture=single photo_saved={photo_path}")
            if active_ride_id is None:
                active_ride_id = uploader.current_ride_id()
                if active_ride_id:
                    active_ride_source = "supabase"
                    store.ensure_ride(active_ride_id, config.device_id)
                    print(f"gesture=single ride_attached={active_ride_id}")
                else:
                    print("gesture=single ride_attached=none")
            if active_ride_id:
                store.add_event(
                    ride_id=active_ride_id,
                    event_type="manual_flag",
                    fix=unknown_fix(),
                    photo_path=photo_path,
                )
            upload = uploader.upload_photo(
                photo_path=photo_path,
                ride_id=active_ride_id,
                event_type="manual_flag",
            )
            if upload:
                print(
                    "gesture=single "
                    f"supabase_uploaded=bucket:{upload.bucket} path:{upload.storage_path}"
                )
            else:
                print("gesture=single supabase_skipped=not_configured")
            leds.saved()
        except Exception as exc:
            print(f"gesture=single photo_error={exc}")
            leds.error()
        finally:
            display_state()

    def summarize_ride(ride_id: str, metrics: RideMetrics) -> None:
        if not summarizer.enabled:
            print("ride_summary_skipped=no_hackclub_ai_key")
            return
        try:
            result = summarizer.summarize(metrics, store.ride_photo_paths(ride_id))
        except Exception as exc:
            print(f"ride_summary_error={exc}")
            return
        if result is None:
            print("ride_summary_skipped=no_result")
            return
        if uploader.enabled:
            uploader.update_ride_summary(ride_id, result.to_supabase_update())
            ai_summary_row = uploader.insert_ai_summary(
                result.to_ai_summary_insert(
                    user_id=config.user_id,
                    device_id=config.device_id,
                )
            )
            print(
                "ride_summary_uploaded="
                f"score:{result.score} rating:{result.rating} distance_m:{metrics.distance_m:.1f}"
                f" ai_summary={'written' if ai_summary_row else 'skipped_schema_missing'}"
            )
        else:
            print(
                "ride_summary_complete="
                f"score:{result.score} rating:{result.rating} supabase_skipped=not_configured"
            )

    def start_ride() -> tuple[str, str]:
        if phone.enabled:
            result = phone.start_ride()
            if result is None or not result.ok or not result.ride_id:
                raise RuntimeError("iPhone ride start did not return ok=true with ride_id")
            store.ensure_ride(result.ride_id, config.device_id)
            print(f"gesture=long iphone_start_sent={result.ride_id}")
            return result.ride_id, "iphone"

        ride_id = uploader.current_ride_id()
        if ride_id:
            store.ensure_ride(ride_id, config.device_id)
            print(f"gesture=long ride_attached={ride_id}")
            return ride_id, "supabase"

        ride_id = store.start_ride(config.device_id)
        uploader.start_ride(ride_id)
        print(f"gesture=long ride_started={ride_id}")
        return ride_id, "local"

    def stop_ride(ride_id: str, source: str | None) -> None:
        if source == "iphone":
            result = phone.stop_ride(ride_id)
            if result is None or not result.ok:
                raise RuntimeError("iPhone ride stop did not return ok=true")
            print(f"gesture=long iphone_stop_sent={ride_id}")
            summarize_local_ride(ride_id)
            return
        if source == "supabase":
            uploader.end_ride(ride_id)
            summarize_local_ride(ride_id)
            return
        summarize_local_ride(ride_id, update_remote_end=True)

    def summarize_local_ride(ride_id: str, update_remote_end: bool = False) -> None:
        store.end_ride(ride_id)
        metrics = store.ride_metrics(ride_id)
        if update_remote_end:
            uploader.end_ride(ride_id, ended_at=metrics.ended_at)
        summarize_ride(ride_id, metrics)

    def unknown_fix() -> GpsFix:
        return GpsFix(
            lat=0.0,
            lng=0.0,
            speed_mps=0.0,
            recorded_at=datetime.now(timezone.utc).isoformat(),
        )

    def toggle_video() -> None:
        try:
            leds.capturing()
            if camera.is_recording_video:
                video_path = camera.stop_video()
                print(f"gesture=double video_stopped={video_path}")
            else:
                video_path = camera.start_video(config.videos_dir, prefix="button_video")
                print(f"gesture=double video_started={video_path}")
            leds.saved()
        except Exception as exc:
            print(f"gesture=double video_error={exc}")
            leds.error()
        finally:
            display_state()

    display_state()
    print("Waiting for button gesture. single=photo, double=video start/stop, long=ride start/stop.")
    try:
        if args.once:
            gesture = button.wait_for_gesture(timing)
            handle_gesture(gesture)
        else:
            run_gesture_loop(button, handle_gesture, timing)
    except KeyboardInterrupt:
        print("Stopping photo button loop")
    finally:
        if active_ride_id is not None and active_ride_source == "local":
            try:
                stop_ride(active_ride_id, active_ride_source)
                print(f"ride_stopped_on_exit={active_ride_id}")
            except Exception as exc:
                print(f"ride_stop_on_exit_error={exc}")
        elif active_ride_id is not None:
            print(f"ride_{active_ride_source}_left_open={active_ride_id}")
        if camera.is_recording_video:
            video_path = camera.stop_video()
            print(f"video_stopped_on_exit={video_path}")
        leds.off()
        button.close()
        store.close()


if __name__ == "__main__":
    main()

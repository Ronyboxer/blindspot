from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path
import threading

from device.blindspot_device.button import (
    ButtonGesture,
    ButtonTiming,
    ConsoleButton,
    GpioButton,
    run_gesture_loop,
)
from device.blindspot_device.ble_bridge import BleRidePeripheral
from device.blindspot_device.camera import MockCamera, PiCamera
from device.blindspot_device.config import DeviceConfig
from device.blindspot_device.gps import GpsFix
from device.blindspot_device.led_strip import ConsoleLedStrip, NeoPixelStrip, NullLedStrip
from device.blindspot_device.phone_bridge import PhoneRideClient
from device.blindspot_device.ride_summary import QwenRideSummarizer
from device.blindspot_device.serial_bridge import SerialJsonBridge, serial_message_to_gesture
from device.blindspot_device.summary_service import RideSummaryServiceClient
from device.blindspot_device.store import LocalStore, RideMetrics
from device.blindspot_device.supabase_sync import SupabasePhotoUploader


def main() -> None:
    parser = argparse.ArgumentParser(description="Take a photo when the handlebar button is pressed")
    parser.add_argument("--mock", action="store_true", help="Use keyboard input and mock JPEG output")
    parser.add_argument("--button-gpio", type=int, default=17, help="BCM GPIO pin for button input")
    parser.add_argument("--led-pin", default="D18", help="board pin name for NeoPixel data, e.g. D18")
    parser.add_argument("--led-count", type=int, default=8, help="number of addressable LEDs")
    parser.add_argument("--no-led", action="store_true", help="Disable hardware LED strip output")
    parser.add_argument("--once", action="store_true", help="capture one photo and exit")
    parser.add_argument("--ble", action="store_true", help="Enable BLE ride-control bridge")
    parser.add_argument("--no-ble", action="store_true", help="Disable BLE even if env enables it")
    parser.add_argument("--serial", action="store_true", help="Enable USB serial JSON-lines bridge")
    parser.add_argument("--no-serial", action="store_true", help="Disable USB serial bridge")
    parser.add_argument("--serial-port", help="USB serial bridge port, e.g. /dev/ttyGS0")
    parser.add_argument("--serial-baud", type=int, help="USB serial bridge baud rate")
    parser.add_argument(
        "--serial-commands",
        action="store_true",
        help="Allow COM messages to trigger single/double/long gestures",
    )
    parser.add_argument("--double-window", type=float, default=0.45, help="seconds to wait for double click")
    parser.add_argument("--long-press", type=float, default=1.1, help="seconds held to count as long press")
    args = parser.parse_args()

    config = DeviceConfig()
    config.ensure_dirs()

    camera = MockCamera() if args.mock else PiCamera()
    button = ConsoleButton() if args.mock else GpioButton(args.button_gpio)
    led_enabled = config.led_enabled and not args.no_led
    if args.mock:
        leds = ConsoleLedStrip()
    elif led_enabled:
        leds = NeoPixelStrip(args.led_count, args.led_pin)
    else:
        leds = NullLedStrip()
    timing = ButtonTiming(args.double_window, args.long_press)
    store = LocalStore(config.db_path)
    uploader = SupabasePhotoUploader.from_config(config)
    summary_service = RideSummaryServiceClient.from_config(config)
    summarizer = QwenRideSummarizer.from_config(config)
    phone = PhoneRideClient.from_config(config)
    ble_enabled = (config.ble_enabled or args.ble) and not args.no_ble
    ble = BleRidePeripheral.from_config(config, enabled=ble_enabled)
    serial_enabled = (config.serial_enabled or args.serial) and not args.no_serial
    serial_bridge = SerialJsonBridge.from_config(
        config,
        enabled=serial_enabled,
        port=args.serial_port,
        baud_rate=args.serial_baud,
    )
    gesture_lock = threading.Lock()

    active_ride_id: str | None = None
    active_ride_source: str | None = None

    def emit(event_type: str, **fields: object) -> None:
        serial_bridge.emit(event_type, **fields)

    def display_state() -> None:
        leds.show_state(
            ride_active=active_ride_id is not None,
            video_recording=camera.is_recording_video,
        )
        emit(
            "state",
            ride_active=active_ride_id is not None,
            video_recording=camera.is_recording_video,
            ride_id=active_ride_id,
        )

    def dispatch_gesture(gesture: ButtonGesture, source: str = "button") -> None:
        with gesture_lock:
            emit("gesture", gesture=gesture.value, gesture_source=source)
            handle_gesture(gesture)

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
                emit("ride_started", ride_id=active_ride_id, ride_source=active_ride_source)
            else:
                ending_ride_id = active_ride_id
                stop_ride(ending_ride_id, active_ride_source)
                active_ride_id = None
                active_ride_source = None
                print(f"gesture=long ride_stopped={ending_ride_id}")
                emit("ride_stopped", ride_id=ending_ride_id)
            leds.saved()
        except Exception as exc:
            print(f"gesture=long ride_error={exc}")
            emit("ride_error", error=str(exc))
            leds.error()
        finally:
            display_state()

    def capture_photo() -> None:
        nonlocal active_ride_id, active_ride_source
        try:
            leds.capturing()
            photo_path: Path = camera.capture(config.photos_dir, prefix="manual_flag")
            print(f"gesture=single photo_saved={photo_path}")
            emit("photo_saved", path=str(photo_path), capture_event_type="manual_flag")
            if active_ride_id is None:
                active_ride_id = uploader.current_ride_id()
                if active_ride_id:
                    active_ride_source = "supabase"
                    store.ensure_ride(active_ride_id, config.device_id)
                    print(f"gesture=single ride_attached={active_ride_id}")
                    emit("ride_attached", ride_id=active_ride_id, ride_source=active_ride_source)
                else:
                    print("gesture=single ride_attached=none")
                    emit("ride_attached", ride_id=None)
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
                emit(
                    "photo_uploaded",
                    ride_id=active_ride_id,
                    bucket=upload.bucket,
                    storage_path=upload.storage_path,
                    capture_event_type="manual_flag",
                )
            else:
                print("gesture=single supabase_skipped=not_configured")
                emit(
                    "photo_upload_skipped",
                    ride_id=active_ride_id,
                    capture_event_type="manual_flag",
                )
            leds.saved()
        except Exception as exc:
            print(f"gesture=single photo_error={exc}")
            emit("photo_error", error=str(exc))
            leds.error()
        finally:
            display_state()

    def summarize_ride(ride_id: str, metrics: RideMetrics) -> None:
        photo_paths = store.ride_photo_paths(ride_id)
        if summary_service.enabled:
            try:
                result = summary_service.summarize(metrics, photo_paths)
                print("ride_summary_service=configured")
            except Exception as exc:
                print(f"ride_summary_service_error={exc}")
                emit("ride_summary_error", ride_id=ride_id, error=str(exc))
                return
        elif summarizer.enabled:
            try:
                result = summarizer.summarize(metrics, photo_paths)
                print("ride_summary_service=direct")
            except Exception as exc:
                print(f"ride_summary_error={exc}")
                emit("ride_summary_error", ride_id=ride_id, error=str(exc))
                return
        else:
            print("ride_summary_skipped=no_hackclub_ai_key")
            emit("ride_summary_skipped", ride_id=ride_id, reason="no_ai_key")
            return
        if result is None:
            print("ride_summary_skipped=no_result")
            emit("ride_summary_skipped", ride_id=ride_id, reason="no_result")
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
            emit(
                "ride_summary_uploaded",
                ride_id=ride_id,
                score=result.score,
                rating=result.rating,
                ai_summary_written=bool(ai_summary_row),
            )
        else:
            print(
                "ride_summary_complete="
                f"score:{result.score} rating:{result.rating} supabase_skipped=not_configured"
            )
            emit("ride_summary_complete", ride_id=ride_id, score=result.score, rating=result.rating)

    def start_ride() -> tuple[str, str]:
        if ble.enabled:
            emit("ble_ride_start_requested")
            result = ble.start_ride()
            if result is None or not result.ok or not result.ride_id:
                raise RuntimeError("iPhone BLE ride start did not return ok=true with ride_id")
            store.ensure_ride(result.ride_id, config.device_id)
            print(f"gesture=long ble_start_sent={result.ride_id}")
            return result.ride_id, "ble"

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
        if source == "ble":
            emit("ble_ride_stop_requested", ride_id=ride_id)
            result = ble.stop_ride(ride_id)
            if result is None or not result.ok:
                raise RuntimeError("iPhone BLE ride stop did not return ok=true")
            print(f"gesture=long ble_stop_sent={ride_id}")
            summarize_local_ride(ride_id)
            return
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
                emit("video_stopped", path=str(video_path) if video_path else None)
            else:
                video_path = camera.start_video(config.videos_dir, prefix="button_video")
                print(f"gesture=double video_started={video_path}")
                emit("video_started", path=str(video_path))
            leds.saved()
        except Exception as exc:
            print(f"gesture=double video_error={exc}")
            emit("video_error", error=str(exc))
            leds.error()
        finally:
            display_state()

    def handle_serial_message(message: dict[str, object]) -> None:
        gesture = serial_message_to_gesture(message)
        if gesture is None:
            emit("serial_command_ignored", message_type=message.get("type"))
            return
        dispatch_gesture(gesture, source="serial")

    serial_status = serial_bridge.start()
    if serial_status.enabled:
        if serial_status.active:
            print(f"serial_bridge=ready port:{serial_status.port}")
            if config.serial_commands_enabled or args.serial_commands:
                serial_bridge.start_reader(handle_serial_message)
                emit("serial_commands_ready")
        else:
            print(f"serial_bridge_error={serial_status.error}")
    display_state()
    if ble.enabled:
        try:
            ble.start()
            print(
                "ble_advertising="
                f"name:{ble.name} service:{ble.service_uuid} "
                f"command:{ble.command_uuid} response:{ble.response_uuid}"
            )
            emit(
                "ble_advertising",
                name=ble.name,
                service_uuid=ble.service_uuid,
                command_uuid=ble.command_uuid,
                response_uuid=ble.response_uuid,
            )
        except Exception as exc:
            print(f"ble_start_error={exc}")
            emit("ble_start_error", error=str(exc))
            leds.error()
            display_state()
    print("Waiting for button gesture. single=photo, double=video start/stop, long=ride start/stop.")
    emit("button_loop_ready", ble_enabled=ble.enabled)
    try:
        if args.once:
            gesture = button.wait_for_gesture(timing)
            dispatch_gesture(gesture)
        else:
            run_gesture_loop(button, dispatch_gesture, timing)
    except KeyboardInterrupt:
        print("Stopping photo button loop")
        emit("button_loop_stopping")
    finally:
        if active_ride_id is not None and active_ride_source == "local":
            try:
                stop_ride(active_ride_id, active_ride_source)
                print(f"ride_stopped_on_exit={active_ride_id}")
                emit("ride_stopped_on_exit", ride_id=active_ride_id)
            except Exception as exc:
                print(f"ride_stop_on_exit_error={exc}")
                emit("ride_stop_on_exit_error", ride_id=active_ride_id, error=str(exc))
        elif active_ride_id is not None:
            print(f"ride_{active_ride_source}_left_open={active_ride_id}")
            emit("ride_left_open", ride_id=active_ride_id, ride_source=active_ride_source)
        if camera.is_recording_video:
            video_path = camera.stop_video()
            print(f"video_stopped_on_exit={video_path}")
            emit("video_stopped_on_exit", path=str(video_path) if video_path else None)
        ble.close()
        serial_bridge.close()
        leds.off()
        button.close()
        store.close()


if __name__ == "__main__":
    main()

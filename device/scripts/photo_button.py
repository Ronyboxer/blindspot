from __future__ import annotations

import argparse
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
from device.blindspot_device.led_strip import ConsoleLedStrip, NeoPixelStrip


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

    ride_active = False

    def display_state() -> None:
        leds.show_state(ride_active=ride_active, video_recording=camera.is_recording_video)

    def handle_gesture(gesture: ButtonGesture) -> None:
        nonlocal ride_active
        if gesture == ButtonGesture.SINGLE:
            capture_photo()
        elif gesture == ButtonGesture.DOUBLE:
            toggle_video()
        elif gesture == ButtonGesture.LONG:
            ride_active = not ride_active
            print(f"ride_state={'started' if ride_active else 'stopped'}")
            leds.saved()
            display_state()

    def capture_photo() -> None:
        try:
            leds.capturing()
            photo_path: Path = camera.capture(config.photos_dir, prefix="manual_flag")
            print(f"gesture=single photo_saved={photo_path}")
            leds.saved()
        except Exception as exc:
            print(f"gesture=single photo_error={exc}")
            leds.error()
        finally:
            display_state()

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
        if camera.is_recording_video:
            video_path = camera.stop_video()
            print(f"video_stopped_on_exit={video_path}")
        leds.off()
        button.close()


if __name__ == "__main__":
    main()

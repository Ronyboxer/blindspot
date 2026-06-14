from __future__ import annotations

import unittest

from device.blindspot_device.button import ButtonGesture
from device.blindspot_device.serial_bridge import (
    build_serial_message,
    decode_serial_json,
    encode_serial_json,
    serial_message_to_gesture,
)


class SerialBridgeTests(unittest.TestCase):
    def test_serial_message_round_trip(self) -> None:
        payload = build_serial_message("photo_saved", "pi-test", path="/tmp/photo.jpg")

        decoded = decode_serial_json(encode_serial_json(payload))

        self.assertEqual(decoded["type"], "photo_saved")
        self.assertEqual(decoded["device_id"], "pi-test")
        self.assertEqual(decoded["source"], "raspberry_pi")
        self.assertEqual(decoded["path"], "/tmp/photo.jpg")
        self.assertIn("occurred_at", decoded)

    def test_serial_message_must_be_json_object(self) -> None:
        with self.assertRaises(RuntimeError):
            decode_serial_json('["bad"]')

    def test_gesture_command(self) -> None:
        gesture = serial_message_to_gesture({"type": "gesture", "gesture": "long"})

        self.assertEqual(gesture, ButtonGesture.LONG)

    def test_direct_gesture_type(self) -> None:
        gesture = serial_message_to_gesture({"type": "double"})

        self.assertEqual(gesture, ButtonGesture.DOUBLE)

    def test_ignored_serial_message(self) -> None:
        gesture = serial_message_to_gesture({"type": "status"})

        self.assertIsNone(gesture)


if __name__ == "__main__":
    unittest.main()

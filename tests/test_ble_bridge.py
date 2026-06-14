from __future__ import annotations

import json
import unittest

from device.blindspot_device.ble_bridge import (
    BleRidePeripheral,
    build_ble_ride_command,
    decode_ble_json,
    encode_ble_json,
)


class BleBridgeTests(unittest.TestCase):
    def test_disabled_bridge_does_not_start_or_signal(self) -> None:
        bridge = BleRidePeripheral(enabled=False, name="BlindSpot-Test", device_id="pi-test")

        self.assertFalse(bridge.enabled)
        self.assertIsNone(bridge.start_ride())
        self.assertIsNone(bridge.stop_ride("ride-1"))

    def test_build_start_command_contains_only_ride_control_data(self) -> None:
        payload = build_ble_ride_command("ride_start", "pi-test")

        self.assertEqual(payload["type"], "ride_start")
        self.assertEqual(payload["device_id"], "pi-test")
        self.assertEqual(payload["source"], "raspberry_pi")
        self.assertIn("request_id", payload)
        self.assertIn("occurred_at", payload)
        self.assertNotIn("lat", payload)
        self.assertNotIn("lng", payload)
        self.assertNotIn("gps", payload)

    def test_build_stop_command_includes_ride_id(self) -> None:
        payload = build_ble_ride_command("ride_stop", "pi-test", ride_id="ride-1")

        self.assertEqual(payload["type"], "ride_stop")
        self.assertEqual(payload["ride_id"], "ride-1")

    def test_ble_json_round_trip(self) -> None:
        payload = {"ok": True, "request_id": "abc", "ride_id": "ride-1", "status": "recording"}

        encoded = encode_ble_json(payload)
        decoded = decode_ble_json(encoded)

        self.assertIsInstance(encoded, bytearray)
        self.assertEqual(decoded, payload)

    def test_ble_response_must_be_json_object(self) -> None:
        with self.assertRaises(RuntimeError):
            decode_ble_json(json.dumps(["not", "object"]).encode("utf-8"))


if __name__ == "__main__":
    unittest.main()

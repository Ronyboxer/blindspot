from __future__ import annotations

from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import threading
import unittest

from device.blindspot_device.phone_bridge import PhoneRideClient


class _RideHandler(BaseHTTPRequestHandler):
    calls: list[tuple[str, dict, str | None]] = []

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length).decode("utf-8"))
        auth = self.headers.get("Authorization")
        self.calls.append((self.path, payload, auth))

        if self.path == "/blindspot/ride/start":
            response = {"ok": True, "ride_id": "ride-from-phone", "status": "recording"}
        elif self.path == "/blindspot/ride/stop":
            response = {"ok": True, "ride_id": payload.get("ride_id"), "status": "stopped"}
        else:
            response = {"ok": False}

        data = json.dumps(response).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args) -> None:
        return


class PhoneRideClientTests(unittest.TestCase):
    def setUp(self) -> None:
        _RideHandler.calls = []
        self.server = HTTPServer(("127.0.0.1", 0), _RideHandler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        host, port = self.server.server_address
        self.base_url = f"http://{host}:{port}"

    def tearDown(self) -> None:
        self.server.shutdown()
        self.thread.join(timeout=2)
        self.server.server_close()

    def test_start_and_stop_ride_post_to_phone(self) -> None:
        client = PhoneRideClient(
            base_url=self.base_url,
            device_id="pi-test",
            token="test-token",
            timeout_s=2,
        )

        started = client.start_ride()
        stopped = client.stop_ride(started.ride_id if started else None)

        self.assertIsNotNone(started)
        self.assertEqual(started.ride_id, "ride-from-phone")
        self.assertIsNotNone(stopped)
        self.assertEqual(stopped.status, "stopped")
        self.assertEqual(_RideHandler.calls[0][0], "/blindspot/ride/start")
        self.assertEqual(_RideHandler.calls[0][1]["type"], "ride_start")
        self.assertEqual(_RideHandler.calls[0][1]["device_id"], "pi-test")
        self.assertEqual(_RideHandler.calls[0][2], "Bearer test-token")
        self.assertEqual(_RideHandler.calls[1][0], "/blindspot/ride/stop")
        self.assertEqual(_RideHandler.calls[1][1]["ride_id"], "ride-from-phone")

    def test_disabled_when_base_url_missing(self) -> None:
        client = PhoneRideClient(base_url=None, device_id="pi-test")

        self.assertFalse(client.enabled)
        self.assertIsNone(client.start_ride())
        self.assertIsNone(client.stop_ride("ride-1"))


if __name__ == "__main__":
    unittest.main()

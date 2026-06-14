from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import asyncio
import json
import threading
from typing import Any
from uuid import uuid4

from .config import DeviceConfig
from .phone_bridge import PhoneRideResult


DEFAULT_BLE_SERVICE_UUID = "9b7d0001-6c9e-4f2a-9f1a-4b5f0b5d0001"
DEFAULT_BLE_COMMAND_UUID = "9b7d0002-6c9e-4f2a-9f1a-4b5f0b5d0002"
DEFAULT_BLE_RESPONSE_UUID = "9b7d0003-6c9e-4f2a-9f1a-4b5f0b5d0003"


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass
class _PendingRideRequest:
    event: threading.Event
    response: dict[str, Any] | None = None


class BleRidePeripheral:
    """BLE peripheral that lets the iPhone app receive Pi ride commands.

    The Pi advertises a GATT service. The iPhone app connects as the BLE central,
    subscribes to the command characteristic, and writes JSON responses back.
    """

    def __init__(
        self,
        enabled: bool,
        name: str,
        device_id: str,
        service_uuid: str = DEFAULT_BLE_SERVICE_UUID,
        command_uuid: str = DEFAULT_BLE_COMMAND_UUID,
        response_uuid: str = DEFAULT_BLE_RESPONSE_UUID,
        response_timeout_s: float = 10.0,
    ) -> None:
        self._enabled = enabled
        self.name = name
        self.device_id = device_id
        self.service_uuid = service_uuid
        self.command_uuid = command_uuid
        self.response_uuid = response_uuid
        self.response_timeout_s = response_timeout_s

        self._loop: asyncio.AbstractEventLoop | None = None
        self._server: Any | None = None
        self._thread: threading.Thread | None = None
        self._ready = threading.Event()
        self._started = threading.Event()
        self._lock = threading.Lock()
        self._pending: dict[str, _PendingRideRequest] = {}
        self._last_command: dict[str, Any] = {"type": "idle", "device_id": self.device_id}
        self._startup_error: BaseException | None = None

    @classmethod
    def from_config(
        cls, config: DeviceConfig, enabled: bool | None = None
    ) -> BleRidePeripheral:
        return cls(
            enabled=config.ble_enabled if enabled is None else enabled,
            name=config.ble_name,
            device_id=config.device_id,
            service_uuid=config.ble_service_uuid,
            command_uuid=config.ble_command_uuid,
            response_uuid=config.ble_response_uuid,
            response_timeout_s=config.ble_response_timeout_s,
        )

    @property
    def enabled(self) -> bool:
        return self._enabled

    @property
    def started(self) -> bool:
        return self._started.is_set()

    def start(self) -> None:
        if not self.enabled or self.started:
            return
        if self._thread and self._thread.is_alive():
            return

        self._ready.clear()
        self._started.clear()
        self._startup_error = None
        self._thread = threading.Thread(target=self._run_thread, name="blindspot-ble", daemon=True)
        self._thread.start()
        if not self._ready.wait(timeout=8):
            raise RuntimeError("BLE server did not become ready")
        if self._startup_error:
            raise RuntimeError(f"BLE server failed to start: {self._startup_error}") from self._startup_error

    def close(self) -> None:
        if self._loop and self._loop.is_running():
            future = asyncio.run_coroutine_threadsafe(self._stop_async(), self._loop)
            try:
                future.result(timeout=5)
            finally:
                self._loop.call_soon_threadsafe(self._loop.stop)
        if self._thread:
            self._thread.join(timeout=5)
        self._started.clear()

    def start_ride(self) -> PhoneRideResult | None:
        if not self.enabled:
            return None
        payload = build_ble_ride_command("ride_start", self.device_id)
        return self._request_ride_action(payload)

    def stop_ride(self, ride_id: str | None) -> PhoneRideResult | None:
        if not self.enabled:
            return None
        payload = build_ble_ride_command("ride_stop", self.device_id, ride_id=ride_id)
        return self._request_ride_action(payload)

    def _request_ride_action(self, payload: dict[str, Any]) -> PhoneRideResult:
        self.start()
        request_id = str(payload["request_id"])
        pending = _PendingRideRequest(event=threading.Event())
        with self._lock:
            self._pending[request_id] = pending

        try:
            self._publish_command(payload)
            if not pending.event.wait(timeout=self.response_timeout_s):
                raise RuntimeError(
                    "Timed out waiting for iPhone BLE ride response. "
                    "Open the app, connect to the Blind Spot BLE service, and retry."
                )
        finally:
            with self._lock:
                self._pending.pop(request_id, None)

        response = pending.response or {}
        ok = bool(response.get("ok", True))
        ride_id = response.get("ride_id")
        status = response.get("status")
        return PhoneRideResult(
            ok=ok,
            ride_id=str(ride_id) if ride_id else None,
            status=str(status) if status else None,
            raw=response,
        )

    def _publish_command(self, payload: dict[str, Any]) -> None:
        if not self._loop or not self._server:
            raise RuntimeError("BLE server is not running")
        future = asyncio.run_coroutine_threadsafe(self._publish_command_async(payload), self._loop)
        future.result(timeout=5)

    async def _publish_command_async(self, payload: dict[str, Any]) -> None:
        self._last_command = payload
        characteristic = self._server.get_characteristic(self.command_uuid)
        if characteristic is None:
            raise RuntimeError("BLE command characteristic is missing")
        characteristic.value = encode_ble_json(payload)
        self._server.update_value(self.service_uuid, self.command_uuid)

    def _run_thread(self) -> None:
        loop = asyncio.new_event_loop()
        self._loop = loop
        asyncio.set_event_loop(loop)
        try:
            loop.run_until_complete(self._start_async(loop))
            self._ready.set()
            loop.run_forever()
        except BaseException as exc:
            self._startup_error = exc
            self._ready.set()
        finally:
            try:
                if self._server:
                    loop.run_until_complete(self._stop_async())
            finally:
                loop.close()

    async def _start_async(self, loop: asyncio.AbstractEventLoop) -> None:
        try:
            from bless import (  # type: ignore
                BlessGATTCharacteristic,
                BlessServer,
                GATTAttributePermissions,
                GATTCharacteristicProperties,
            )
        except ImportError as exc:
            raise RuntimeError(
                "Install the BLE dependency on the Pi with: python -m pip install '.[pi]'"
            ) from exc

        def read_request(characteristic: BlessGATTCharacteristic, **_: Any) -> bytearray:
            return characteristic.value

        def write_request(characteristic: BlessGATTCharacteristic, value: Any, **_: Any) -> None:
            characteristic.value = bytearray(value)
            self._handle_response_bytes(bytes(characteristic.value))

        server = BlessServer(name=self.name, loop=loop)
        server.read_request_func = read_request
        server.write_request_func = write_request

        await server.add_new_service(self.service_uuid)
        command_flags = (
            GATTCharacteristicProperties.read | GATTCharacteristicProperties.notify
        )
        response_flags = GATTCharacteristicProperties.read | GATTCharacteristicProperties.write
        read_perm = GATTAttributePermissions.readable
        read_write_perm = GATTAttributePermissions.readable | GATTAttributePermissions.writeable

        await server.add_new_characteristic(
            self.service_uuid,
            self.command_uuid,
            command_flags,
            encode_ble_json(self._last_command),
            read_perm,
        )
        await server.add_new_characteristic(
            self.service_uuid,
            self.response_uuid,
            response_flags,
            encode_ble_json({"type": "ready", "ok": True}),
            read_write_perm,
        )
        self._server = server
        await server.start()
        self._started.set()

    async def _stop_async(self) -> None:
        if self._server:
            await self._server.stop()
            self._server = None

    def _handle_response_bytes(self, raw: bytes) -> None:
        response = decode_ble_json(raw)
        request_id = response.get("request_id")
        with self._lock:
            pending = self._pending.get(str(request_id)) if request_id else None
            if pending is None and len(self._pending) == 1:
                pending = next(iter(self._pending.values()))
            if pending is None:
                return
            pending.response = response
            pending.event.set()


def build_ble_ride_command(
    command_type: str,
    device_id: str,
    ride_id: str | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "type": command_type,
        "request_id": uuid4().hex,
        "device_id": device_id,
        "source": "raspberry_pi",
        "occurred_at": _utc_now(),
    }
    if ride_id:
        payload["ride_id"] = ride_id
    return payload


def encode_ble_json(payload: dict[str, Any]) -> bytearray:
    return bytearray(json.dumps(payload, separators=(",", ":")).encode("utf-8"))


def decode_ble_json(raw: bytes | bytearray) -> dict[str, Any]:
    try:
        decoded = bytes(raw).decode("utf-8")
        parsed = json.loads(decoded)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"BLE response must be a JSON object: {exc}") from exc
    if not isinstance(parsed, dict):
        raise RuntimeError("BLE response must be a JSON object")
    return parsed

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
import threading
from typing import Any, Callable

from .button import ButtonGesture
from .config import DeviceConfig


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass(frozen=True)
class SerialBridgeStatus:
    enabled: bool
    active: bool
    port: str
    error: str | None = None


class SerialJsonBridge:
    """JSON-lines bridge over a USB serial gadget.

    The Pi writes status/events to /dev/ttyGS0. A laptop listener can write
    JSON commands back on the same serial link, mainly for demo testing.
    """

    def __init__(
        self,
        enabled: bool,
        port: str,
        baud_rate: int,
        device_id: str,
        read_timeout_s: float = 0.2,
        write_timeout_s: float = 1.0,
    ) -> None:
        self.enabled = enabled
        self.port = port
        self.baud_rate = baud_rate
        self.device_id = device_id
        self.read_timeout_s = read_timeout_s
        self.write_timeout_s = write_timeout_s
        self._serial: Any | None = None
        self._write_lock = threading.Lock()
        self._stop = threading.Event()
        self._reader_thread: threading.Thread | None = None
        self._last_error: str | None = None

    @classmethod
    def from_config(
        cls,
        config: DeviceConfig,
        enabled: bool | None = None,
        port: str | None = None,
        baud_rate: int | None = None,
    ) -> SerialJsonBridge:
        return cls(
            enabled=config.serial_enabled if enabled is None else enabled,
            port=port or config.serial_port,
            baud_rate=baud_rate or config.serial_baud,
            device_id=config.device_id,
        )

    @property
    def active(self) -> bool:
        return self._serial is not None

    @property
    def status(self) -> SerialBridgeStatus:
        return SerialBridgeStatus(
            enabled=self.enabled,
            active=self.active,
            port=self.port,
            error=self._last_error,
        )

    def start(self) -> SerialBridgeStatus:
        if not self.enabled:
            return self.status
        if self._serial is not None:
            return self.status

        try:
            import serial  # type: ignore

            self._serial = serial.Serial(
                self.port,
                self.baud_rate,
                timeout=self.read_timeout_s,
                write_timeout=self.write_timeout_s,
            )
            self._last_error = None
            self.emit("serial_ready", baud=self.baud_rate)
        except Exception as exc:
            self._serial = None
            self._last_error = str(exc)
        return self.status

    def emit(self, event_type: str, **fields: Any) -> bool:
        if self._serial is None:
            return False
        payload = build_serial_message(event_type, self.device_id, **fields)
        return self.send(payload)

    def send(self, payload: dict[str, Any]) -> bool:
        if self._serial is None:
            return False
        try:
            with self._write_lock:
                self._serial.write(encode_serial_json(payload))
                self._serial.flush()
            return True
        except Exception as exc:
            self._last_error = str(exc)
            return False

    def read_message(self) -> dict[str, Any] | None:
        if self._serial is None:
            return None
        raw = self._serial.readline()
        if not raw:
            return None
        return decode_serial_json(raw)

    def start_reader(self, on_message: Callable[[dict[str, Any]], None]) -> None:
        if self._serial is None or self._reader_thread is not None:
            return
        self._stop.clear()
        self._reader_thread = threading.Thread(
            target=self._reader_loop,
            args=(on_message,),
            name="blindspot-serial",
            daemon=True,
        )
        self._reader_thread.start()

    def close(self) -> None:
        self._stop.set()
        if self._reader_thread:
            self._reader_thread.join(timeout=2)
            self._reader_thread = None
        if self._serial is not None:
            try:
                self._serial.close()
            finally:
                self._serial = None

    def _reader_loop(self, on_message: Callable[[dict[str, Any]], None]) -> None:
        while not self._stop.is_set():
            try:
                message = self.read_message()
            except Exception as exc:
                self._last_error = str(exc)
                continue
            if message is None:
                continue
            on_message(message)


def build_serial_message(event_type: str, device_id: str, **fields: Any) -> dict[str, Any]:
    payload = {
        "type": event_type,
        "source": "raspberry_pi",
        "device_id": device_id,
        "occurred_at": _utc_now(),
    }
    payload.update(fields)
    return payload


def encode_serial_json(payload: dict[str, Any]) -> bytes:
    return (json.dumps(payload, separators=(",", ":")) + "\n").encode("utf-8")


def decode_serial_json(raw: bytes | bytearray | str) -> dict[str, Any]:
    if isinstance(raw, str):
        text = raw.strip()
    else:
        text = bytes(raw).decode("utf-8").strip()
    parsed = json.loads(text)
    if not isinstance(parsed, dict):
        raise RuntimeError("serial message must be a JSON object")
    return parsed


def serial_message_to_gesture(message: dict[str, Any]) -> ButtonGesture | None:
    message_type = str(message.get("type") or "").strip().lower()
    raw_gesture = str(message.get("gesture") or "").strip().lower()
    if message_type in {"single", "double", "long"}:
        raw_gesture = message_type
    if message_type not in {"gesture", "button_gesture", "single", "double", "long"}:
        return None
    try:
        return ButtonGesture(raw_gesture)
    except ValueError:
        return None

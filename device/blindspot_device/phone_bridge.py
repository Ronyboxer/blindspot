from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
from typing import Any
from urllib import error, request

from .config import DeviceConfig


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass(frozen=True)
class PhoneRideResult:
    ok: bool
    ride_id: str | None
    status: str | None
    raw: dict[str, Any]


class PhoneRideClient:
    def __init__(
        self,
        base_url: str | None,
        device_id: str,
        token: str | None = None,
        timeout_s: float = 2.0,
    ) -> None:
        self.base_url = base_url.rstrip("/") if base_url else None
        self.device_id = device_id
        self.token = token
        self.timeout_s = timeout_s

    @classmethod
    def from_config(cls, config: DeviceConfig) -> PhoneRideClient:
        return cls(
            base_url=config.phone_base_url,
            device_id=config.device_id,
            token=config.phone_token,
            timeout_s=config.phone_timeout_s,
        )

    @property
    def enabled(self) -> bool:
        return bool(self.base_url)

    def start_ride(self) -> PhoneRideResult | None:
        if not self.enabled:
            return None
        return self._post(
            "/blindspot/ride/start",
            {
                "type": "ride_start",
                "device_id": self.device_id,
                "source": "raspberry_pi",
                "occurred_at": _utc_now(),
            },
        )

    def stop_ride(self, ride_id: str | None) -> PhoneRideResult | None:
        if not self.enabled:
            return None
        payload: dict[str, Any] = {
            "type": "ride_stop",
            "device_id": self.device_id,
            "source": "raspberry_pi",
            "occurred_at": _utc_now(),
        }
        if ride_id:
            payload["ride_id"] = ride_id
        return self._post("/blindspot/ride/stop", payload)

    def _post(self, path: str, payload: dict[str, Any]) -> PhoneRideResult:
        if not self.base_url:
            raise RuntimeError("Phone ride client is not configured")

        data = json.dumps(payload).encode("utf-8")
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-BlindSpot-Device-ID": self.device_id,
        }
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"

        req = request.Request(
            f"{self.base_url}{path}",
            data=data,
            headers=headers,
            method="POST",
        )
        try:
            with request.urlopen(req, timeout=self.timeout_s) as response:
                body = response.read().decode("utf-8")
        except error.URLError as exc:
            raise RuntimeError(f"iPhone ride signal failed: {exc}") from exc

        parsed = json.loads(body) if body.strip() else {}
        if not isinstance(parsed, dict):
            raise RuntimeError("iPhone ride signal response must be a JSON object")
        ok = bool(parsed.get("ok", True))
        ride_id = parsed.get("ride_id")
        status = parsed.get("status")
        return PhoneRideResult(
            ok=ok,
            ride_id=str(ride_id) if ride_id else None,
            status=str(status) if status else None,
            raw=parsed,
        )

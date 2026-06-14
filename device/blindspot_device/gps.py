from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import itertools
import time


@dataclass(frozen=True)
class GpsFix:
    lat: float
    lng: float
    speed_mps: float
    recorded_at: str
    elevation_m: float | None = None


class GpsReader:
    def read_fix(self) -> GpsFix:
        raise NotImplementedError


class MockGpsReader(GpsReader):
    def __init__(self, start_lat: float = 37.7749, start_lng: float = -122.4194) -> None:
        self._start_lat = start_lat
        self._start_lng = start_lng
        self._steps = itertools.count()

    def read_fix(self) -> GpsFix:
        step = next(self._steps)
        return GpsFix(
            lat=self._start_lat + step * 0.00001,
            lng=self._start_lng + step * 0.00001,
            speed_mps=4.2,
            recorded_at=datetime.now(timezone.utc).isoformat(),
            elevation_m=None,
        )


class SerialGpsReader(GpsReader):
    def __init__(self, port: str = "/dev/serial0", baudrate: int = 9600) -> None:
        try:
            import serial
        except ImportError as exc:
            raise RuntimeError("Install pyserial to read UART GPS") from exc

        self._serial = serial.Serial(port, baudrate=baudrate, timeout=1)
        self._last_fix: GpsFix | None = None

    def read_fix(self) -> GpsFix:
        while True:
            line = self._serial.readline().decode("ascii", errors="ignore").strip()
            fix = parse_gprmc(line)
            if fix:
                self._last_fix = fix
                return fix
            if self._last_fix:
                return self._last_fix
            time.sleep(0.1)


def parse_gprmc(sentence: str) -> GpsFix | None:
    if not sentence.startswith(("$GPRMC", "$GNRMC")):
        return None

    fields = sentence.split(",")
    if len(fields) < 8 or fields[2] != "A":
        return None

    lat = _nmea_coord_to_decimal(fields[3], fields[4])
    lng = _nmea_coord_to_decimal(fields[5], fields[6])
    if lat is None or lng is None:
        return None

    knots = float(fields[7] or 0)
    return GpsFix(
        lat=lat,
        lng=lng,
        speed_mps=knots * 0.514444,
        recorded_at=datetime.now(timezone.utc).isoformat(),
    )


def _nmea_coord_to_decimal(value: str, hemisphere: str) -> float | None:
    if not value or not hemisphere:
        return None
    degree_digits = 2 if hemisphere in {"N", "S"} else 3
    degrees = float(value[:degree_digits])
    minutes = float(value[degree_digits:])
    decimal = degrees + minutes / 60
    if hemisphere in {"S", "W"}:
        decimal = -decimal
    return decimal

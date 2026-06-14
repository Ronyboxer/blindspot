from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import sys
import time
from typing import Any


def main() -> None:
    parser = argparse.ArgumentParser(description="Blind Spot USB COM demo monitor/control")
    parser.add_argument("--port", required=True, help="Windows COM port, for example COM5")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--gesture", choices=["single", "double", "long"], help="send one gesture")
    parser.add_argument("--listen", action="store_true", help="print incoming JSON lines")
    parser.add_argument("--seconds", type=float, default=0.0, help="listen duration; 0 means forever")
    args = parser.parse_args()

    try:
        import serial  # type: ignore
    except ImportError as exc:
        raise SystemExit("Install pyserial first: python -m pip install pyserial") from exc

    try:
        with serial.Serial(
            args.port,
            args.baud,
            timeout=0.2,
            write_timeout=1.0,
            dsrdtr=False,
            rtscts=False,
        ) as ser:
            if args.gesture:
                payload = {
                    "type": "gesture",
                    "gesture": args.gesture,
                    "source": "demo_com",
                    "occurred_at": datetime.now(timezone.utc).isoformat(),
                }
                ser.write((json.dumps(payload, separators=(",", ":")) + "\n").encode("utf-8"))
                ser.flush()
                print(f"sent gesture={args.gesture}")
            if args.listen or not args.gesture:
                listen(ser, args.seconds)
    except Exception as exc:
        raise SystemExit(f"COM failed: {exc}") from exc


def listen(ser: Any, seconds: float) -> None:
    deadline = time.monotonic() + seconds if seconds > 0 else None
    while deadline is None or time.monotonic() < deadline:
        raw = ser.readline()
        if not raw:
            continue
        text = raw.decode("utf-8", errors="replace").strip()
        if not text:
            continue
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            print(text)
            continue
        print(json.dumps(parsed, indent=2, sort_keys=True))
        sys.stdout.flush()


if __name__ == "__main__":
    main()

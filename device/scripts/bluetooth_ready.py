from __future__ import annotations

import argparse
import subprocess


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare Raspberry Pi Bluetooth for Blind Spot BLE")
    parser.add_argument(
        "--name",
        default="BlindSpot-Pi",
        help="Bluetooth adapter alias shown during scans",
    )
    parser.add_argument(
        "--discoverable",
        action="store_true",
        help="Also make the adapter discoverable for quick phone-side debugging",
    )
    args = parser.parse_args()

    commands = [
        "power on",
        f"system-alias {args.name}",
        "agent NoInputNoOutput",
        "default-agent",
        "pairable on",
    ]
    if args.discoverable:
        commands.append("discoverable on")
    commands.append("show")

    proc = subprocess.run(
        ["bluetoothctl"],
        input="\n".join(commands) + "\n",
        text=True,
        capture_output=True,
        check=False,
    )
    print(proc.stdout)
    if proc.stderr:
        print(proc.stderr)
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)


if __name__ == "__main__":
    main()

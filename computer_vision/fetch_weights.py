"""Download UFLD TuSimple weights from Google Drive directly."""

# /// script
# requires-python = ">=3.11"
# dependencies = ["requests"]
# ///

import os
import sys
import requests

FILE_ID = "1WCYyur5ZaWczH15ecmeDG1vuZMjDQ1XJ"
OUTPUT = os.path.join("models", "tusimple_18.pth")


def download_from_gdrive(file_id: str, dest: str) -> None:
    os.makedirs(os.path.dirname(dest), exist_ok=True)

    # Try the confirm=t trick which bypasses the virus scan warning
    url = f"https://drive.google.com/uc?export=download&id={file_id}&confirm=t"
    print(f"Downloading from Google Drive (id={file_id})...")

    session = requests.Session()
    resp = session.get(url, stream=True, timeout=60)
    ct = resp.headers.get("Content-Type", "unknown")
    print(f"  Status: {resp.status_code}, Content-Type: {ct}")

    if resp.status_code != 200:
        print(f"  FAILED: HTTP {resp.status_code}")
        sys.exit(1)

    total = 0
    with open(dest, "wb") as f:
        for chunk in resp.iter_content(32768):
            f.write(chunk)
            total += len(chunk)

    size_mb = os.path.getsize(dest) / 1e6
    print(f"  Downloaded {size_mb:.1f} MB to {dest}")

    # Check if we got an HTML error page instead of a model file
    if os.path.getsize(dest) < 1_000_000:
        print("  WARNING: File seems too small, checking contents...")
        with open(dest, "r", errors="replace") as f:
            head = f.read(500)
        print(f"  Content: {head[:200]}")
        os.remove(dest)
        print("  Removed invalid file.")
        sys.exit(1)

    print(f"  OK! {size_mb:.1f} MB")


if __name__ == "__main__":
    download_from_gdrive(FILE_ID, OUTPUT)
    print(f"\nSaved to: {OUTPUT}")

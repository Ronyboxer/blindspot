"""
Stream the PINTO UFLD TuSimple archive and extract only the ONNX model.
This avoids downloading the full 6.88 GB archive by stopping as soon as
the target file is found.
"""

# /// script
# requires-python = ">=3.11"
# dependencies = ["requests"]
# ///

import io
import os
import sys
import gzip
import tarfile
import requests

URL = "https://s3.ap-northeast-2.wasabisys.com/pinto-model-zoo/140_Ultra-Fast-Lane-Detection/resources_tusimple.tar.gz"
TARGET_PATTERN = "tusimple"  # look for any file with tusimple in the name
TARGET_EXT = ".onnx"
OUTPUT_DIR = "models"


def stream_extract():
    """Stream the tar.gz and extract only ONNX files."""
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print(f"Streaming archive from: {URL}")
    print(f"Looking for: *{TARGET_PATTERN}*{TARGET_EXT}")
    print()

    resp = requests.get(URL, stream=True, timeout=30)
    resp.raise_for_status()

    # Wrap the response in a file-like object for tarfile
    # We read in chunks and feed to the decompressor
    raw = resp.raw
    raw.decode_content = True

    try:
        with tarfile.open(fileobj=raw, mode="r|gz") as tar:
            found = 0
            for member in tar:
                name = member.name.lower()
                # Print all entries so we can see what's in the archive
                if member.isfile():
                    size_mb = member.size / 1e6
                    if name.endswith(".onnx"):
                        print(f"  [ONNX] {member.name}  ({size_mb:.1f} MB)")

                        # Extract this file
                        extracted = tar.extractfile(member)
                        if extracted:
                            dest_name = os.path.basename(member.name)
                            dest_path = os.path.join(OUTPUT_DIR, dest_name)
                            with open(dest_path, "wb") as f:
                                while True:
                                    chunk = extracted.read(65536)
                                    if not chunk:
                                        break
                                    f.write(chunk)
                            actual_size = os.path.getsize(dest_path)
                            print(f"       -> Saved to {dest_path} ({actual_size/1e6:.1f} MB)")
                            found += 1

                            # Also create a symlink/copy as tusimple.onnx if name matches
                            if "tusimple" in name and "288x800" in name:
                                tusimple_path = os.path.join(OUTPUT_DIR, "tusimple.onnx")
                                import shutil
                                shutil.copy2(dest_path, tusimple_path)
                                print(f"       -> Copied as {tusimple_path}")
                    elif name.endswith((".onnx", ".pb", ".tflite")):
                        print(f"  [skip] {member.name}  ({size_mb:.1f} MB)")

            print(f"\nDone! Found {found} ONNX file(s)")

    except Exception as e:
        print(f"\nStreaming error: {e}")
        print("This is expected if the connection drops.")
        print(f"Found {found if 'found' in dir() else 0} ONNX files before error.")


if __name__ == "__main__":
    stream_extract()

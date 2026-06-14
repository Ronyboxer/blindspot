from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
import time
from uuid import uuid4


PLACEHOLDER_JPEG = bytes.fromhex(
    "ffd8ffe000104a46494600010100000100010000ffdb004300"
    "0302020302020303030304030304050805050404050a07070608"
    "0c0a0c0c0b0a0b0b0d0e12100d0e110e0b0b10161011131415"
    "15150c0f171816141812141514ffc0000b080001000101011100"
    "ffc40014000100000000000000000000000000000000000000ff"
    "da0008010100003f00d2cf20ffd9"
)


class Camera:
    def capture(self, photos_dir: Path, prefix: str = "capture") -> Path:
        raise NotImplementedError

    @property
    def is_recording_video(self) -> bool:
        return False

    def start_video(self, videos_dir: Path, prefix: str = "video") -> Path:
        raise NotImplementedError

    def stop_video(self) -> Path | None:
        return None


class MockCamera(Camera):
    """Creates a tiny valid JPEG so the rest of the pipeline can run anywhere."""

    def __init__(self) -> None:
        self._video_path: Path | None = None

    def capture(self, photos_dir: Path, prefix: str = "capture") -> Path:
        photos_dir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        path = photos_dir / f"{prefix}-{stamp}-{uuid4().hex[:8]}.jpg"
        path.write_bytes(PLACEHOLDER_JPEG)
        return path

    @property
    def is_recording_video(self) -> bool:
        return self._video_path is not None

    def start_video(self, videos_dir: Path, prefix: str = "video") -> Path:
        if self._video_path is not None:
            return self._video_path
        videos_dir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        self._video_path = videos_dir / f"{prefix}-{stamp}-{uuid4().hex[:8]}.mockvideo"
        self._video_path.write_text("mock video recording started\n", encoding="utf-8")
        return self._video_path

    def stop_video(self) -> Path | None:
        if self._video_path is None:
            return None
        self._video_path.write_text("mock video recording stopped\n", encoding="utf-8")
        path = self._video_path
        self._video_path = None
        return path


class PiCamera(Camera):
    def __init__(self) -> None:
        try:
            from picamera2 import Picamera2
        except ImportError as exc:
            raise RuntimeError("Install picamera2 on the Raspberry Pi to use PiCamera") from exc

        self._camera = self._open_camera(Picamera2)
        self._camera.configure(self._camera.create_still_configuration())
        self._camera.start()
        self._video_path: Path | None = None
        self._video_encoder = None

    def _open_camera(self, picamera_cls: type) -> object:
        last_error: Exception | None = None
        for _ in range(12):
            try:
                return picamera_cls()
            except (IndexError, RuntimeError) as exc:
                last_error = exc
                time.sleep(2)
        raise RuntimeError("Pi camera did not become available") from last_error

    def capture(self, photos_dir: Path, prefix: str = "capture") -> Path:
        if self.is_recording_video:
            raise RuntimeError("Stop video recording before taking a still photo")
        photos_dir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        path = photos_dir / f"{prefix}-{stamp}-{uuid4().hex[:8]}.jpg"
        self._camera.capture_file(str(path))
        return path

    @property
    def is_recording_video(self) -> bool:
        return self._video_path is not None

    def start_video(self, videos_dir: Path, prefix: str = "video") -> Path:
        if self._video_path is not None:
            return self._video_path
        try:
            from picamera2.encoders import H264Encoder
        except ImportError as exc:
            raise RuntimeError("Install picamera2 video encoder support to record video") from exc

        videos_dir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        path = videos_dir / f"{prefix}-{stamp}-{uuid4().hex[:8]}.h264"
        self._camera.stop()
        self._camera.configure(self._camera.create_video_configuration())
        self._video_encoder = H264Encoder(bitrate=8_000_000)
        self._camera.start_recording(self._video_encoder, str(path))
        self._video_path = path
        return path

    def stop_video(self) -> Path | None:
        if self._video_path is None:
            return None
        path = self._video_path
        self._camera.stop_recording()
        self._video_path = None
        self._video_encoder = None
        self._camera.configure(self._camera.create_still_configuration())
        self._camera.start()
        return path

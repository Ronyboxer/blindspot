from dataclasses import dataclass, field
from pathlib import Path
import os


def _env_path(name: str, default: str) -> Path:
    return Path(os.getenv(name, default))


def _load_env_file() -> None:
    env_file = Path(os.getenv("BLINDSPOT_ENV_FILE", ".env"))
    if not env_file.exists():
        return
    for raw_line in env_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip("'\"")
        if key and key not in os.environ:
            os.environ[key] = value


def _env_first(*names: str) -> str | None:
    for name in names:
        value = os.getenv(name)
        if value:
            return value
    return None


_load_env_file()


@dataclass(frozen=True)
class DeviceConfig:
    data_dir: Path = field(default_factory=lambda: _env_path("BLINDSPOT_DATA_DIR", "data/device"))
    db_path: Path = field(
        default_factory=lambda: _env_path("BLINDSPOT_DB_PATH", "data/device/blindspot.sqlite3")
    )
    photos_dir: Path = field(
        default_factory=lambda: _env_path("BLINDSPOT_PHOTOS_DIR", "data/device/photos")
    )
    videos_dir: Path = field(
        default_factory=lambda: _env_path("BLINDSPOT_VIDEOS_DIR", "data/device/videos")
    )
    backend_url: str | None = field(default_factory=lambda: os.getenv("BLINDSPOT_BACKEND_URL"))
    api_key: str | None = field(default_factory=lambda: os.getenv("BLINDSPOT_API_KEY"))
    device_id: str = field(default_factory=lambda: os.getenv("BLINDSPOT_DEVICE_ID", "dev-pi-001"))
    user_id: str | None = field(default_factory=lambda: os.getenv("BLINDSPOT_USER_ID"))
    impact_threshold_g: float = field(
        default_factory=lambda: float(os.getenv("BLINDSPOT_IMPACT_THRESHOLD_G", "2.4"))
    )
    crash_threshold_g: float = field(
        default_factory=lambda: float(os.getenv("BLINDSPOT_CRASH_THRESHOLD_G", "3.0"))
    )
    crash_orientation_delta_deg: float = field(
        default_factory=lambda: float(os.getenv("BLINDSPOT_CRASH_ORIENTATION_DELTA_DEG", "55"))
    )
    crash_stillness_g: float = field(
        default_factory=lambda: float(os.getenv("BLINDSPOT_CRASH_STILLNESS_G", "0.18"))
    )
    crash_stillness_seconds: float = field(
        default_factory=lambda: float(os.getenv("BLINDSPOT_CRASH_STILLNESS_SECONDS", "3.0"))
    )
    supabase_url: str | None = field(
        default_factory=lambda: _env_first("BLINDSPOT_SUPABASE_URL", "SUPABASE_URL")
    )
    supabase_key: str | None = field(
        default_factory=lambda: _env_first("BLINDSPOT_SUPABASE_KEY", "SUPABASE_KEY")
    )
    supabase_bucket: str = field(
        default_factory=lambda: os.getenv("BLINDSPOT_SUPABASE_BUCKET", "photos")
    )
    supabase_rides_table: str = field(
        default_factory=lambda: os.getenv("BLINDSPOT_SUPABASE_RIDES_TABLE", "rides")
    )
    supabase_photos_table: str = field(
        default_factory=lambda: os.getenv("BLINDSPOT_SUPABASE_PHOTOS_TABLE", "photos")
    )
    supabase_ai_summary_table: str = field(
        default_factory=lambda: os.getenv("BLINDSPOT_SUPABASE_AI_SUMMARY_TABLE", "ai_summary")
    )
    hackclub_ai_api_key: str | None = field(
        default_factory=lambda: _env_first(
            "BLINDSPOT_HACKCLUB_AI_API_KEY",
            "HACKCLUB_AI_API_KEY",
            "HACK_CLUB_AI_API_KEY",
        )
    )
    hackclub_ai_model: str = field(
        default_factory=lambda: os.getenv("BLINDSPOT_HACKCLUB_AI_MODEL", "qwen/qwen3.7-plus")
    )
    hackclub_ai_endpoint: str = field(
        default_factory=lambda: os.getenv(
            "BLINDSPOT_HACKCLUB_AI_ENDPOINT",
            "https://ai.hackclub.com/proxy/v1/chat/completions",
        )
    )
    hackclub_ai_timeout_s: float = field(
        default_factory=lambda: float(os.getenv("BLINDSPOT_HACKCLUB_AI_TIMEOUT_S", "60"))
    )
    hackclub_ai_max_images: int = field(
        default_factory=lambda: int(os.getenv("BLINDSPOT_HACKCLUB_AI_MAX_IMAGES", "24"))
    )
    phone_base_url: str | None = field(
        default_factory=lambda: _env_first("BLINDSPOT_PHONE_BASE_URL", "BLINDSPOT_IPHONE_BASE_URL")
    )
    phone_token: str | None = field(default_factory=lambda: os.getenv("BLINDSPOT_PHONE_TOKEN"))
    phone_timeout_s: float = field(
        default_factory=lambda: float(os.getenv("BLINDSPOT_PHONE_TIMEOUT_S", "2.0"))
    )

    def ensure_dirs(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.photos_dir.mkdir(parents=True, exist_ok=True)
        self.videos_dir.mkdir(parents=True, exist_ok=True)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)

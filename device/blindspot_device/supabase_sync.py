from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping

from .config import DeviceConfig


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass(frozen=True)
class SupabaseUploadResult:
    bucket: str
    storage_path: str
    storage_url: str
    photo_row: dict[str, Any] | None = None


class SupabasePhotoUploader:
    def __init__(
        self,
        supabase_url: str | None,
        supabase_key: str | None,
        bucket: str = "photos",
        rides_table: str = "rides",
        photos_table: str = "photos",
        automated_photos_table: str = "automated_photos",
        ai_summary_table: str = "ai_summary",
        device_id: str = "dev-pi-001",
        user_id: str | None = None,
        client: Any | None = None,
    ) -> None:
        self.bucket = bucket
        self.rides_table = rides_table
        self.photos_table = photos_table
        self.automated_photos_table = automated_photos_table
        self.ai_summary_table = ai_summary_table
        self.device_id = device_id
        self.user_id = user_id
        self._client = client

        if self._client is None and supabase_url and supabase_key:
            try:
                from supabase import create_client
            except ImportError as exc:
                raise RuntimeError(
                    "Install supabase-py on the Raspberry Pi to upload photos to Supabase"
                ) from exc
            self._client = create_client(supabase_url, supabase_key)

    @classmethod
    def from_config(cls, config: DeviceConfig) -> SupabasePhotoUploader:
        return cls(
            supabase_url=config.supabase_url,
            supabase_key=config.supabase_key,
            bucket=config.supabase_bucket,
            rides_table=config.supabase_rides_table,
            photos_table=config.supabase_photos_table,
            automated_photos_table=config.supabase_automated_photos_table,
            ai_summary_table=config.supabase_ai_summary_table,
            device_id=config.device_id,
            user_id=config.user_id,
        )

    @property
    def enabled(self) -> bool:
        return self._client is not None

    def start_ride(self, ride_id: str, started_at: str | None = None) -> None:
        if not self.enabled:
            return
        row: dict[str, Any] = {
            "id": ride_id,
            "device_id": self.device_id,
            "started_at": started_at or _utc_now(),
        }
        if self.user_id:
            row["user_id"] = self.user_id
        self._client.table(self.rides_table).upsert(row).execute()

    def current_ride_id(self) -> str | None:
        if not self.enabled:
            return None

        query = self._client.table(self.rides_table).select("id").is_("ended_at", "null")
        if self.user_id:
            query = query.eq("user_id", self.user_id)
        else:
            query = query.eq("device_id", self.device_id)
        response = query.order("started_at", desc=True).limit(1).execute()
        rows = getattr(response, "data", None)
        if not isinstance(rows, list) or not rows:
            return None
        ride_id = rows[0].get("id")
        return str(ride_id) if ride_id else None

    def end_ride(self, ride_id: str, ended_at: str | None = None) -> None:
        if not self.enabled:
            return
        self._client.table(self.rides_table).update({"ended_at": ended_at or _utc_now()}).eq(
            "id", ride_id
        ).execute()

    def update_ride_summary(self, ride_id: str, summary_row: Mapping[str, Any]) -> None:
        if not self.enabled:
            return
        row = dict(summary_row)
        row.setdefault("summarized_at", _utc_now())
        try:
            self._client.table(self.rides_table).update(row).eq("id", ride_id).execute()
        except Exception as exc:
            if not _is_schema_cache_miss(exc):
                raise
            legacy_row = {
                key: value
                for key, value in row.items()
                if key
                in {
                    "distance_m",
                    "duration_s",
                    "photo_count",
                    "accessibility_score",
                    "accessibility_rating",
                    "accessibility_summary",
                    "accessibility_labels",
                    "accessibility_observations",
                    "accessibility_map_tags",
                    "accessibility_model",
                    "qwen_summary",
                    "summarized_at",
                }
            }
            self._client.table(self.rides_table).update(legacy_row).eq("id", ride_id).execute()

    def insert_ai_summary(self, summary_row: Mapping[str, Any]) -> dict[str, Any] | None:
        if not self.enabled:
            return None
        row = dict(summary_row)
        row.setdefault("device_id", self.device_id)
        if self.user_id:
            row.setdefault("user_id", self.user_id)
        row.setdefault("created_at", _utc_now())
        try:
            response = self._client.table(self.ai_summary_table).insert(row).execute()
        except Exception as exc:
            if _is_schema_cache_miss(exc):
                return None
            raise
        inserted = getattr(response, "data", None)
        return inserted[0] if isinstance(inserted, list) and inserted else row

    def upload_photo(
        self,
        photo_path: Path,
        ride_id: str | None,
        event_type: str = "manual_flag",
        captured_at: str | None = None,
        lat: float | None = None,
        lng: float | None = None,
    ) -> SupabaseUploadResult | None:
        if not self.enabled:
            return None
        if not ride_id:
            return None
        if not photo_path.exists():
            raise FileNotFoundError(photo_path)

        captured_at = captured_at or _utc_now()
        event_type = event_type.strip() if event_type else "automated_capture"
        is_manual_photo = event_type == "manual_flag"
        if is_manual_photo:
            storage_path = f"devices/{self.device_id}/rides/{ride_id}/{photo_path.name}"
            table_name = self.photos_table
        else:
            event_path = _safe_storage_path_part(event_type)
            storage_path = (
                f"devices/{self.device_id}/rides/{ride_id}/automated/{event_path}/{photo_path.name}"
            )
            table_name = self.automated_photos_table

        with photo_path.open("rb") as file:
            self._client.storage.from_(self.bucket).upload(
                path=storage_path,
                file=file,
                file_options={
                    "content-type": "image/jpeg",
                    "cache-control": "3600",
                    "upsert": "false",
                },
            )

        storage_url = self._storage_url(storage_path)
        photo_row: dict[str, Any] = {
            "ride_id": ride_id,
            "storage_url": storage_url,
            "event_type": event_type,
            "captured_at": captured_at,
            "is_processed": False,
        }
        if is_manual_photo:
            photo_row["is_blurred"] = False
        if lat is not None:
            photo_row["lat"] = lat
        if lng is not None:
            photo_row["lng"] = lng

        response = self._client.table(table_name).insert(photo_row).execute()
        inserted = getattr(response, "data", None)
        return SupabaseUploadResult(
            bucket=self.bucket,
            storage_path=storage_path,
            storage_url=storage_url,
            photo_row=inserted[0] if isinstance(inserted, list) and inserted else photo_row,
        )

    def _storage_url(self, storage_path: str) -> str:
        try:
            return self._client.storage.from_(self.bucket).get_public_url(storage_path)
        except Exception:
            return f"storage://{self.bucket}/{storage_path}"


def _is_schema_cache_miss(exc: Exception) -> bool:
    text = str(exc)
    return "PGRST204" in text or "PGRST205" in text or "schema cache" in text


def _safe_storage_path_part(value: str) -> str:
    safe = "".join(char if char.isalnum() or char in {"-", "_"} else "-" for char in value)
    return safe.strip("-_") or "automated_capture"

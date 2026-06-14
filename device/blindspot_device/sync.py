from __future__ import annotations

import json
from urllib import request

from .store import LocalStore


class SyncClient:
    def __init__(self, backend_url: str | None, api_key: str | None = None) -> None:
        self.backend_url = backend_url.rstrip("/") if backend_url else None
        self.api_key = api_key

    def sync_pending(self, store: LocalStore) -> int:
        synced = 0
        for item in store.pending_sync_items():
            payload = json.loads(item["payload_json"])
            if self.backend_url:
                self._post(item["kind"], payload)
            else:
                print(f"[sync dry-run] {item['kind']}: {payload}")
            store.mark_synced(item["id"])
            synced += 1
        return synced

    def _post(self, kind: str, payload: dict) -> None:
        body = json.dumps({"kind": kind, "payload": payload}).encode("utf-8")
        headers = {"content-type": "application/json"}
        if self.api_key:
            headers["authorization"] = f"Bearer {self.api_key}"
        req = request.Request(f"{self.backend_url}/device/events", data=body, headers=headers)
        with request.urlopen(req, timeout=10) as response:
            if response.status >= 300:
                raise RuntimeError(f"sync failed with HTTP {response.status}")

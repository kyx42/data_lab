"""Local filesystem writer for ingestion payloads."""

from __future__ import annotations

from pathlib import Path


class LocalWriter:
    """Persist payloads on the local filesystem."""

    def write_bytes(self, data: bytes, destination: Path) -> Path:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        return destination

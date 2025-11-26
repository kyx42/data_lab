"""Utilities for ingesting data into the lakehouse raw zone."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Protocol, Sequence


class Writer(Protocol):
    """Thin protocol for objects that can persist raw payloads."""

    def write_bytes(self, data: bytes, destination: Path) -> Path:
        ...


@dataclass(slots=True)
class IngestionJob:
    """Represent a reproducible ingestion job."""

    name: str
    source: str
    output_dir: Path

    def target_path(self, filename: str) -> Path:
        """Return the path where `filename` should be stored."""
        return self.output_dir / self.name / filename


def ingest_payloads(
    job: IngestionJob,
    payloads: Sequence[bytes],
    filenames: Sequence[str],
    writer: Writer,
) -> list[Path]:
    """Persist raw payloads while keeping provenance information.

    Args:
        job: Metadata describing the ingestion run.
        payloads: Raw and unmodified payloads retrieved from the source system.
        filenames: Output filenames aligning one-to-one with `payloads`.
        writer: Object responsible for writing bytes to storage.

    Returns:
        List of paths written, ordered as inputs.

    Raises:
        ValueError: If `payloads` and `filenames` do not share the same length.
    """
    if len(payloads) != len(filenames):
        raise ValueError("payload and filename counts must match")

    output_paths: list[Path] = []

    for payload, filename in zip(payloads, filenames):
        destination = job.target_path(filename)
        destination.parent.mkdir(parents=True, exist_ok=True)
        output_paths.append(writer.write_bytes(payload, destination))

    return output_paths

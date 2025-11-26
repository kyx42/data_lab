"""Unit tests for ingestion utilities."""

from __future__ import annotations

from pathlib import Path

import pytest

from src.ingest.base_ingestor import IngestionJob, ingest_payloads


class DummyWriter:
    """In-memory writer for tests."""

    def __init__(self) -> None:
        self.storage: dict[Path, bytes] = {}

    def write_bytes(self, data: bytes, destination: Path) -> Path:
        self.storage[destination] = data
        return destination


def test_ingest_payloads_persists_files(tmp_path: Path) -> None:
    job = IngestionJob(name="sample", source="unit-test", output_dir=tmp_path)
    writer = DummyWriter()

    payloads = [b"foo", b"bar"]
    filenames = ["a.txt", "b.txt"]

    paths = ingest_payloads(job, payloads, filenames, writer)

    assert len(paths) == 2
    for filename in filenames:
        expected = tmp_path / "sample" / filename
        assert expected in writer.storage


def test_ingest_payloads_length_mismatch(tmp_path: Path) -> None:
    job = IngestionJob(name="sample", source="unit-test", output_dir=tmp_path)

    with pytest.raises(ValueError):
        ingest_payloads(job, [b"foo"], ["a.txt", "b.txt"], DummyWriter())

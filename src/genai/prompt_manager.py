"""Prompt and feedback management utilities for LLM workflows."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, MutableMapping


@dataclass(slots=True)
class PromptTemplate:
    """Represent a prompt template and metadata."""

    name: str
    text: str
    tags: list[str] = field(default_factory=list)
    metadata: MutableMapping[str, str] = field(default_factory=dict)


class PromptRegistry:
    """Store and retrieve prompt templates from disk."""

    def __init__(self, storage_path: Path) -> None:
        self.storage_path = storage_path
        self.storage_path.parent.mkdir(parents=True, exist_ok=True)

    def save(self, templates: Iterable[PromptTemplate]) -> None:
        serialized = [
            {"name": p.name, "text": p.text, "tags": p.tags, "metadata": dict(p.metadata)}
            for p in templates
        ]
        self.storage_path.write_text(json.dumps(serialized, indent=2))

    def load(self) -> list[PromptTemplate]:
        if not self.storage_path.exists():
            return []

        entries = json.loads(self.storage_path.read_text())
        return [
            PromptTemplate(
                name=entry["name"],
                text=entry["text"],
                tags=list(entry.get("tags", [])),
                metadata=dict(entry.get("metadata", {})),
            )
            for entry in entries
        ]

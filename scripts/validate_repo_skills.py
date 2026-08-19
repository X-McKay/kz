#!/usr/bin/env python3
"""Validate repository-local Codex and Claude skill copies without dependencies."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKILL_NAMES = ("kz-development", "kz-operations")
NAME_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def frontmatter(path: Path) -> dict[str, str]:
    content = path.read_text()
    if "TODO" in content:
        raise ValueError(f"{path}: unresolved TODO")
    if not content.startswith("---\n"):
        raise ValueError(f"{path}: missing frontmatter")
    try:
        raw = content.split("---\n", 2)[1]
    except IndexError as exc:
        raise ValueError(f"{path}: unterminated frontmatter") from exc
    parsed: dict[str, str] = {}
    for line in raw.splitlines():
        key, separator, value = line.partition(":")
        if not separator or not value.strip():
            raise ValueError(f"{path}: invalid frontmatter line {line!r}")
        parsed[key.strip()] = value.strip()
    if set(parsed) != {"name", "description"}:
        raise ValueError(f"{path}: frontmatter must contain only name and description")
    return parsed


def validate() -> None:
    for skill_name in SKILL_NAMES:
        codex = ROOT / ".agents" / "skills" / skill_name / "SKILL.md"
        claude = ROOT / ".claude" / "skills" / skill_name / "SKILL.md"
        if codex.read_bytes() != claude.read_bytes():
            raise ValueError(f"{skill_name}: Codex and Claude instructions differ")
        metadata = frontmatter(codex)
        if metadata["name"] != skill_name or not NAME_PATTERN.fullmatch(metadata["name"]):
            raise ValueError(f"{codex}: invalid skill name")
        if not 25 <= len(metadata["description"]) <= 1024:
            raise ValueError(f"{codex}: description must be 25-1024 characters")
        openai_yaml = codex.parent / "agents" / "openai.yaml"
        interface = openai_yaml.read_text()
        if f"${skill_name}" not in interface:
            raise ValueError(f"{openai_yaml}: default prompt must mention ${skill_name}")


def main() -> int:
    try:
        validate()
    except (OSError, ValueError) as exc:
        print(f"skill validation failed: {exc}", file=sys.stderr)
        return 1
    print(f"validated {len(SKILL_NAMES)} mirrored Codex/Claude skills")
    return 0


if __name__ == "__main__":
    sys.exit(main())

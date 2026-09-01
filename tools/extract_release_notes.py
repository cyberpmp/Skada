"""Extract one release section from CHANGELOG.md for GitHub Releases."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


SECTION_HEADING = re.compile(r"^##\s+(.+?)\s*$")
LIST_ENTRY = re.compile(r"^\s*[-*+]\s+\S", re.MULTILINE)


def _section_key(heading: str) -> str:
    """Return the version-like first token from a level-two heading."""
    token = heading.strip().split(maxsplit=1)[0].strip("[]")
    if token.lower().startswith("v") and len(token) > 1:
        token = token[1:]
    return token.lower()


def changelog_sections(text: str) -> list[tuple[str, str]]:
    """Split a changelog into ordered ``(heading, body)`` sections."""
    lines = text.splitlines()
    starts: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        match = SECTION_HEADING.match(line)
        if match:
            starts.append((index, match.group(1).strip()))

    sections: list[tuple[str, str]] = []
    for position, (start, heading) in enumerate(starts):
        end = starts[position + 1][0] if position + 1 < len(starts) else len(lines)
        body = "\n".join(lines[start + 1 : end]).strip()
        sections.append((heading, body))
    return sections


def extract_release_notes(text: str, version: str) -> tuple[str, str]:
    """Return ``(notes, source heading)`` for a release version.

    An explicit version heading is authoritative. If it is absent, the
    ``Unreleased`` section is used so tag-driven releases do not require a
    separate changelog-edit commit. Empty or prose-only sections are rejected.
    """
    normalized_version = version.removeprefix("v").lower()
    sections = changelog_sections(text)

    selected: tuple[str, str] | None = None
    for heading, body in sections:
        if _section_key(heading) == normalized_version:
            selected = heading, body
            break

    if selected is None:
        for heading, body in sections:
            if _section_key(heading) == "unreleased":
                selected = heading, body
                break

    if selected is None:
        raise ValueError(
            f"CHANGELOG.md has neither a '{version}' section nor an 'Unreleased' section"
        )

    heading, notes = selected
    if not notes or not LIST_ENTRY.search(notes):
        raise ValueError(f"CHANGELOG.md section '{heading}' has no release-note entries")
    return notes.rstrip() + "\n", heading


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="Release version, with or without a v prefix")
    parser.add_argument("--changelog", type=Path, default=Path("CHANGELOG.md"))
    parser.add_argument("--output", type=Path, default=Path("release-notes.md"))
    args = parser.parse_args()

    try:
        notes, heading = extract_release_notes(
            args.changelog.read_text(encoding="utf-8"), args.version
        )
    except (OSError, ValueError) as error:
        parser.error(str(error))

    args.output.write_text(notes, encoding="utf-8", newline="\n")
    print(f"Release notes for v{args.version.removeprefix('v')} use CHANGELOG.md section '{heading}'.")


if __name__ == "__main__":
    main()

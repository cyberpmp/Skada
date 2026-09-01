"""Tests for the release changelog extractor."""

import unittest

from tools.extract_release_notes import extract_release_notes


class ReleaseNotesTests(unittest.TestCase):
    def test_prefers_matching_version_and_stops_at_next_release(self):
        changelog = """\
# Changelog

## Unreleased

- Future work.

## 1.2.0 - 2026-09-02

### Added

- Released feature.

## 1.1.0 - 2026-09-01

- Previous feature.
"""
        notes, heading = extract_release_notes(changelog, "1.2.0")
        self.assertEqual(heading, "1.2.0 - 2026-09-02")
        self.assertIn("Released feature.", notes)
        self.assertNotIn("Future work.", notes)
        self.assertNotIn("Previous feature.", notes)

    def test_accepts_bracketed_v_version_heading(self):
        notes, heading = extract_release_notes("## [v2.0.0]\n\n- Shipped.\n", "v2.0.0")
        self.assertEqual(heading, "[v2.0.0]")
        self.assertEqual(notes, "- Shipped.\n")

    def test_falls_back_to_unreleased(self):
        changelog = "## Unreleased\n\n### Fixed\n\n- Important fix.\n"
        notes, heading = extract_release_notes(changelog, "1.3.0")
        self.assertEqual(heading, "Unreleased")
        self.assertIn("Important fix.", notes)

    def test_rejects_empty_or_prose_only_section(self):
        with self.assertRaisesRegex(ValueError, "no release-note entries"):
            extract_release_notes("## Unreleased\n\nNothing yet.\n", "1.3.0")

    def test_rejects_missing_sections(self):
        with self.assertRaisesRegex(ValueError, "neither"):
            extract_release_notes("# Changelog\n", "1.3.0")


if __name__ == "__main__":
    unittest.main()

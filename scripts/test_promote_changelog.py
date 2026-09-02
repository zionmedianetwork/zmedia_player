#!/usr/bin/env python3
"""Tests for promote_changelog.py — stdlib only, no pip install required.

Run: python3 scripts/test_promote_changelog.py

The release workflow depends on this script to close [Unreleased]. A silent
regression here would mis-shape CHANGELOG.md on a release, which is exactly the
class of drift the two-phase release split exists to prevent.
"""

import sys
import unittest
from pathlib import Path

# Runnable from anywhere: `python3 scripts/test_promote_changelog.py`.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from promote_changelog import promote  # noqa: E402

PREAMBLE = "# Changelog\n\nPreamble line.\n\n"
NOTES = "### 🚀 Features\n\n- 🚀 feat: something (@dev) (abc1234)"


class PromoteTest(unittest.TestCase):
    def test_promotes_curated_notes_and_leaves_unreleased_empty(self):
        src = PREAMBLE + "## [Unreleased]\n\n### Added\n- a thing\n\n## [0.3.0] - 2026-08-18\n\n- old\n"
        out = promote(src, "0.4.0", "2026-09-02", NOTES)
        self.assertIn("## [Unreleased]\n\n## [0.4.0] - 2026-09-02\n\n### Added\n- a thing\n", out)
        # The curated body moved; it was not duplicated or dropped.
        self.assertEqual(out.count("- a thing"), 1)
        # Older sections survive, in order, below the new one.
        self.assertLess(out.index("## [0.4.0]"), out.index("## [0.3.0]"))
        self.assertIn("- old", out)

    def test_falls_back_to_commit_notes_when_unreleased_is_empty(self):
        src = PREAMBLE + "## [Unreleased]\n\n## [0.3.0] - 2026-08-18\n\n- old\n"
        out = promote(src, "0.4.0", "2026-09-02", NOTES)
        self.assertIn("## [0.4.0] - 2026-09-02\n\n### 🚀 Features", out)

    def test_placeholder_when_there_is_nothing_at_all(self):
        src = PREAMBLE + "## [Unreleased]\n\n## [0.3.0] - 2026-08-18\n\n- old\n"
        out = promote(src, "0.4.0", "2026-09-02", "")
        self.assertIn("_No changes recorded._", out)

    def test_inserts_a_section_when_unreleased_is_missing(self):
        src = PREAMBLE + "## [0.3.0] - 2026-08-18\n\n- old\n"
        out = promote(src, "0.4.0", "2026-09-02", NOTES)
        self.assertIn("## [Unreleased]", out)
        self.assertLess(out.index("## [0.4.0]"), out.index("## [0.3.0]"))

    def test_refuses_to_add_a_duplicate_version(self):
        src = PREAMBLE + "## [0.4.0] - 2026-01-01\n\n- already released\n"
        with self.assertRaises(SystemExit):
            promote(src, "0.4.0", "2026-09-02", NOTES)

    def test_does_not_assume_a_fixed_length_preamble(self):
        # The previous implementation hard-coded `tail -n +8`, so an extra line
        # of preamble silently ate or duplicated content.
        src = "# Changelog\n\nOne.\nTwo.\nThree.\nFour.\nFive.\nSix.\n\n## [Unreleased]\n\n- kept\n"
        out = promote(src, "0.4.0", "2026-09-02", NOTES)
        self.assertIn("Six.", out)
        self.assertIn("- kept", out)
        self.assertEqual(out.count("# Changelog"), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)

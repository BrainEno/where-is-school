#!/usr/bin/env python3
"""Both directions for the font-size prose rule in `tools/subset_font.py --check` (#286).

- a KiB or byte count next to "subset" in a live document is refused;
- the same count in a line that does not mention the subset is not;
- an upstream source font's exact byte count is stable and allowed;
- the repository's live documents carry no such count.

Run with `python3 tests/font_size_prose_test.py`; no font build and no network.
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import subset_font  # noqa: E402


class FontSizeProseTest(unittest.TestCase):
    def tree(self, readme: str) -> Path:
        base = Path(self._tmp.name)
        for target in subset_font.TARGETS:
            path = base / target.source
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"x" * 1234)
        (base / "README.md").write_text(readme, encoding="utf-8")
        return base

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_count_next_to_subset_fails(self) -> None:
        root = self.tree("the shipped font is a 376 KiB subset (385,416 bytes)\n")
        problems = subset_font.stale_size_prose(root)
        self.assertEqual(len(problems), 2, problems)
        self.assertIn("README.md:1", problems[0])

    def test_count_elsewhere_passes(self) -> None:
        self.assertEqual(subset_font.stale_size_prose(self.tree("the pack is 256 KiB\n")), [])

    def test_upstream_size_is_allowed(self) -> None:
        root = self.tree("the upstream file (1,234 bytes); the subset is built from it\n")
        self.assertEqual(subset_font.stale_size_prose(root), [])

    def test_repository_passes(self) -> None:
        self.assertEqual(subset_font.stale_size_prose(ROOT), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)

#
# Copyright 2026 Artise.
#
# SPDX-License-Identifier: AGPL-3.0-only
#
"""Tests for artise_test_suites.py. Run: python3 -m unittest discover -s Artise/Scripts/tests"""
import pathlib
import sys
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS))

import artise_test_suites as picker  # noqa: E402


class SuitesTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.tests = pathlib.Path(self.folder.name)
        (self.tests / "Artise").mkdir()
        self.write("Artise/ArtiseThingsTests.swift", "@MainActor\nstruct ArtiseThingsTests {\n}\n")
        self.write("ComposerTests.swift", "final class ComposerTests: XCTestCase {\n    // Artise: the sticker button\n}\n")
        self.write("TimelineItemMenuActionProviderTests.swift", "struct TimelineItemMenuActionProviderTests {\n}\n")
        self.write("RoomDetailsTests.swift", "@Suite(.serialized)\nstruct RoomDetailsTests {\n}\nprivate struct Helper {}\n")

    def tearDown(self):
        self.folder.cleanup()

    def write(self, name, text):
        (self.tests / name).write_text(text, encoding="utf-8")

    def test_artise_suites_and_hooks_always_run(self):
        """Scenario: a branch that changes no upstream file. Expected: the Artise folder's suites and suites that mention Artise."""
        self.assertEqual(picker.suites([], self.tests), ["ArtiseThingsTests", "ComposerTests"])

    def test_a_changed_file_brings_its_suite(self):
        """Scenario: the branch changes TimelineItemMenuActionProvider.swift and a YAML file. Expected: its suite joins; the YAML adds nothing."""
        changed = ["ElementX/Sources/Screens/Timeline/View/ItemMenu/TimelineItemMenuActionProvider.swift", ".github/workflows/artise.yml"]
        self.assertEqual(picker.suites(changed, self.tests),
                         ["ArtiseThingsTests", "ComposerTests", "TimelineItemMenuActionProviderTests"])

    def test_attributes_before_a_suite_are_read(self):
        """Scenario: suites declared with @MainActor or @Suite(...) before them, and a helper type. Expected: only the suites."""
        self.assertEqual(picker.suites_in("@Suite(.serialized)\n@MainActor\nstruct ATests {}\nstruct Helper {}\nfinal class BTests {}"),
                         ["ATests", "BTests"])

    def test_the_real_tests_folder(self):
        """Scenario: this repository's tests. Expected: the Artise suites are found, and nothing upstream without a reason."""
        found = picker.suites([])
        self.assertIn("ArtiseNotesServiceTests", found)
        self.assertNotIn("TimelineItemFactoryTests", found)


if __name__ == "__main__":
    unittest.main()

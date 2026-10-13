#
# Copyright 2026 Artise.
#
# SPDX-License-Identifier: AGPL-3.0-only
#
"""Tests for import_android_strings.py. Run: python3 -m unittest discover -s Artise/Scripts/tests"""
import pathlib
import plistlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import apply_string_overrides as strings_reader  # noqa: E402
import import_android_strings as importer  # noqa: E402

ANDROID_EN = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="title">Notes</string>
    <string name="quoted">"It\\'s here"</string>
    <string name="format">Nothing found for “%1$s”.</string>
    <string name="lines">Used in:\\n%1$s</string>
    <string name="amp">Photos &amp; files</string>
    <plurals name="count">
        <item quantity="one">%1$d note</item>
        <item quantity="other">%1$d notes</item>
    </plurals>
</resources>
"""


class ImportTests(unittest.TestCase):
    def test_converts_strings_and_plurals(self):
        """Scenario: an Android values folder. Expected: the same keys and texts, %s as %@, plurals in a stringsdict."""
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "res" / "values").mkdir(parents=True)
            (root / "res" / "values" / "strings.xml").write_text(ANDROID_EN, encoding="utf-8")

            importer.main(root / "res", root / "out", "ArtiseNotes")

            strings = strings_reader.load_strings(root / "out" / "en.lproj" / "ArtiseNotes.strings")
            self.assertEqual(strings, {
                "title": "Notes",
                "quoted": "It's here",
                "format": "Nothing found for “%1$@”.",
                "lines": "Used in:\n%1$@",
                "amp": "Photos & files",
            })
            plurals = plistlib.loads((root / "out" / "en.lproj" / "ArtiseNotes.stringsdict").read_bytes())
            self.assertEqual(plurals["count"]["count"]["one"], "%d note")
            self.assertEqual(plurals["count"]["NSStringLocalizedFormatKey"], "%#@count@")

    def test_imported_notes_strings_cover_spanish(self):
        """Scenario: the notes texts imported into the app. Expected: every English text has a Spanish one."""
        resources = pathlib.Path(__file__).resolve().parents[2] / "Resources" / "Notes"
        english = strings_reader.load_strings(resources / "en.lproj" / "ArtiseNotes.strings")
        spanish = strings_reader.load_strings(resources / "es.lproj" / "ArtiseNotes.strings")
        missing = set(english) - set(spanish)
        # Android keeps one English-only text (not translatable); nothing else may be missing.
        self.assertLessEqual(len(missing), 1, missing)


if __name__ == "__main__":
    unittest.main()

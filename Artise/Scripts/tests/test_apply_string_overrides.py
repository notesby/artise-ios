#
# Copyright 2026 Artise.
#
# SPDX-License-Identifier: AGPL-3.0-only
#
"""Tests for apply_string_overrides.py. Run: python3 -m unittest discover -s Artise/Scripts/tests"""
import pathlib
import plistlib
import re
import sys
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent
REPO = SCRIPTS.parent.parent
sys.path.insert(0, str(SCRIPTS))

import apply_string_overrides as overrides  # noqa: E402

UPSTREAM = REPO / "ElementX" / "Resources" / "Localizations"
ARTISE = REPO / "Artise" / "Resources" / "StringOverrides"
PLACEHOLDER = re.compile(r"%(?:\d+\$)?[@dDuUxXfeEgGcCsSp]")


class ParserTests(unittest.TestCase):
    def test_parses_every_upstream_table(self):
        """Scenario: all of upstream's string files. Expected: each parses into the same number of entries as it has lines with a key."""
        files = sorted(UPSTREAM.glob("*.lproj/*.strings"))
        self.assertTrue(files)
        for path in files:
            text = path.read_text(encoding="utf-8")
            expected = len(re.findall(r'^\s*"(?:[^"\\]|\\.)*"\s*=', text, re.M))
            self.assertEqual(len(overrides.load_strings(path)), expected, path)

    def test_unescapes_quotes_newlines_and_unicode(self):
        """Scenario: escaped characters and comments. Expected: real characters, comments ignored."""
        text = '/* note */\n"a" = "say \\"hi\\"\\nnow";\n// line\n"b" = "\\U00E9";\n"c" = "";'
        self.assertEqual(overrides.parse_strings_text(text), {"a": 'say "hi"\nnow', "b": "é", "c": ""})

    def test_rejects_malformed_entries(self):
        """Scenario: an entry without a value. Expected: a clear error instead of a silent skip."""
        with self.assertRaises(ValueError):
            overrides.parse_strings_text('"a";')


class ApplyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.directory.name)
        self.resources = self.root / "App.app"
        self.overrides = self.root / "Overrides"

    def tearDown(self):
        self.directory.cleanup()

    def write(self, base, language, table, text):
        folder = base / f"{language}.lproj"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{table}.strings").write_text(text, encoding="utf-8")

    def read(self, language, table):
        return overrides.load_strings(self.resources / f"{language}.lproj" / f"{table}.strings")

    def test_renames_the_product_and_applies_overrides(self):
        """Scenario: en, en-US and fr tables naming Element X, with English overrides only.
        Expected: every language says Artise, en-US uses the en overrides, untouched keys stay."""
        for language in ("en", "en-US", "fr"):
            self.write(self.resources, language, "InfoPlist", '"cam" = "Element X needs the camera";\n"face" = "Face ID";')
            self.write(self.resources, language, "Localizable", '"title" = "Be in your element";')
        self.write(self.overrides, "en", "Localizable", '"title" = "Your family’s private chat";')

        self.assertEqual(overrides.apply(self.resources, self.overrides), 5)

        for language in ("en", "en-US"):
            self.assertEqual(self.read(language, "Localizable"), {"title": "Your family’s private chat"})
        self.assertEqual(self.read("fr", "Localizable"), {"title": "Be in your element"})
        self.assertEqual(self.read("fr", "InfoPlist"), {"cam": "Artise needs the camera", "face": "Face ID"})

    def test_reads_compiled_tables(self):
        """Scenario: Xcode already compiled the table to a binary plist. Expected: it is read and updated."""
        folder = self.resources / "en.lproj"
        folder.mkdir(parents=True)
        (folder / "Localizable.strings").write_bytes(plistlib.dumps({"k": "Element X"}, fmt=plistlib.FMT_BINARY))
        overrides.apply(self.resources, self.overrides)
        self.assertEqual(self.read("en", "Localizable"), {"k": "Artise"})


class ArtiseOverridesTests(unittest.TestCase):
    def test_every_override_matches_an_upstream_string(self):
        """Scenario: Artise's override files. Expected: each key still exists upstream with the same
        placeholders, so an upstream rename or a format change fails here instead of in the app."""
        files = sorted(ARTISE.glob("*.lproj/*.strings"))
        self.assertTrue(files)
        for path in files:
            table = "Localizable" if path.stem == "Wording" else path.stem
            upstream = overrides.load_strings(UPSTREAM / "en.lproj" / f"{table}.strings")
            for key, value in overrides.load_strings(path).items():
                self.assertIn(key, upstream, f"{path}: {key}")
                self.assertEqual(sorted(PLACEHOLDER.findall(value)), sorted(PLACEHOLDER.findall(upstream[key])), f"{path}: {key}")

    def test_english_and_spanish_override_the_same_keys(self):
        """Scenario: Artise writes English and Spanish by hand. Expected: both languages cover the same strings."""
        for table in ("Localizable", "InfoPlist"):
            english = set(overrides.load_strings(ARTISE / "en.lproj" / f"{table}.strings"))
            spanish = set(overrides.load_strings(ARTISE / "es.lproj" / f"{table}.strings"))
            self.assertTrue(english <= spanish, f"{table}: missing in Spanish: {english - spanish}")

    def test_wording_covers_every_language_and_is_current(self):
        """Scenario: the generated Wording.strings. Expected: en, es and pt have the same keys, and they match the
        table in wording_overrides.py (someone edited the table without running it, or the reverse)."""
        import wording_overrides
        keys = set(wording_overrides.wording_for_ios(REPO))
        for language in wording_overrides.LANGUAGES:
            self.assertEqual(set(overrides.load_strings(ARTISE / f"{language}.lproj" / "Wording.strings")), keys, language)

    def test_hand_written_overrides_win_over_wording(self):
        """Scenario: a key in both Wording.strings and Localizable.strings. Expected: Localizable's text is used."""
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root / "app/es.lproj").mkdir(parents=True)
            (root / "artise/es.lproj").mkdir(parents=True)
            (root / "app/es.lproj/Localizable.strings").write_text('"k" = "sala";', encoding="utf-8")
            (root / "artise/es.lproj/Wording.strings").write_text('"k" = "chat"; "j" = "x";', encoding="utf-8")
            (root / "artise/es.lproj/Localizable.strings").write_text('"k" = "mano";', encoding="utf-8")
            overrides.apply(root / "app", root / "artise")
            self.assertEqual(overrides.load_strings(root / "app/es.lproj/Localizable.strings"), {"k": "mano", "j": "x"})

    def test_pt_folder_covers_brazilian_phones(self):
        """Scenario: a pt-BR table and only a pt override folder. Expected: the pt texts are applied."""
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root / "app/pt-BR.lproj").mkdir(parents=True)
            (root / "artise/pt.lproj").mkdir(parents=True)
            (root / "app/pt-BR.lproj/Localizable.strings").write_text('"k" = "sala";', encoding="utf-8")
            (root / "artise/pt.lproj/Wording.strings").write_text('"k" = "conversa";', encoding="utf-8")
            overrides.apply(root / "app", root / "artise")
            self.assertEqual(overrides.load_strings(root / "app/pt-BR.lproj/Localizable.strings"), {"k": "conversa"})

    def test_no_override_names_element(self):
        """Scenario: Artise's own wording. Expected: it never mentions Element."""
        for path in ARTISE.glob("*.lproj/*.strings"):
            for key, value in overrides.load_strings(path).items():
                self.assertNotIn("Element", value, f"{path}: {key}")


if __name__ == "__main__":
    unittest.main()

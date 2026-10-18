#
# Copyright 2026 Artise.
#
# SPDX-License-Identifier: AGPL-3.0-only
#
"""Every Artise text exists in English, Spanish and Portuguese, translated. Run: python3 -m unittest discover -s Artise/Scripts/tests"""
import pathlib
import plistlib
import re
import sys
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent
REPO = SCRIPTS.parent.parent
sys.path.insert(0, str(SCRIPTS))

from apply_string_overrides import load_strings  # noqa: E402

LANGUAGES = ("en", "es", "pt")
# Artise's own tables (one folder per feature), Element's texts Artise writes by hand, and the sticker share extension.
FOLDERS = sorted(path for path in (REPO / "Artise" / "Resources").iterdir() if (path / "en.lproj").is_dir())
FOLDERS.append(REPO / "ArtiseStickerShare" / "SupportingFiles")
# Android keeps "%1$s → %2$s" (renamed, in the notes history) in English only: it has no words.
ENGLISH_ONLY = {"screen_notes_history_renamed"}


def texts(path):
    """A .strings file's texts, or a .stringsdict's plural forms flattened to one text each."""
    if path.suffix == ".stringsdict":
        plurals = plistlib.loads(path.read_bytes())
        return {key: " | ".join(str(value) for value in entry["count"].values()) for key, entry in plurals.items()}
    return load_strings(path)


def tables(folder):
    return sorted(path.name for path in (folder / "en.lproj").iterdir() if path.suffix in (".strings", ".stringsdict"))


class LanguageTests(unittest.TestCase):
    def test_every_text_has_spanish_and_portuguese(self):
        """Scenario: each Artise table in English. Expected: Spanish and Portuguese have the same keys, so nobody on a
        Spanish or Portuguese phone sees an English text."""
        self.assertTrue(FOLDERS)
        for folder in FOLDERS:
            for table in tables(folder):
                english = set(texts(folder / "en.lproj" / table)) - ENGLISH_ONLY
                for language in LANGUAGES[1:]:
                    path = folder / f"{language}.lproj" / table
                    self.assertTrue(path.exists(), path)
                    missing = english - set(texts(path))
                    self.assertFalse(missing, f"{path}: missing {sorted(missing)}")

    def test_translations_are_not_left_in_english(self):
        """Scenario: Spanish and Portuguese texts. Expected: none is the English text copied unchanged (names such as
        "Artise" and short labels are allowed)."""
        for folder in FOLDERS:
            for table in tables(folder):
                english = texts(folder / "en.lproj" / table)
                for language in LANGUAGES[1:]:
                    path = folder / f"{language}.lproj" / table
                    if not path.exists():
                        continue
                    for key, value in texts(path).items():
                        words = re.sub(r"%(\d+\$)?[@d]|[^\w ]", "", english.get(key, "")).split()
                        if len(words) >= 3:
                            self.assertNotEqual(value, english[key], f"{path}: {key} is still in English")


if __name__ == "__main__":
    unittest.main()

#
# Copyright 2026 Artise.
#
# SPDX-License-Identifier: AGPL-3.0-only
#
"""Applies Artise's wording to the string tables of a built app bundle.

1. In every language, "Element X" becomes "Artise" (permission prompts, the old-call message).
2. Then <overrides>/<language>.lproj/<table>.strings replace whole strings, for the languages
   Artise writes by hand. A regional language without its own folder (en-US) uses its base (en).

Usage: apply_string_overrides.py <app resources folder> <overrides folder>
"""
import pathlib
import plistlib
import re
import sys

TABLES = ("Localizable", "InfoPlist")
PRODUCT_NAMES = {"Element X": "Artise"}

_ESCAPES = {'"': '"', "\\": "\\", "n": "\n", "t": "\t", "r": "\r", "'": "'"}
_TOKEN = re.compile(r'\s+|/\*.*?\*/|//[^\n]*|"((?:[^"\\]|\\.)*)"|=|;', re.S)


def _unescape(text):
    def replace(match):
        escaped = match.group(1)
        if escaped.startswith("U"):
            return chr(int(escaped[1:], 16))
        return _ESCAPES.get(escaped, escaped)

    return re.sub(r"\\(U[0-9a-fA-F]{4}|.)", replace, text)


def parse_strings_text(text):
    """Parses an old-style `"key" = "value";` strings file."""
    strings, pending, position = {}, [], 0
    while position < len(text):
        match = _TOKEN.match(text, position)
        if not match:
            raise ValueError(f"Unexpected text at offset {position}: {text[position:position + 30]!r}")
        position = match.end()
        token = match.group(0)
        if match.group(1) is not None:
            pending.append(_unescape(match.group(1) or ""))
        elif token == ";":
            if len(pending) != 2:
                raise ValueError(f"Malformed entry before offset {position}")
            strings[pending[0]] = pending[1]
            pending = []
    if pending:
        raise ValueError("Unterminated entry at the end of the file")
    return strings


def load_strings(path):
    """Reads a .strings file in any format (old-style text, XML or binary plist)."""
    data = path.read_bytes()
    if data.startswith(b"bplist") or data.lstrip().startswith(b"<?xml"):
        return plistlib.loads(data)
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return parse_strings_text(data.decode("utf-16"))
    return parse_strings_text(data.decode("utf-8-sig"))


def rename_products(strings):
    changed = {}
    for key, value in strings.items():
        new_value = value
        for old, new in PRODUCT_NAMES.items():
            new_value = new_value.replace(old, new)
        if new_value != value:
            changed[key] = new_value
    return changed


def override_file(overrides, language, table):
    for candidate in (language, language.split("-")[0]):
        path = overrides / f"{candidate}.lproj" / f"{table}.strings"
        if path.exists():
            return path
    return None


def apply(resources, overrides):
    """Updates the tables in `resources` and returns how many strings changed."""
    applied = 0
    for lproj in sorted(resources.glob("*.lproj")):
        for table in TABLES:
            target = lproj / f"{table}.strings"
            if not target.exists():
                continue
            strings = load_strings(target)
            updates = rename_products(strings)
            override = override_file(overrides, lproj.stem, table)
            if override:
                updates.update(load_strings(override))
            if not updates:
                continue
            strings.update(updates)
            target.write_bytes(plistlib.dumps(strings, fmt=plistlib.FMT_BINARY))
            applied += len(updates)
    return applied


if __name__ == "__main__":
    count = apply(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
    print(f"Artise string overrides: {count} strings updated.")

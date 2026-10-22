#
# Copyright 2026 Artise.
#
# SPDX-License-Identifier: AGPL-3.0-only
#
"""Lists the unit test suites a feature branch runs: the ones that test Artise's code and the hooks it touches.

The full upstream suite takes 11 to 13 minutes a pass; these take about a minute. development still runs
everything, so an upstream test this misses fails there. A branch runs:

- every suite in UnitTests/Sources/Artise;
- every other suite whose file mentions Artise (tests of an upstream hook, such as the sticker button);
- for each Swift file that differs from development, the suite named after it ("TimelineItemMenuActionProvider.swift"
  runs "TimelineItemMenuActionProviderTests").

Usage: artise_test_suites.py [changed file ...]   (prints one suite name per line)
"""
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
TESTS = REPO / "UnitTests" / "Sources"
# A test type: `struct FooTests`, `final class FooTests: XCTestCase`, with attributes such as `@MainActor` before it.
SUITE = re.compile(r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:final\s+)?(?:struct|class)\s+(\w+Tests)\b", re.MULTILINE)


def suites_in(text):
    """The test types declared at the top level of a test file."""
    return SUITE.findall(text)


def suites(changed, tests_dir=TESTS):
    """The suites to run for a branch whose changed files are `changed` (paths), sorted and without repeats."""
    changed_stems = {pathlib.Path(path).stem for path in changed if path.endswith(".swift")}
    found = set()
    for path in sorted(tests_dir.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(tests_dir).as_posix()
        names = suites_in(text)
        if relative.startswith("Artise/") or re.search("artise", text, re.IGNORECASE):
            found.update(names)
        found.update(name for name in names if name[: -len("Tests")] in changed_stems)
    return sorted(found)


if __name__ == "__main__":
    print("\n".join(suites(sys.argv[1:])))

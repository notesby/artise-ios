#!/bin/sh
#
# Copyright 2026 Artise.
#
# SPDX-License-Identifier: AGPL-3.0-only
#
# Xcode build phase: applies Artise's wording to the app's built string tables.
# Upstream's string files are rewritten by their translation tool, so Artise never edits them.

set -eu

exec /usr/bin/python3 "$SRCROOT/Artise/Scripts/apply_string_overrides.py" \
    "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH" \
    "$SRCROOT/Artise/Resources/StringOverrides"

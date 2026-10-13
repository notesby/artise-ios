#!/bin/bash
#
# Copyright 2026 Artise.
#
# SPDX-License-Identifier: AGPL-3.0-only
#
# Fails when a file that Artise added has no Artise copyright and license header.
# Formats without comments (JSON, string catalogs, images) are skipped.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

paths=(Artise ElementX/Sources/Artise ArtiseStickerShare .github/workflows/artise*.yml)
missing=0

while IFS= read -r file; do
    case "$file" in
        *.swift|*.sh|*.yml|*.yaml|*.plist|*.md|*.py|*.strings|*.xcconfig) ;;
        *) continue ;;
    esac
    if ! head -n 12 "$file" | grep -q "Copyright 2026 Artise\." ||
       ! head -n 12 "$file" | grep -q "SPDX-License-Identifier: AGPL-3.0-only"; then
        echo "::error file=$file::Missing the Artise header (Copyright 2026 Artise. / SPDX-License-Identifier: AGPL-3.0-only)"
        missing=1
    fi
done < <(git ls-files -- "${paths[@]}" 2>/dev/null)

if [ "$missing" -ne 0 ]; then
    exit 1
fi
echo "All Artise files have the Artise header."

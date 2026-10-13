#
# Copyright 2026 Artise.
#
# SPDX-License-Identifier: AGPL-3.0-only
#
"""Generate Artise's iOS app icon (the default, dark and tinted 1024 px PNGs plus a preview), the round logo on
the welcome screen, and the CallKit icon.

The geometry and colours are the same as the Android launcher icon
(artise-android: artise/appicon/icon-source/gen.py), so both apps show the same mark.

Usage: python3 make_app_icon.py [output appiconset folder]
Needs cairosvg and Pillow (pip install cairosvg pillow).
"""
import io
import math
import pathlib
import sys

import cairosvg
from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
OUT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "Assets.xcassets" / "ArtiseAppIcon.appiconset"
OUT.mkdir(parents=True, exist_ok=True)

BLUE = "#22408A"
BLUE_LIGHT = "#2E55B3"
BLUE_DEEP = "#172D63"
YELLOW = "#FFE27A"

# The mark is drawn on Android's 108 grid and scaled toward the centre, exactly as on Android.
SCALE = 0.88
SIZE = 1024


def s(x, y):
    return (54 + (x - 54) * SCALE, 54 + (y - 54) * SCALE)


def rounded_polygon(points, radii):
    """Closed path through points with each corner rounded by a quadratic curve."""
    points = [s(*p) for p in points]
    radii = [r * SCALE for r in radii]
    n = len(points)
    parts = []
    for i in range(n):
        prev, cur, nxt = points[i - 1], points[i], points[(i + 1) % n]
        r = radii[i]

        def toward(a, b, d):
            dx, dy = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dy)
            return (a[0] + dx / length * d, a[1] + dy / length * d)

        start = toward(cur, prev, r)
        end = toward(cur, nxt, r)
        parts.append(("M" if i == 0 else "L") + f"{start[0]:.2f},{start[1]:.2f}")
        parts.append(f"Q{cur[0]:.2f},{cur[1]:.2f} {end[0]:.2f},{end[1]:.2f}")
    return " ".join(parts) + " Z"


def sparkle(cx, cy, r, pinch=0.16):
    """Four-point star with concave sides, Ari's mark."""
    cx, cy = s(cx, cy)
    r *= SCALE
    p = r * pinch
    return (
        f"M{cx:.2f},{cy - r:.2f} "
        f"Q{cx + p:.2f},{cy - p:.2f} {cx + r:.2f},{cy:.2f} "
        f"Q{cx + p:.2f},{cy + p:.2f} {cx:.2f},{cy + r:.2f} "
        f"Q{cx - p:.2f},{cy + p:.2f} {cx - r:.2f},{cy:.2f} "
        f"Q{cx - p:.2f},{cy - p:.2f} {cx:.2f},{cy - r:.2f} Z"
    )


# A house whose base turns into a chat bubble's tail: home + conversation.
HOUSE = rounded_polygon(
    [(54, 27), (80, 46.5), (80, 71), (49, 71), (39.5, 81), (39.5, 71), (28, 71), (28, 46.5)],
    [4.5, 4, 5, 2.5, 1.8, 1.2, 5, 4],
)
# Ari: one big sparkle and a small companion.
SPARK_BIG = sparkle(52, 55.5, 11.5)
SPARK_SMALL = sparkle(66.5, 45.5, 4.6)

# iOS shows the whole square and applies its own corner mask, so the icon shows the middle 72 units
# of the 108 grid, like the Play Store icon.
VIEWBOX = 'viewBox="18 18 72 72"'

GRADIENT = f"""<defs><linearGradient id="g" x1="0" y1="0" x2="108" y2="108" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="{BLUE_LIGHT}"/><stop offset="1" stop-color="{BLUE_DEEP}"/>
  </linearGradient></defs>"""

DEFAULT_SVG = f"""<svg xmlns="http://www.w3.org/2000/svg" {VIEWBOX}>
  {GRADIENT}
  <rect width="108" height="108" fill="url(#g)"/>
  <path d="{HOUSE}" fill="{YELLOW}"/>
  <path d="{SPARK_BIG}" fill="{BLUE}"/>
  <path d="{SPARK_SMALL}" fill="{BLUE}"/>
</svg>"""

# Dark appearance: iOS draws its own dark background behind a transparent icon.
DARK_SVG = f"""<svg xmlns="http://www.w3.org/2000/svg" {VIEWBOX}>
  <path d="{HOUSE}" fill="{YELLOW}"/>
  <path d="{SPARK_BIG}" fill="{BLUE_DEEP}"/>
  <path d="{SPARK_SMALL}" fill="{BLUE_DEEP}"/>
</svg>"""

# Tinted appearance: a white mark that iOS recolours, with the sparkles cut out.
TINTED_SVG = f"""<svg xmlns="http://www.w3.org/2000/svg" {VIEWBOX}>
  <rect x="18" y="18" width="72" height="72" fill="#000"/>
  <path d="{HOUSE} {SPARK_BIG} {SPARK_SMALL}" fill="#FFF" fill-rule="evenodd"/>
</svg>"""


def render(svg, name, opaque):
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=SIZE, output_height=SIZE)
    image = Image.open(io.BytesIO(png))
    # App Store Connect rejects an app icon with an alpha channel.
    image = image.convert("RGB") if opaque else image.convert("RGBA")
    image.save(OUT / name, optimize=True)


render(DEFAULT_SVG, "AppIcon.png", opaque=True)
render(DARK_SVG, "AppIcon-dark.png", opaque=False)
render(TINTED_SVG, "AppIcon-tinted.png", opaque=True)

(OUT / "Contents.json").write_text("""{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "AppIcon-dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "AppIcon-tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
""")

# A preview with the iOS corner mask, for reviews only (not shipped).
preview = Image.open(OUT / "AppIcon.png").resize((256, 256))
mask = Image.new("L", (256, 256), 0)
from PIL import ImageDraw  # noqa: E402

ImageDraw.Draw(mask).rounded_rectangle((0, 0, 255, 255), radius=57, fill=255)
preview.putalpha(mask)
preview.save(HERE / "preview.png")
print("written to", OUT)

# The welcome screen's logo, in place of Element's (same name and 110 pt size, so no code changes): the icon's
# colours in a circle, which Element's brand card frames with round shadows.
REPO = HERE.parents[2]
LOGO_SVG = f"""<svg xmlns="http://www.w3.org/2000/svg" width="110pt" height="110pt" viewBox="9 9 90 90">
  {GRADIENT}
  <circle cx="54" cy="54" r="45" fill="url(#g)"/>
  <path d="{HOUSE}" fill="{YELLOW}"/>
  <path d="{SPARK_BIG}" fill="{BLUE}"/>
  <path d="{SPARK_SMALL}" fill="{BLUE}"/>
</svg>"""
cairosvg.svg2pdf(bytestring=LOGO_SVG.encode(),
                 write_to=str(REPO / "ElementX/Resources/Assets.xcassets/images/app-logo.imageset/app-logo.pdf"))

# CallKit draws its icon as a template (only the shape counts): the mark with the sparkles cut out, 40 pt.
CALLKIT = REPO / "Artise/Resources/Assets.xcassets/ArtiseCallKitIcon.imageset"
CALLKIT.mkdir(parents=True, exist_ok=True)
CALLKIT_SVG = f"""<svg xmlns="http://www.w3.org/2000/svg" width="40pt" height="40pt" viewBox="24 24 60 60">
  <path d="{HOUSE} {SPARK_BIG} {SPARK_SMALL}" fill="#000" fill-rule="evenodd"/>
</svg>"""
cairosvg.svg2pdf(bytestring=CALLKIT_SVG.encode(), write_to=str(CALLKIT / "ArtiseCallKitIcon.pdf"))
(CALLKIT / "Contents.json").write_text("""{
  "images" : [
    {
      "filename" : "ArtiseCallKitIcon.pdf",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
""")
print("logo and CallKit icon written")

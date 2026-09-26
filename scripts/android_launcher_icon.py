#!/usr/bin/env python3
"""Regenerate the Android launcher icon from the iOS app icon.

The iOS icon (``AppIcon.appiconset/FlightFormsLight-1024.png``) is the one
piece of artwork the app has. Android wants an adaptive icon instead: layers on
a 108 dp canvas of which only the middle 72 dp shows, cut to whatever shape the
launcher uses. This writes, for each density:

- ``ic_launcher_background.png``: the iOS artwork scaled to the visible 72 dp,
  its edges stretched out to fill the 18 dp margin the launcher uses for
  parallax and shape cropping. The artwork already has its own background, so
  it is the background layer.
- no foreground: ``mipmap-anydpi/ic_launcher.xml`` uses a transparent colour.
  The artwork is one picture; split into layers it would drift apart as the
  launcher animates them.
- ``ic_launcher_monochrome.png``: the white parts of the artwork (the form, the
  ring, the aeroplane and the tick) as an alpha mask, for Android 13 themed
  icons, which tint it with the wallpaper's colours.

Run it when the iOS icon changes, and commit the result:

    pip install pillow numpy
    python scripts/android_launcher_icon.py
"""

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = (
    ROOT / "app" / "flyfun-forms" / "flyfun-forms" / "Assets.xcassets"
    / "AppIcon.appiconset" / "FlightFormsLight-1024.png"
)
RES = ROOT / "app" / "android" / "app" / "src" / "main" / "res"

# Adaptive icon canvas in px at each density: 108 dp.
DENSITIES = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

# The visible part of the canvas: 72 of 108 dp.
VISIBLE = 72 / 108


def full_canvas(art: np.ndarray) -> np.ndarray:
    """The artwork centred on the 108 dp canvas, its edge pixels stretched outwards."""
    size = art.shape[0]
    margin = round(size * (1 / VISIBLE - 1) / 2)
    pad = ((margin, margin), (margin, margin), (0, 0))
    return np.pad(art, pad, mode="edge")


def white_mask(rgb: np.ndarray) -> np.ndarray:
    """Alpha for the white parts of the artwork, soft at the edges."""
    rgb = rgb.astype(np.float32)
    lightest = rgb.max(axis=2)
    darkest = rgb.min(axis=2)
    # White is bright and grey; the blue sky and the red badge are bright but
    # coloured, the form's text lines are grey but dark.
    whiteness = np.clip((darkest - 175) / 30, 0, 1) * np.clip(1 - (lightest - darkest - 18) / 17, 0, 1)
    return (whiteness * 255).astype(np.uint8)


def main() -> None:
    art = np.asarray(Image.open(SOURCE).convert("RGB"))
    canvas = full_canvas(art)
    mask = white_mask(canvas)
    background = Image.fromarray(canvas, "RGB")
    monochrome = Image.fromarray(
        np.dstack([np.full_like(mask, 255)] * 3 + [mask]), "RGBA"
    )

    for density, px in DENSITIES.items():
        out = RES / f"mipmap-{density}"
        out.mkdir(parents=True, exist_ok=True)
        background.resize((px, px), Image.LANCZOS).save(out / "ic_launcher_background.png", optimize=True)
        monochrome.resize((px, px), Image.LANCZOS).save(out / "ic_launcher_monochrome.png", optimize=True)
        print(f"wrote {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

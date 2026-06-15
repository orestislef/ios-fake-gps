#!/usr/bin/env python3
"""
Generate the app icon: a white location pin with a route trail on a blue→teal
rounded-square background. Renders at 4x and downsamples for clean edges, writes
a 1024px PNG, and builds a full .iconset for `iconutil`.
"""
import math
import os

from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(REPO, "assets")
SS = 4               # supersample factor
BASE = 1024


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def squircle_mask(size, n=5.0):
    """Apple-style superellipse (squircle) mask, filled row by row."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    a = size / 2.0
    c = (size - 1) / 2.0
    for y in range(size):
        ny = (y - c) / a
        v = 1.0 - abs(ny) ** n
        if v <= 0:
            continue
        nx = v ** (1.0 / n)
        d.line([(c - nx * a, y), (c + nx * a, y)], fill=255)
    return m


def render(size):
    top = (10, 132, 255)      # iOS system blue
    bottom = (52, 199, 89)    # iOS system green
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    grad = Image.new("RGBA", (size, size))
    gd = ImageDraw.Draw(grad)
    for y in range(size):
        gd.line([(0, y), (size, y)], fill=lerp(top, bottom, y / size) + (255,))
    img.paste(grad, (0, 0), squircle_mask(size))

    d = ImageDraw.Draw(img, "RGBA")
    cx = size / 2
    head_cy = size * 0.42

    # Two subtle signal pulses hugging the pin — "broadcasting" a spoofed spot.
    for rr, alpha in [(0.235, 85), (0.300, 45)]:
        R = size * rr
        width = max(1, int(size * 0.014))
        d.ellipse([cx - R, head_cy - R, cx + R, head_cy + R],
                  outline=(255, 255, 255, alpha), width=width)

    # Pin: circular head + tapered tail to a point.
    head_r = size * 0.165
    tip_y = size * 0.76
    white = (255, 255, 255, 255)
    d.ellipse([cx - head_r, head_cy - head_r, cx + head_r, head_cy + head_r],
              fill=white)
    spread = head_r * 0.80
    d.polygon([(cx - spread, head_cy + head_r * 0.60),
               (cx + spread, head_cy + head_r * 0.60),
               (cx, tip_y)], fill=white)
    # Inner dot, tinted green to echo the live-position marker.
    hole_r = head_r * 0.46
    d.ellipse([cx - hole_r, head_cy - hole_r, cx + hole_r, head_cy + hole_r],
              fill=(52, 199, 89, 255))
    return img


def main():
    os.makedirs(ASSETS, exist_ok=True)
    big = render(BASE * SS)
    base = big.resize((BASE, BASE), Image.LANCZOS)
    base.save(os.path.join(ASSETS, "icon_1024.png"))

    iconset = os.path.join(ASSETS, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    specs = [
        (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
    ]
    for px, name in specs:
        big.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))
    print("wrote", os.path.join(ASSETS, "icon_1024.png"))
    print("wrote", iconset)


if __name__ == "__main__":
    main()

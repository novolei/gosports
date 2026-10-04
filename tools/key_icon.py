#!/usr/bin/env python
"""Raw Gemini render on a flat chroma-green background -> clean transparent game icon.

    python tools/key_icon.py art_src/gemini/raw/bonk_v1.png assets/env/bonk_icon.png [size=512] [margin=0.04]

Steps: estimate the background green from the border, soft-key every pixel by its distance to it (green dominance),
remove the green spill from semi-transparent edges, crop to the content (ignoring stray specks), pad to a square with a
small margin and resize. Always works from the raw render (generation is not reproducible).
"""
import sys

import numpy as np
from PIL import Image


def key(img: Image.Image) -> Image.Image:
    rgb = np.asarray(img.convert("RGB"), np.float32) / 255.0
    h, w, _ = rgb.shape
    border = np.concatenate([rgb[:6].reshape(-1, 3), rgb[-6:].reshape(-1, 3), rgb[:, :6].reshape(-1, 3), rgb[:, -6:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    # how much greener than red/blue a pixel is, relative to the background's own green dominance
    dom = g - np.maximum(r, b)
    bg_dom = max(float(bg[1] - max(bg[0], bg[2])), 0.2)
    t = np.clip(dom / bg_dom, 0.0, 1.0)
    # also treat pixels very close to the background colour as background
    dist = np.sqrt(((rgb - bg) ** 2).sum(-1))
    t = np.maximum(t, np.clip(1.0 - dist / 0.18, 0.0, 1.0))
    alpha = np.clip(1.0 - (t - 0.08) / 0.62, 0.0, 1.0)
    alpha = alpha * alpha * (3 - 2 * alpha)                      # smoothstep
    # colour decontamination (matting equation c = a*fg + (1-a)*bg  ->  fg) on the semi-transparent edge,
    # then a final clamp of any remaining green dominance
    a3 = alpha[..., None]
    fg = np.where(a3 < 0.98, (rgb - bg * (1.0 - a3)) / np.maximum(a3, 0.04), rgb)
    fg = np.clip(fg, 0.0, 1.0)
    fr, fgc, fb = fg[..., 0], fg[..., 1], fg[..., 2]
    spill = np.clip(fgc - np.maximum(fr, fb), 0.0, None)
    fgc = np.where(alpha < 0.98, fgc - spill, fgc)
    out = np.dstack([fr, fgc, fb, alpha])
    return Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def crop_square(img: Image.Image, size: int, margin: float) -> Image.Image:
    a = np.asarray(img)[..., 3].astype(np.float32) / 255.0
    ys = np.where(a.sum(1) > 3.0)[0]                              # ignore specks thinner than ~3 px
    xs = np.where(a.sum(0) > 3.0)[0]
    x0, x1, y0, y1 = xs[0], xs[-1] + 1, ys[0], ys[-1] + 1
    side = int(max(x1 - x0, y1 - y0) * (1.0 + 2.0 * margin))
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img.crop((x0, y0, x1, y1)), (side // 2 - (cx - x0), side // 2 - (cy - y0)))
    return canvas.resize((size, size), Image.LANCZOS)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 512
    margin = float(sys.argv[4]) if len(sys.argv) > 4 else 0.04
    out = crop_square(key(Image.open(src)), size, margin)
    out.save(dst)
    a = np.asarray(out)[..., 3]
    print("saved %s  %dx%d  opaque %.1f%%  transparent %.1f%%  edge %.1f%%" % (
        dst, out.size[0], out.size[1], (a > 250).mean() * 100, (a < 5).mean() * 100, ((a >= 5) & (a <= 250)).mean() * 100))


if __name__ == "__main__":
    main()

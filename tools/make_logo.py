#!/usr/bin/env python
"""Brand assets: app icon (App Store / Play / Windows), Android adaptive layers, boot splash, wordmark.

Input : art_src/brand/ball_render.png  (the real in-game ball, rendered by tools/render_ball.gd)
Output: icon.png (512, project icon)             art_src/brand/ios/*.png (App Store 1024 + the iOS size set)
        assets/brand/android_*.png (launcher)    art_src/brand/play_store_512.png      art_src/brand/icon.ico
        assets/ui/splash.png (compact transparent logo + text; shown at native size on a solid colour from project.godot)
        art_src/brand/wordmark.png

App Store rules respected: 1024 x 1024 px, fully opaque RGB (no alpha channel), square corners (iOS rounds them itself),
one clear focal point, no text, nothing important near the edges.  Android adaptive icons keep the mark inside the
central 66 % "safe zone".   python tools/make_logo.py
"""
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

FONT = "assets/fonts/ui_font.ttf"
BG_TOP = (46, 232, 200)          # icon gradient: turquoise ...
BG_BOT = (20, 140, 216)          # ... to a clear blue
SPLASH_BG = (29, 186, 205)       # the solid colour behind the splash (== project.godot boot_splash/bg_color)
PINK = (255, 79, 160)
YELLOW = (255, 214, 64)
WHITE = (255, 255, 255)
NAVY = (8, 52, 96)
SS = 2


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def diag_gradient(size):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    t = np.clip((xx * 0.42 + yy * 0.58) / size, 0, 1)[..., None]
    c0 = np.array(BG_TOP, np.float32)
    c1 = np.array(BG_BOT, np.float32)
    return Image.fromarray((c0 + (c1 - c0) * t).astype(np.uint8), "RGB")


def radial_glow(size, cx, cy, r, alpha):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
    a = np.clip(1.0 - d, 0, 1) ** 1.6 * alpha
    arr = np.zeros((size, size, 4), np.uint8)
    arr[..., :3] = 255
    arr[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def ribbon(canvas, start, ang_deg, length, width, bend, color):
    """tapered, slightly curved speed line that starts at `start` and runs backwards (angle measured from -x, downwards)"""
    a = math.radians(ang_deg)
    dx, dy = -math.cos(a), math.sin(a)
    nx, ny = -dy, dx
    pts_l, pts_r = [], []
    n = 60
    for i in range(n + 1):
        t = i / n
        x = start[0] + dx * length * t + nx * bend * math.sin(t * math.pi) * 0.9
        y = start[1] + dy * length * t + ny * bend * math.sin(t * math.pi) * 0.9
        w = width * (1.0 - t) ** 0.85 * (0.55 + 0.45 * min(1.0, t * 6))   # fat at the ball, thin at the tail
        pts_l.append((x + nx * w / 2, y + ny * w / 2))
        pts_r.append((x - nx * w / 2, y - ny * w / 2))
    d = ImageDraw.Draw(canvas)
    d.polygon(pts_l + pts_r[::-1], fill=color)
    d.ellipse([start[0] - width / 2, start[1] - width / 2, start[0] + width / 2, start[1] + width / 2], fill=color)


def star4(canvas, cx, cy, r, color):
    d = ImageDraw.Draw(canvas)
    pts = []
    for i in range(8):
        a = math.pi / 4 * i - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.26
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=color)


def compose_mark(size, ball_d, trail_scale=1.0, sparkle=True, center=None):
    """ball + speed lines + sparkle on a transparent square canvas of `size` px"""
    big = size * SS
    cx, cy = (center if center else (size * 0.56, size * 0.46))
    cx, cy = cx * SS, cy * SS
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    # speed lines (behind the ball): white, pink, yellow, staggered
    L = size * 0.64 * trail_scale * SS
    wd = ball_d * 0.30 * SS
    off = ball_d * 0.36 * SS
    ang = 24
    for k, (col, ln, o, wmul) in enumerate([((255, 255, 255, 255), 1.0, -off, 1.0), (PINK + (255,), 0.86, 0.0, 1.12), (YELLOW + (255,), 0.72, off, 0.9)]):
        a = math.radians(ang)
        nxv, nyv = math.sin(a), math.cos(a)
        st = (cx + nxv * o * -1.0, cy + nyv * o)
        ribbon(layer, st, ang, L * ln, wd * wmul, ball_d * 0.06 * (1 if k != 1 else -1) * SS, col)
    # soft shadow of the whole mark (drop shadow keeps it readable on any background)
    sh = layer.filter(ImageFilter.GaussianBlur(ball_d * 0.02 * SS))
    shadow = Image.new("RGBA", layer.size, (0, 40, 80, 0))
    shadow.putalpha(sh.getchannel("A").point(lambda v: int(v * 0.30)))
    base = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    base.alpha_composite(shadow, (0, int(ball_d * 0.025 * SS)))
    base.alpha_composite(layer)
    # the real ball
    ball = Image.open("art_src/brand/ball_render.png").convert("RGBA")
    bd = int(ball_d * SS)
    ball = ball.resize((bd, bd), Image.LANCZOS)
    bsh = Image.new("RGBA", (bd, bd), (0, 40, 80, 0))
    bsh.putalpha(ball.getchannel("A").filter(ImageFilter.GaussianBlur(bd * 0.02)).point(lambda v: int(v * 0.35)))
    base.alpha_composite(bsh, (int(cx - bd / 2), int(cy - bd / 2 + bd * 0.035)))
    base.alpha_composite(ball, (int(cx - bd / 2), int(cy - bd / 2)))
    if sparkle:
        sp = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        star4(sp, cx + ball_d * 0.44 * SS, cy - ball_d * 0.60 * SS, ball_d * 0.14 * SS, (255, 255, 255, 255))
        star4(sp, cx + ball_d * 0.55 * SS, cy - ball_d * 0.30 * SS, ball_d * 0.07 * SS, PINK + (255,))
        base.alpha_composite(sp)
    return base.resize((size, size), Image.LANCZOS)


def round_corners(img, radius_frac):
    """rounded-square RGBA version of an opaque icon (the corner radius iOS / macOS / Windows 11 use is ~22 % of the side)"""
    size = img.size[0]
    k = 4
    mask = Image.new("L", (size * k, size * k), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size * k - 1, size * k - 1], radius=int(size * k * radius_frac), fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def make_icon(size=1024):
    bg = diag_gradient(size).convert("RGBA")
    bg.alpha_composite(radial_glow(size, size * 0.56, size * 0.46, size * 0.62, 0.30))
    # faint flat diagonal stripes (the game's UI language)
    st = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(st)
    for x in range(-size, size * 2, 150):
        d.polygon([(x, size), (x + 54, size), (x + 54 + size * 0.7, 0), (x + size * 0.7, 0)], fill=(255, 255, 255, 16))
    bg.alpha_composite(st)
    mark = compose_mark(size, ball_d=size * 0.62, center=(size * 0.575, size * 0.50))
    bg.alpha_composite(mark)
    return bg.convert("RGB")                       # opaque: App Store icons must not carry an alpha channel


def fit_in_circle(mark, canvas, circle_frac):
    """scale `mark` (RGBA, square) so its visible content fits inside a circle of circle_frac * canvas, centred"""
    bbox = mark.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    crop = mark.crop(bbox)
    w, h = crop.size
    diag = math.hypot(w, h)
    k = canvas * circle_frac / diag
    crop = crop.resize((max(1, int(w * k)), max(1, int(h * k))), Image.LANCZOS)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.alpha_composite(crop, ((canvas - crop.size[0]) // 2, (canvas - crop.size[1]) // 2))
    return out


def outlined_text(text, size, fill, outline, ow, shadow=None):
    font = ImageFont.truetype(FONT, size)
    l, t, r, b = font.getbbox(text, stroke_width=ow)
    pad = ow + 24
    img = Image.new("RGBA", (r - l + pad * 2, b - t + pad * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if shadow:
        d.text((pad - l + 0, pad - t + 10), text, font=font, fill=shadow, stroke_width=ow, stroke_fill=shadow)
    d.text((pad - l, pad - t), text, font=font, fill=fill, stroke_width=ow, stroke_fill=outline)
    return img


def make_wordmark(h=300):
    go = outlined_text("Go", 250, YELLOW + (255,), NAVY + (255,), 16, NAVY + (110,))
    sp = outlined_text("Sports", 250, WHITE + (255,), NAVY + (255,), 16, NAVY + (110,))
    w = go.size[0] + sp.size[0] - 30
    mk = Image.new("RGBA", (w, max(go.size[1], sp.size[1])), (0, 0, 0, 0))
    mk.alpha_composite(go, (0, 0))
    mk.alpha_composite(sp, (go.size[0] - 30, 0))
    return mk.rotate(4, resample=Image.BICUBIC, expand=True)


def make_splash(w=960, h=640):
    """compact transparent canvas with the logo group centred. project.godot shows it at NATIVE size (boot_splash/fullsize=false)
    on the solid boot_splash/bg_color: Godot's fullsize mode crops to the longer window side, a fixed small logo never does."""
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    mark = compose_mark(700, ball_d=400, trail_scale=0.9, center=(400, 330))
    mk = mark.crop((20, 40, 680, 620))
    mk = mk.resize((int(mk.size[0] * 0.48), int(mk.size[1] * 0.48)), Image.LANCZOS)
    wm = make_wordmark()
    k = 515.0 / wm.size[0]
    wm = wm.resize((int(wm.size[0] * k), int(wm.size[1] * k)), Image.LANCZOS)
    sub = outlined_text("VOLLEYBALL  ·  排球", 31, WHITE + (255,), NAVY + (255,), 4)
    total_h = mk.size[1] + wm.size[1] + sub.size[1] - 54
    y0 = (h - total_h) // 2
    out.alpha_composite(mk, ((w - mk.size[0]) // 2 + 12, y0))
    out.alpha_composite(wm, ((w - wm.size[0]) // 2, y0 + mk.size[1] - 26))
    out.alpha_composite(sub, ((w - sub.size[0]) // 2, y0 + mk.size[1] - 26 + wm.size[1] - 18))
    return out


def save(img, path, **kw):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    img.save(path, **kw)
    print(path, img.size, img.mode)


def main():
    icon = make_icon(1024)
    # ---- Apple: App Store master + the usual iOS / iPadOS / macOS sizes
    save(icon, "art_src/brand/ios/AppStore_1024.png", optimize=True)
    for px in (180, 167, 152, 120, 87, 80, 76, 60, 58, 40, 29, 20):
        save(icon.resize((px, px), Image.LANCZOS), "art_src/brand/ios/icon_%d.png" % px, optimize=True)
    # ---- Google Play + Android launcher (legacy + adaptive)
    save(icon.resize((512, 512), Image.LANCZOS), "art_src/brand/play_store_512.png", optimize=True)
    save(icon.resize((192, 192), Image.LANCZOS), "assets/brand/android_192.png", optimize=True)
    mark = compose_mark(1024, ball_d=1024 * 0.62, center=(1024 * 0.575, 1024 * 0.50))
    fg = fit_in_circle(mark, 1024, 0.62).resize((432, 432), Image.LANCZOS)         # content inside the 66 % safe zone
    save(fg, "assets/brand/android_fg.png", optimize=True)
    bg = diag_gradient(432).convert("RGBA")
    bg.alpha_composite(radial_glow(432, 216, 200, 280, 0.28))
    save(bg.convert("RGB"), "assets/brand/android_bg.png", optimize=True)
    # themed (monochrome) icon: the ball as a white stencil
    ball = Image.open("art_src/brand/ball_render.png").convert("RGBA").resize((300, 300), Image.LANCZOS)
    rgb = np.array(ball.convert("RGB")).astype(np.float32)
    # panels that are yellow / blue become cut-outs, white stays solid
    lum = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    keep = (sat < 60) | (lum < 50)
    alpha = np.array(ball.getchannel("A")).astype(np.float32) * np.where(keep, 1.0, 0.0)
    mono = Image.new("RGBA", (300, 300), (255, 255, 255, 0))
    mono.putalpha(Image.fromarray(alpha.astype(np.uint8), "L"))
    mono_c = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    mono_c.alpha_composite(mono, (66, 66))
    save(mono_c, "assets/brand/android_mono.png", optimize=True)
    # ---- project icon (full-bleed square, used by Godot tooling) + the rounded desktop icon (window title bar / taskbar / .exe / .ico)
    save(icon.resize((512, 512), Image.LANCZOS), "icon.png", optimize=True)
    rounded = round_corners(icon, 0.2237)
    save(rounded.resize((512, 512), Image.LANCZOS), "assets/brand/icon_win.png", optimize=True)
    rounded.save("assets/brand/icon_win.ico", sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (24, 24), (16, 16)])
    print("assets/brand/icon_win.ico")
    # ---- wordmark + splash
    wm = make_wordmark()
    save(wm, "art_src/brand/wordmark.png", optimize=True)
    save(make_splash(), "assets/ui/splash.png", optimize=True)


if __name__ == "__main__":
    main()

#!/usr/bin/env python
"""Renders the boot splash (assets/ui/splash.png) and a matching launcher icon (icon.png 512) in the game's own look:
airy sky gradient, tilted 'Go Sports' logo, swoosh lines, a ball. Re-run after changing the look.
    python tools/make_splash.py
"""
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1920, 1080
FONT = "assets/fonts/ui_font.ttf"
TEAL = (32, 185, 168)
BLUE = (27, 134, 217)
SKY_TOP = (150, 205, 245)
SKY_BOT = (236, 247, 252)


def gradient(w, h, a, b):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        c = tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    return img


def outlined_text(size, text, fill, outline, ow):
    font = ImageFont.truetype(FONT, size)
    l, t, r, b = font.getbbox(text, stroke_width=ow)
    img = Image.new("RGBA", (r - l + ow * 2 + 8, b - t + ow * 2 + 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.text((ow + 4 - l, ow + 4 - t), text, font=font, fill=fill, stroke_width=ow, stroke_fill=outline)
    return img


def volleyball(d_px):
    """white ball with three curved colour bands (yellow / blue / yellow) - reads as a volleyball even at icon size"""
    s = d_px * 4
    pad = s * 0.04
    ball = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    bd = ImageDraw.Draw(ball)
    bd.ellipse([pad, pad, s - pad, s - pad], fill=(255, 255, 255, 255))
    bands = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ld = ImageDraw.Draw(bands)
    r = s * 0.62
    w = int(s * 0.17)
    for (cx, cy, a0, a1), col in [((-0.30, 0.5, -52, 52), (255, 214, 64, 255)), ((1.30, 0.5, 128, 232), (40, 110, 225, 255)), ((0.5, -0.30, 38, 142), (255, 214, 64, 255))]:
        ld.arc([s * cx - r, s * cy - r, s * cx + r, s * cy + r], a0, a1, fill=col, width=w)
    clip = Image.new("L", (s, s), 0)
    ImageDraw.Draw(clip).ellipse([pad, pad, s - pad, s - pad], fill=255)
    ball.paste(bands, mask=Image.composite(bands.split()[3], Image.new("L", (s, s), 0), clip))
    # soft outline + gloss on their own layers (alpha-blended, not overwritten)
    ring = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse([pad, pad, s - pad, s - pad], outline=(30, 70, 140, 255), width=int(s * 0.022))
    ball.alpha_composite(ring)
    gloss = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).ellipse([s * 0.2, s * 0.15, s * 0.4, s * 0.29], fill=(255, 255, 255, 150))
    ball.alpha_composite(gloss)
    return ball.resize((d_px, d_px), Image.LANCZOS)


def splash():
    img = gradient(W, H, SKY_TOP, SKY_BOT).convert("RGBA")
    # soft clouds
    cl = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(cl)
    for cx, cy, rr in [(380, 220, 90), (470, 200, 120), (560, 230, 80), (1500, 300, 110), (1600, 285, 80), (1420, 320, 70), (1150, 140, 60), (1220, 130, 90)]:
        cd.ellipse([cx - rr, cy - rr * 0.55, cx + rr, cy + rr * 0.55], fill=(255, 255, 255, 150))
    cl = cl.filter(ImageFilter.GaussianBlur(10))
    img.alpha_composite(cl)
    # court strip at the bottom
    d = ImageDraw.Draw(img)
    d.polygon([(0, H), (0, int(H * 0.82)), (W, int(H * 0.76)), (W, H)], fill=(238, 154, 150, 255))
    d.polygon([(0, int(H * 0.82)), (W, int(H * 0.76)), (W, int(H * 0.775)), (0, int(H * 0.835))], fill=(255, 255, 255, 255))
    # logo: "Go" teal + "Sports" blue, tilted -4 degrees
    go = outlined_text(250, "Go", TEAL + (255,), (255, 255, 255, 255), 14)
    sp = outlined_text(250, "Sports", BLUE + (255,), (255, 255, 255, 255), 14)
    logo = Image.new("RGBA", (go.width + sp.width - 20, max(go.height, sp.height)), (0, 0, 0, 0))
    logo.alpha_composite(go, (0, 0))
    logo.alpha_composite(sp, (go.width - 20, 0))
    shadow = Image.new("RGBA", logo.size, (0, 0, 0, 0))
    shadow.paste((20, 60, 110, 90), mask=logo.split()[3])
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    lg = Image.new("RGBA", (logo.width + 60, logo.height + 60), (0, 0, 0, 0))
    lg.alpha_composite(shadow, (30, 38))
    lg.alpha_composite(logo, (30, 30))
    lg = lg.rotate(4, resample=Image.BICUBIC, expand=True)
    img.alpha_composite(lg, ((W - lg.width) // 2, int(H * 0.22)))
    # strap line + swoosh lines
    strap = outlined_text(60, "VOLLEYBALL", (29, 106, 112, 255), (255, 255, 255, 255), 6)
    img.alpha_composite(strap, ((W - strap.width) // 2, int(H * 0.57)))
    sw = ImageDraw.Draw(img)
    for i, col in enumerate([(55, 211, 214), (230, 91, 220), (59, 124, 255)]):
        y0 = int(H * 0.66) + i * 18
        x_end = int(W * (0.72 - 0.12 * i))
        pts = []
        for k in range(61):
            t = k / 60
            x = int(W * 0.28 + (x_end - W * 0.28) * t)
            y = int(y0 - math.sin(t * math.pi) * 8 - t * 8)
            pts.append((x, y))
        sw.line(pts, fill=col + (255,), width=8, joint="curve")
        sw.ellipse([pts[-1][0] - 9, pts[-1][1] - 9, pts[-1][0] + 9, pts[-1][1] + 9], fill=col + (255,))
    ball = volleyball(150)
    img.alpha_composite(ball, (int(W * 0.5 + 420), int(H * 0.085)))
    img.convert("RGB").save("assets/ui/splash.png")
    print("splash written")


def icon():
    s = 512
    img = gradient(s, s, (70, 190, 200), (30, 140, 205)).convert("RGBA")
    d = ImageDraw.Draw(img)
    d.rectangle([0, int(s * 0.74), s, s], fill=(255, 168, 120, 255))
    b = volleyball(int(s * 0.74))
    img.alpha_composite(b, (int(s * 0.13), int(s * 0.1)))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.22), fill=255)
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    out.paste(img, mask=mask)
    out.save("icon.png")
    print("icon written")


if __name__ == "__main__":
    splash()
    icon()

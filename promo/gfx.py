"""2D drawing helpers for the promo video: game fonts + palette, rounded shapes, cached RGBA layers, easing, and a tiny compositor.

Everything is drawn in 1920x1080 coordinates.  Layers are pre-rendered once (PIL) and then moved / scaled / faded per frame with
OpenCV, so a 3-minute 60 fps edit renders in minutes, not hours.
"""
from __future__ import annotations

import math
from functools import lru_cache
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT_DIR = ROOT / "core" / "assets" / "fonts"
W, H = 1920, 1080

# palette = the game's UI language (scripts/ui/ui_kit.gd)
BLUE = (47, 168, 255)
BLUE_DARK = (22, 104, 201)
PINK = (255, 79, 160)
PINK_DARK = (196, 36, 115)
YELLOW = (255, 211, 61)
GREEN = (91, 214, 91)
INK = (27, 42, 74)
WHITE = (255, 255, 255)
TEAL = (33, 196, 167)
TEAL_DARK = (18, 128, 108)
CYAN = (29, 186, 205)
ORANGE = (242, 140, 40)
NAVY_BG = (13, 21, 40)


def rgb2bgr(c):
    return (c[2], c[1], c[0])


# ------------------------------------------------------------------ fonts
@lru_cache(maxsize=256)
def font(size: int, kind: str = "zh") -> ImageFont.FreeTypeFont:
    """kind: zh (WenDaoChaoHei, upright) | lat (Rubik-like body) | disp (Latin display) | ital (Latin display italic)"""
    name = {"zh": "WenDaoChaoHei-2.ttf", "lat": "latin_body.ttf", "disp": "latin_display.ttf", "ital": "latin_italic.ttf"}[kind]
    return ImageFont.truetype(str(FONT_DIR / name), size)


def has_cjk(s: str) -> bool:
    return any("一" <= ch <= "鿿" or "　" <= ch <= "〿" or "＀" <= ch <= "￯" for ch in s)


def text_size(text: str, size: int, kind: str = "zh", stroke: int = 0):
    f = font(size, kind)
    l, t, r, b = f.getbbox(text, stroke_width=stroke)
    return r - l, b - t


def text_layer(text: str, size: int, fill=WHITE, kind: str = "zh", stroke: int = 0, stroke_fill=INK, shadow: int = 0,
               shadow_col=(0, 0, 0), pad: int = 8, spacing: int = 6, align: str = "center") -> np.ndarray:
    """RGBA layer (H x W x 4, straight alpha) with the text, optional outline and a soft drop shadow.  Multi-line with \\n."""
    f = font(size, kind)
    lines = text.split("\n")
    widths = []
    for ln in lines:
        l, t, r, b = f.getbbox(ln, stroke_width=stroke)
        widths.append(r - l)
    lh = int(size * 1.18) + spacing
    w = max(widths) + pad * 2 + shadow * 2
    h = lh * len(lines) + pad * 2 + shadow * 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, ln in enumerate(lines):
        l, t, r, b = f.getbbox(ln, stroke_width=stroke)
        x = pad + stroke
        if align == "center":
            x = (w - (r - l)) // 2 - l
        elif align == "right":
            x = w - pad - (r - l) - l
        else:
            x = pad - l + stroke
        y = pad + i * lh - t + int(size * 0.06)
        if shadow:
            d.text((x + shadow, y + shadow), ln, font=f, fill=shadow_col + (140,), stroke_width=stroke, stroke_fill=shadow_col + (140,))
        d.text((x, y), ln, font=f, fill=tuple(fill) + (255,), stroke_width=stroke, stroke_fill=tuple(stroke_fill) + (255,))
    if shadow:
        base = np.array(img)
        a = Image.fromarray(base[:, :, 3]).filter(ImageFilter.GaussianBlur(shadow * 0.8))
        # keep the crisp text but soften the shadow part: cheap approach = composite blurred alpha underneath
        under = Image.new("RGBA", (w, h), shadow_col + (0,))
        under.putalpha(a.point(lambda v: int(v * 0.35)))
        under.alpha_composite(img)
        img = under
    return np.array(img)


def pill_layer(w: int, h: int, fill=WHITE, alpha: float = 1.0, radius: int | None = None, outline=None, outline_w: int = 0,
               shadow: int = 0, pad: int = 12, gradient=None) -> np.ndarray:
    """rounded rectangle, optional vertical gradient (top, bottom), optional outline and blurred shadow"""
    ss = 2
    radius = h // 2 if radius is None else radius
    cw, ch = w + pad * 2 + shadow * 2, h + pad * 2 + shadow * 2
    img = Image.new("RGBA", (cw * ss, ch * ss), (0, 0, 0, 0))
    x0, y0 = (pad + shadow) * ss, (pad + shadow) * ss
    box = (x0, y0, x0 + w * ss, y0 + h * ss)
    if shadow:
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle((box[0], box[1] + shadow * ss * 0.5, box[2], box[3] + shadow * ss * 0.5), radius * ss, fill=(0, 0, 0, 120))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(shadow * ss * 0.7)))
    body = Image.new("RGBA", img.size, (0, 0, 0, 0))
    if gradient:
        g = np.zeros((ch * ss, cw * ss, 4), np.uint8)
        top, bot = gradient
        for yy in range(box[1], box[3]):
            k = (yy - box[1]) / max(box[3] - box[1] - 1, 1)
            g[yy, :, :3] = [int(top[i] + (bot[i] - top[i]) * k) for i in range(3)]
            g[yy, :, 3] = 255
        gi = Image.fromarray(g)
        mask = Image.new("L", img.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle(box, radius * ss, fill=255)
        body.paste(gi, (0, 0), mask)
    else:
        ImageDraw.Draw(body).rounded_rectangle(box, radius * ss, fill=tuple(fill) + (255,))
    if alpha < 1.0:
        a = np.array(body)
        a[:, :, 3] = (a[:, :, 3] * alpha).astype(np.uint8)
        body = Image.fromarray(a)
    img.alpha_composite(body)
    if outline and outline_w:
        ImageDraw.Draw(img).rounded_rectangle(box, radius * ss, outline=tuple(outline) + (255,), width=outline_w * ss)
    img = img.resize((cw, ch), Image.LANCZOS)
    return np.array(img)


def parallelogram_layer(w: int, h: int, fill, skew: int = 36, outline=None, outline_w: int = 0, shadow: int = 10, pad: int = 14) -> np.ndarray:
    ss = 2
    cw, ch = w + skew + pad * 2 + shadow * 2, h + pad * 2 + shadow * 2
    img = Image.new("RGBA", (cw * ss, ch * ss), (0, 0, 0, 0))
    x0, y0 = (pad + shadow) * ss, (pad + shadow) * ss
    pts = [(x0 + skew * ss, y0), (x0 + (w + skew) * ss, y0), (x0 + w * ss, y0 + h * ss), (x0, y0 + h * ss)]
    if shadow:
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).polygon([(x, y + shadow * ss * 0.6) for x, y in pts], fill=(0, 0, 0, 110))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(shadow * ss * 0.6)))
    d = ImageDraw.Draw(img)
    d.polygon(pts, fill=tuple(fill) + (255,))
    if outline and outline_w:
        d.line(pts + [pts[0]], fill=tuple(outline) + (255,), width=outline_w * ss, joint="curve")
    return np.array(img.resize((cw, ch), Image.LANCZOS))


def circle_layer(d: int, fill, outline=None, outline_w: int = 0, shadow: int = 0, pad: int = 8) -> np.ndarray:
    ss = 3
    cw = d + pad * 2 + shadow * 2
    img = Image.new("RGBA", (cw * ss, cw * ss), (0, 0, 0, 0))
    c0 = (pad + shadow) * ss
    box = (c0, c0, c0 + d * ss, c0 + d * ss)
    if shadow:
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((box[0], box[1] + shadow * ss * 0.5, box[2], box[3] + shadow * ss * 0.5), fill=(0, 0, 0, 110))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(shadow * ss * 0.6)))
    dr = ImageDraw.Draw(img)
    dr.ellipse(box, fill=tuple(fill) + (255,), outline=(tuple(outline) + (255,)) if outline else None, width=outline_w * ss)
    return np.array(img.resize((cw, cw), Image.LANCZOS))


def load_rgba(path: str | Path, height: int | None = None, width: int | None = None) -> np.ndarray:
    img = Image.open(path).convert("RGBA")
    if height is not None:
        img = img.resize((max(1, round(img.width * height / img.height)), height), Image.LANCZOS)
    elif width is not None:
        img = img.resize((width, max(1, round(img.height * width / img.width))), Image.LANCZOS)
    return np.array(img)


def stack_layers(base: np.ndarray, top: np.ndarray, x: int, y: int) -> np.ndarray:
    """alpha-composite `top` onto `base` (both RGBA, straight alpha) at (x, y); grows `base` if needed.  Used while BUILDING layers."""
    b = Image.fromarray(base)
    b.alpha_composite(Image.fromarray(top), (x, y))
    return np.array(b)


def new_layer(w: int, h: int) -> np.ndarray:
    return np.zeros((h, w, 4), np.uint8)


# ------------------------------------------------------------------ easing
def clamp01(x):
    return 0.0 if x < 0 else 1.0 if x > 1 else x


def ease_out_cubic(x):
    x = clamp01(x)
    return 1 - (1 - x) ** 3


def ease_in_out(x):
    x = clamp01(x)
    return x * x * (3 - 2 * x)


def ease_out_back(x, s=1.70158):
    x = clamp01(x)
    return 1 + (s + 1) * (x - 1) ** 3 + s * (x - 1) ** 2


def ease_out_elastic(x):
    x = clamp01(x)
    if x in (0.0, 1.0):
        return x
    return 2 ** (-10 * x) * math.sin((x * 10 - 0.75) * (2 * math.pi) / 3) + 1


def ease_in_back(x, s=1.70158):
    x = clamp01(x)
    return (s + 1) * x ** 3 - s * x ** 2


def lerp(a, b, t):
    return a + (b - a) * t


# ------------------------------------------------------------------ compositor
def blit(canvas: np.ndarray, layer: np.ndarray, x: float, y: float, scale: float = 1.0, rot: float = 0.0, alpha: float = 1.0,
         anchor=(0.5, 0.5)) -> None:
    """Draw an RGBA layer (straight alpha) onto a BGR canvas (in place).  (x, y) is where `anchor` (fractions of the layer size) lands.
    Scale / rotation (degrees, clockwise) are applied around the anchor.  Only the touched bounding box is processed."""
    if alpha <= 0.002 or scale <= 0.002:
        return
    lh, lw = layer.shape[:2]
    ax, ay = anchor[0] * lw, anchor[1] * lh
    ch, cw = canvas.shape[:2]
    if rot == 0.0 and scale == 1.0:
        x0, y0 = int(round(x - ax)), int(round(y - ay))
        src = layer
        sx0 = max(0, -x0)
        sy0 = max(0, -y0)
        dx0, dy0 = max(0, x0), max(0, y0)
        w2 = min(lw - sx0, cw - dx0)
        h2 = min(lh - sy0, ch - dy0)
        if w2 <= 0 or h2 <= 0:
            return
        roi = src[sy0:sy0 + h2, sx0:sx0 + w2]
        _over(canvas, roi, dx0, dy0, alpha)
        return
    ang = math.radians(rot)
    c, s = math.cos(ang) * scale, math.sin(ang) * scale
    # corners of the transformed layer -> bbox
    corners = np.array([[0, 0], [lw, 0], [lw, lh], [0, lh]], np.float32) - np.array([ax, ay], np.float32)
    rot_m = np.array([[c, -s], [s, c]], np.float32)
    pts = corners @ rot_m.T + np.array([x, y], np.float32)
    bx0, by0 = int(max(0, math.floor(pts[:, 0].min()))), int(max(0, math.floor(pts[:, 1].min())))
    bx1, by1 = int(min(cw, math.ceil(pts[:, 0].max()))), int(min(ch, math.ceil(pts[:, 1].max())))
    if bx1 <= bx0 or by1 <= by0:
        return
    # affine map layer -> canvas bbox
    m = np.array([[c, -s, x - (c * ax - s * ay) - bx0], [s, c, y - (s * ax + c * ay) - by0]], np.float32)
    # premultiply for clean edges
    a = layer[:, :, 3:4].astype(np.float32) / 255.0
    pm = np.concatenate([layer[:, :, :3].astype(np.float32) * a, a * 255.0], axis=2)
    warped = cv2.warpAffine(pm, m, (bx1 - bx0, by1 - by0), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0))
    wa = warped[:, :, 3:4] / 255.0 * alpha
    rgb = warped[:, :, :3] / 255.0 * 255.0 * alpha          # already premultiplied by the source alpha
    roi = canvas[by0:by1, bx0:bx1].astype(np.float32)
    out = roi * (1.0 - wa) + rgb[:, :, ::-1]
    canvas[by0:by1, bx0:bx1] = np.clip(out, 0, 255).astype(np.uint8)


def _over(canvas: np.ndarray, roi_rgba: np.ndarray, dx: int, dy: int, alpha: float) -> None:
    h, w = roi_rgba.shape[:2]
    a = roi_rgba[:, :, 3:4].astype(np.float32) * (alpha / 255.0)
    dst = canvas[dy:dy + h, dx:dx + w].astype(np.float32)
    src = roi_rgba[:, :, 2::-1].astype(np.float32)
    canvas[dy:dy + h, dx:dx + w] = np.clip(dst * (1.0 - a) + src * a, 0, 255).astype(np.uint8)


def fill_rect(canvas: np.ndarray, x0, y0, x1, y1, color_rgb, alpha: float = 1.0) -> None:
    x0, y0, x1, y1 = int(max(0, x0)), int(max(0, y0)), int(min(canvas.shape[1], x1)), int(min(canvas.shape[0], y1))
    if x1 <= x0 or y1 <= y0:
        return
    roi = canvas[y0:y1, x0:x1].astype(np.float32)
    col = np.array(rgb2bgr(color_rgb), np.float32)
    canvas[y0:y1, x0:x1] = np.clip(roi * (1 - alpha) + col * alpha, 0, 255).astype(np.uint8)


def vignette(canvas: np.ndarray, strength: float = 0.35) -> None:
    ys, xs = np.ogrid[:canvas.shape[0], :canvas.shape[1]]
    d = ((xs - canvas.shape[1] / 2) / (canvas.shape[1] / 2)) ** 2 + ((ys - canvas.shape[0] / 2) / (canvas.shape[0] / 2)) ** 2
    f = 1.0 - strength * np.clip(d - 0.35, 0, 1)
    canvas[:] = np.clip(canvas.astype(np.float32) * f[:, :, None], 0, 255).astype(np.uint8)


def gradient_bg(top, bottom, w: int = W, h: int = H, angle_deg: float = 0.0) -> np.ndarray:
    """BGR gradient image"""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    a = math.radians(angle_deg)
    t = (yy * math.cos(a) + xx * math.sin(a))
    t = (t - t.min()) / max(t.max() - t.min(), 1e-6)
    top = np.array(rgb2bgr(top), np.float32)
    bot = np.array(rgb2bgr(bottom), np.float32)
    return (top[None, None, :] * (1 - t[:, :, None]) + bot[None, None, :] * t[:, :, None]).astype(np.uint8)

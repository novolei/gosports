"""Cover / thumbnail images for the GoSports promo (Bilibili 16:9 + 16:10, YouTube 1280x720).  Real game frames + the game's UI language.

  python promo/cover.py            -> promo/publish/cover_*.png / .jpg

Sources (not in git, from promo/rec*.sh): promo_work/cover/ps_full_8.05.png (the slow-mo punch), promo_work/rec/m3_sunset.avi (a sunset-venue
frame) and the Gemini sardine icon promo_work/gag_sardine.png.
"""
from __future__ import annotations

import math
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cards  # noqa: E402
import cards2  # noqa: E402
import gfx  # noqa: E402
from gfx import (BLUE, INK, ORANGE, PINK, TEAL, WHITE, YELLOW, H, W, blit, load_rgba, pill_layer, text_layer)  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "promo_work"
OUT = ROOT / "promo" / "publish"
VIOLET = (122, 92, 255)


def frame(path: Path, t: float | None = None) -> np.ndarray:
    if t is not None:
        tmp = WORK / "cover" / "_f.png"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(t), "-i", str(path), "-frames:v", "1", str(tmp)], check=True)
        path = tmp
    return cv2.imread(str(path))


def crop_to_canvas(img: np.ndarray, cx: float, cy: float, zoom: float) -> np.ndarray:
    """crop a 16:9 window (1/zoom of the image) around the normalised centre and scale it to 1920x1080"""
    h, w = img.shape[:2]
    cw, ch = w / zoom, h / zoom
    x0 = int(min(max(cx * w - cw / 2, 0), w - cw))
    y0 = int(min(max(cy * h - ch / 2, 0), h - ch))
    roi = img[y0:y0 + int(ch), x0:x0 + int(cw)]
    return cv2.resize(roi, (W, H), interpolation=cv2.INTER_AREA if roi.shape[1] > W else cv2.INTER_CUBIC)


def punch_up(img: np.ndarray, sat: float = 1.18, contrast: float = 1.08) -> np.ndarray:
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV).astype(np.float32)
    hsv[:, :, 1] = np.clip(hsv[:, :, 1] * sat, 0, 255)
    out = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2BGR)
    return cv2.convertScaleAbs(out, alpha=contrast, beta=-4)


def gradient_overlay(canvas: np.ndarray, top: float = 0.62, bottom: float = 0.0, left: float = 0.0, color=(8, 14, 34)) -> None:
    ys = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    xs = np.linspace(0, 1, W, dtype=np.float32)[None, :]
    a = np.clip(top * (1 - ys / 0.55), 0, 1) + np.clip(bottom * ((ys - 0.62) / 0.38), 0, 1) + np.clip(left * (1 - xs / 0.5), 0, 1)
    a = np.clip(a, 0, 0.85)[:, :, None]
    col = np.array(gfx.rgb2bgr(color), np.float32)
    canvas[:] = np.clip(canvas.astype(np.float32) * (1 - a) + col * a, 0, 255).astype(np.uint8)


def tlayer(text, size, fill, kind, stroke, stroke_fill=INK, shadow=10):
    return text_layer(text, size, fill, kind, stroke, stroke_fill, shadow=shadow, pad=14)


def chip(canvas, text, x, y, color, size=46, kind="zh", icon=None, rot=0.0, anchor=(0.0, 0.5)):
    tl = text_layer(text, size, WHITE, kind, 5, INK, pad=6)
    w = tl.shape[1] + 70 + (70 if icon else 0)
    pl = pill_layer(w, 86, color, radius=43, outline=WHITE, outline_w=5, shadow=12)
    lay = gfx.stack_layers(pl, tl, 12 + 35 + (70 if icon else 0), 12 + 16)
    if icon is not None:
        lay = gfx.stack_layers(lay, icon, 12 + 18, 12 + 12)
    blit(canvas, lay, x, y, rot=rot, anchor=anchor)


# ------------------------------------------------------------------ variants
def cover_gag(lang: str, size=(1920, 1080)) -> np.ndarray:
    """A: the hook - a real slow-mo punch frame + the sardine, with two big lines"""
    img = frame(WORK / "cover" / "ps_full_8.05.png")
    canvas = punch_up(crop_to_canvas(img, 0.50, 0.64, 1.30))
    gradient_overlay(canvas, top=0.78, bottom=0.55)
    # comic burst + sardine, top right
    burst = cards.burst_layer(780, YELLOW, INK, 18, 0.78)
    blit(canvas, burst, 1610, 300, rot=14, alpha=0.96)
    fish = load_rgba(WORK / "gag_sardine.png", height=420)
    blit(canvas, fish, 1630, 305, rot=-22)
    if lang == "zh":
        l1 = tlayer("裁判扔沙丁鱼", 168, WHITE, "zh", 18)
        l2 = tlayer("队友气到挥拳", 168, YELLOW, "zh", 18)
        blit(canvas, l1, 60, 150, rot=-3, anchor=(0.0, 0.5))
        blit(canvas, l2, 70, 335, rot=-3, anchor=(0.0, 0.5))
        chip(canvas, "和 Claude 聊出来的排球游戏", 70, 960, PINK, 50, "zh", rot=-2)
    else:
        l1 = tlayer("SARDINES.", 190, WHITE, "ital", 18)
        l2 = tlayer("PUNCHES.", 190, YELLOW, "ital", 18)
        blit(canvas, l1, 60, 150, rot=-3, anchor=(0.0, 0.5))
        blit(canvas, l2, 70, 345, rot=-3, anchor=(0.0, 0.5))
        chip(canvas, "A volleyball game built with Claude", 70, 960, PINK, 46, "disp", rot=-2)
    logo = load_rgba(cards.SPLASH, height=380)
    blit(canvas, logo, 1560, 870)
    return canvas


def cover_collab(lang: str, size=(1920, 1080)) -> np.ndarray:
    """B: the collaboration - 'me + Claude' over a blurred sunset-venue frame, with the numbers"""
    img = frame(WORK / "rec" / "m3_sunset.avi", 52.0)
    bg = cv2.GaussianBlur(crop_to_canvas(img, 0.5, 0.62, 1.4), (0, 0), 6)
    canvas = punch_up(bg, 1.1, 0.9)
    gradient_overlay(canvas, top=0.35, bottom=0.45, color=(10, 16, 40))
    fill_dark = np.zeros_like(canvas)
    canvas[:] = cv2.addWeighted(canvas, 0.78, fill_dark, 0.22, 0)
    # the pair: me + Claude
    if lang == "en":
        base = gfx.circle_layer(280, TEAL, outline=WHITE, outline_w=4, shadow=6)
        tt = text_layer("ME", 112, WHITE, "disp", 0, INK, pad=2)
        me = gfx.stack_layers(base, tt, (base.shape[1] - tt.shape[1]) // 2, (base.shape[0] - tt.shape[0]) // 2 - 2)
    else:
        me = cards2.avatar("me", 280)
    ai = cards2.avatar("ai", 280)
    blit(canvas, me, 560, 330)
    blit(canvas, ai, 1360, 330)
    plus = tlayer("+", 220, YELLOW, "disp", 14)
    blit(canvas, plus, 960, 320)
    if lang == "zh":
        t1 = tlayer("聊 14 轮", 190, WHITE, "zh", 18)
        t2 = tlayer("做出一款排球游戏", 130, YELLOW, "zh", 14)
        blit(canvas, t1, W / 2, 615, rot=-2)
        blit(canvas, t2, W / 2, 790, rot=-2)
        chip(canvas, "21 小时", 410, 955, TEAL, 46, "zh")
        chip(canvas, "2.5 万行代码", 790, 955, BLUE, 46, "zh")
        chip(canvas, "全程 Claude Sonnet 5.5", 1230, 955, VIOLET, 46, "zh")
    else:
        t1 = tlayer("I + CLAUDE", 190, WHITE, "ital", 16)
        t2 = tlayer("BUILT A GAME", 150, YELLOW, "ital", 14)
        blit(canvas, t1, W / 2, 615, rot=-2)
        blit(canvas, t2, W / 2, 790, rot=-2)
        chip(canvas, "21 hours", 440, 955, TEAL, 44, "disp")
        chip(canvas, "25,000+ lines", 760, 955, BLUE, 44, "disp")
        chip(canvas, "Claude Sonnet 5.5", 1230, 955, VIOLET, 44, "disp")
    logo = load_rgba(cards.SPLASH, height=260)
    blit(canvas, logo, 270, 160, rot=-6)
    return canvas


def save(img: np.ndarray, name: str, size: tuple[int, int], crop169_to: tuple[int, int] | None = None, jpg: bool = False) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    out = img
    if crop169_to is not None:                       # 16:10 -> centre crop of the 16:9 design (the safe zone is the middle 90 %)
        cw = int(round(H * crop169_to[0] / crop169_to[1]))
        x0 = (W - cw) // 2
        out = img[:, x0:x0 + cw]
    out = cv2.resize(out, size, interpolation=cv2.INTER_AREA)
    if jpg:
        cv2.imwrite(str(OUT / f"{name}.jpg"), out, [cv2.IMWRITE_JPEG_QUALITY, 92])
    else:
        cv2.imwrite(str(OUT / f"{name}.png"), out)
    print("wrote", name, out.shape[1], "x", out.shape[0])


def main():
    zh_a, zh_b = cover_gag("zh"), cover_collab("zh")
    en_a, en_b = cover_gag("en"), cover_collab("en")
    save(zh_a, "bilibili_cover_A_gag_1920x1080", (1920, 1080))
    save(zh_b, "bilibili_cover_B_collab_1920x1080", (1920, 1080))
    save(zh_a, "bilibili_cover_A_gag_1146x717", (1146, 717), crop169_to=(1146, 717))
    save(zh_b, "bilibili_cover_B_collab_1146x717", (1146, 717), crop169_to=(1146, 717))
    save(en_a, "youtube_thumbnail_A_gag_1280x720", (1280, 720), jpg=True)
    save(en_b, "youtube_thumbnail_B_collab_1280x720", (1280, 720), jpg=True)


if __name__ == "__main__":
    main()

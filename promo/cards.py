"""Graphic cards and overlays for the GoSports promo (all in 1920x1080 coordinates, game UI language)."""
from __future__ import annotations

import math
import random
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

import gfx
from gfx import (BLUE, BLUE_DARK, CYAN, GREEN, INK, NAVY_BG, ORANGE, PINK, PINK_DARK, TEAL, TEAL_DARK, WHITE, YELLOW, H, W, blit,
                 circle_layer, ease_in_out, ease_out_back, ease_out_cubic, ease_out_elastic, fill_rect, lerp, load_rgba, pill_layer,
                 text_layer)

ROOT = Path(__file__).resolve().parents[1]
SPLASH = ROOT / "assets" / "ui" / "splash.png"
ICON = ROOT / "assets" / "brand" / "icon_win.png"
UI = ROOT / "assets" / "ui"
MONO = "C:/Windows/Fonts/consola.ttf"
MONO_B = "C:/Windows/Fonts/consolab.ttf"


# ------------------------------------------------------------------ backgrounds
_BG_CACHE: dict = {}


def bg_sport(t: float, top=TEAL, bottom=BLUE, stripe_alpha: float = 0.10) -> np.ndarray:
    """teal -> blue gradient with slowly drifting diagonal stripes (the game's menu look)"""
    key = ("sport", top, bottom)
    if key not in _BG_CACHE:
        _BG_CACHE[key] = gfx.gradient_bg(top, bottom, angle_deg=18)
    bg = _BG_CACHE[key].copy()
    ph = (t * 60.0) % 160.0
    ys, xs = np.mgrid[0:H:2, 0:W:2]
    s = (((xs + ys * 0.55 + ph) % 160) < 56).astype(np.float32)
    s = cv2.resize(s, (W, H), interpolation=cv2.INTER_NEAREST)
    bg = np.clip(bg.astype(np.float32) + s[:, :, None] * 255 * stripe_alpha, 0, 255).astype(np.uint8)
    return bg


def bg_dark(t: float, glow=(TEAL, PINK)) -> np.ndarray:
    key = ("dark",)
    if key not in _BG_CACHE:
        _BG_CACHE[key] = gfx.gradient_bg((16, 26, 52), (8, 12, 28), angle_deg=8)
    bg = _BG_CACHE[key].copy()
    # soft drifting glow orbs
    for i, c in enumerate(glow):
        cx = W * (0.25 + 0.5 * i) + math.sin(t * 0.35 + i * 2.1) * 140
        cy = H * (0.35 + 0.3 * i) + math.cos(t * 0.3 + i) * 90
        key2 = ("orb", c)
        if key2 not in _BG_CACHE:
            ys, xs = np.mgrid[0:540, 0:960].astype(np.float32)
            d = np.sqrt((xs - 480) ** 2 + (ys - 270) ** 2) / 480.0
            _BG_CACHE[key2] = np.clip(1 - d, 0, 1) ** 2.2
        orb = cv2.resize(_BG_CACHE[key2], (1100, 620))
        x0, y0 = int(cx - 550), int(cy - 310)
        ox0, oy0 = max(0, -x0), max(0, -y0)
        x1, y1 = min(W, x0 + 1100), min(H, y0 + 620)
        if x1 > max(0, x0) and y1 > max(0, y0):
            sub = orb[oy0:oy0 + (y1 - max(0, y0)), ox0:ox0 + (x1 - max(0, x0))]
            col = np.array(gfx.rgb2bgr(c), np.float32)
            roi = bg[max(0, y0):y1, max(0, x0):x1].astype(np.float32)
            bg[max(0, y0):y1, max(0, x0):x1] = np.clip(roi + sub[:, :, None] * col * 0.30, 0, 255).astype(np.uint8)
    # dot grid
    ys, xs = np.mgrid[0:H:48, 0:W:48]
    for y, x in zip(ys.ravel(), xs.ravel()):
        cv2.circle(bg, (int(x + 24), int(y + 24)), 2, (60, 70, 100), -1)
    return bg


# ------------------------------------------------------------------ small drawing helpers (PIL on a BGR canvas via layers)
LANG = "zh"                       # "zh" or "en": the English cut shows English card titles (TR) and drops duplicated captions (HIDE_EN)

TR = {
    "它会自己看图验证": "IT CHECKS ITS OWN SCREENSHOTS", "运行游戏，录一串画面": "Runs the game, records frames", "自己看图：动作对不对？": "Looks at them: does it move right?",
    "发现问题 → 修 → 再验证": "Spots a problem → fixes → re-checks", "每一轮，它都这样收尾": "EVERY ROUND ENDS LIKE THIS",
    "编译检查": "Compile check", "中英文校验": "Translation check", "回归测试": "Regression runs", "加密打包": "Encrypted build", "装进手机": "Phone install",
    "一个人，加一个 Claude": "ONE PERSON + ONE CLAUDE", "小时": "HOURS", "行代码": "LINES OF CODE", "节设计文档": "DESIGN-DOC SECTIONS", "次工具调用": "TOOL CALLS",
    "十四轮对话": "FOURTEEN ROUNDS OF CONVERSATION", "写 → 跑 → 看 → 改": "WRITE → RUN → LOOK → FIX",
    "说一句人话": "Say it in plain words", "写代码": "Writes code", "运行游戏": "Runs the game", "截图 · 看图": "Screenshot · look", "发现问题 → 修好": "Spot it → fix it",
    "我只负责说：哪里不对劲": "I just say what feels off", "下一款：并行开发中": "THE NEXT GAME, IN PARALLEL",
    "动画": "Animation", "界面": "UI", "美术": "Art", "场馆": "Venue", "音效": "Sound", "整合": "Main line", "特效": "Effects", "音乐": "Music",
    "各自一个分支  ·  互不污染": "Each on its own branch · no cross-contamination",
    "GoSports 系列": "THE GOSPORTS SERIES", "排球": "VOLLEYBALL", "乒乓球": "TABLE TENNIS", "足球": "FOOTBALL", "沙狐球": "SHUFFLEBOARD",
    "已上线": "PLAYABLE NOW", "即将到来": "COMING SOON", "全都是代码生成的": "ALL GENERATED IN CODE",
    "第 13 轮": "Round 13", "我的原话": "my own words", "实现效果": "In the game",
    "读懂需求，设计「队友内讧」": "Reads the request, designs the falling-out", "写代码：怒气标记、投掷、挥拳": "Writes code: anger mark, throw, punch",
    "运行游戏，录下画面自检": "Runs the game, records and checks", "两对两  卡通排球": "2-ON-2 CARTOON VOLLEYBALL",
    "搞怪环节": "GAG TIME!", "GAG TIME!": "umpire props · angry partners",
    "由 Claude Sonnet 5.5 协作开发": "Built in collaboration with Claude Sonnet 5.5",
}
HIDE_EN = {"Claude takes screenshots and looks at them itself", "14 rounds of conversation", "The next game is being built in parallel Claude sessions",
           "THE GOSPORTS SERIES", "VOLLEYBALL", "TABLE TENNIS", "FOOTBALL", "SHUFFLEBOARD", "PLAYABLE NOW", "COMING SOON", "IN PROGRESS",
           "Built in collaboration with Claude Sonnet 5.5", "branch · animation", "branch · UI", "branch · art", "branch · venue", "branch · audio", "branch · main line",
           "lines of code", "design-doc sections", "tool calls", "pose specs → baked clips", "particles · speed lines",
           "31 synthesised sounds", "two themes in numpy", "every pill, ribbon, card"}


def draw_text_on(canvas, text, x, y, size, fill=WHITE, kind="zh", stroke=0, stroke_fill=INK, anchor=(0.0, 0.5), alpha=1.0, shadow=0, scale=1.0):
    if LANG == "en":
        if text in HIDE_EN:
            return
        if text in TR:
            text = TR[text]
            if kind == "zh":
                kind = "disp"
                size = int(size * 0.80)
    key = (text, size, tuple(fill), kind, stroke, tuple(stroke_fill), shadow)
    if key not in _BG_CACHE:
        _BG_CACHE[key] = text_layer(text, size, fill, kind, stroke, stroke_fill, shadow=shadow)
    blit(canvas, _BG_CACHE[key], x, y, scale=scale, alpha=alpha, anchor=anchor)


def mono_layer(text: str, size: int, fill, bold=False) -> np.ndarray:
    f = ImageFont.truetype(MONO_B if bold else MONO, size)
    l, t, r, b = f.getbbox(text)
    img = Image.new("RGBA", (r - l + 6, int(size * 1.35)), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((3 - l, 2), text, font=f, fill=tuple(fill) + (255,))
    return np.array(img)


def cached(key, fn):
    if key not in _BG_CACHE:
        _BG_CACHE[key] = fn()
    return _BG_CACHE[key]


def icon(name: str, size: int, tint=None) -> np.ndarray:
    def mk():
        a = load_rgba(UI / name, height=size)
        if tint is not None:
            a[:, :, 0], a[:, :, 1], a[:, :, 2] = tint
        return a
    return cached(("icon", name, size, tint), mk)


# ------------------------------------------------------------------ logo / end card
def sparkle_layer(size: int, color=WHITE) -> np.ndarray:
    ss = 4
    s = size * ss
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s / 2
    pts = []
    for i in range(8):
        r = c if i % 2 == 0 else c * 0.22
        a = math.pi / 4 * i - math.pi / 2
        pts.append((c + r * math.cos(a), c + r * math.sin(a)))
    d.polygon(pts, fill=tuple(color) + (255,))
    return np.array(img.resize((size, size), Image.LANCZOS))


class Confetti:
    def __init__(self, n=60, seed=3):
        r = random.Random(seed)
        cols = [YELLOW, PINK, WHITE, CYAN, ORANGE, GREEN]
        self.p = [dict(x=r.uniform(0, W), y=r.uniform(-H, 0), vy=r.uniform(120, 340), vx=r.uniform(-60, 60), rot=r.uniform(0, 360),
                       vr=r.uniform(-240, 240), w=r.randint(10, 22), h=r.randint(6, 12), c=r.choice(cols), ph=r.uniform(0, 6.28)) for _ in range(n)]

    def draw(self, canvas, t):
        for q in self.p:
            y = (q["y"] + q["vy"] * t) % (H + 200) - 100
            x = q["x"] + q["vx"] * t + math.sin(t * 2 + q["ph"]) * 30
            key = ("conf", q["c"], q["w"], q["h"])
            if key not in _BG_CACHE:
                lay = np.zeros((q["h"] + 4, q["w"] + 4, 4), np.uint8)
                lay[2:-2, 2:-2, :3] = q["c"]
                lay[2:-2, 2:-2, 3] = 255
                _BG_CACHE[key] = lay
            blit(canvas, _BG_CACHE[key], x % W, y, rot=q["rot"] + q["vr"] * t, alpha=0.9)


_CONFETTI = Confetti()


def logo_card(canvas: np.ndarray, t: float, dur: float, with_tagline: bool = True) -> None:
    """the Go Sports logo pops onto the teal court background, with a burst of sparkles and confetti"""
    canvas[:] = bg_sport(t)
    _CONFETTI.draw(canvas, t)
    logo = cached(("logo", 640), lambda: load_rgba(SPLASH, height=720))
    # burst rays behind the logo
    u = gfx.clamp01(t / 0.6)
    if u < 1:
        for i in range(14):
            a = math.radians(i * 360 / 14 + 8)
            r0, r1 = 120 + 500 * ease_out_cubic(u), 220 + 700 * ease_out_cubic(u)
            cv2.line(canvas, (int(W / 2 + math.cos(a) * r0), int(H * 0.46 + math.sin(a) * r0)),
                     (int(W / 2 + math.cos(a) * r1), int(H * 0.46 + math.sin(a) * r1)), (255, 255, 255), 6, cv2.LINE_AA)
    s = ease_out_elastic(gfx.clamp01(t / 0.9))
    blit(canvas, logo, W / 2, H * 0.47 + math.sin(t * 2.4) * 6, scale=max(s, 0.01) * 1.12, alpha=gfx.clamp01(t / 0.2))
    spk = cached(("spk", 90), lambda: sparkle_layer(90, WHITE))
    for i, (dx, dy, ph) in enumerate(((-520, -250, 0.0), (500, -180, 1.1), (430, 230, 2.0), (-470, 210, 3.0))):
        k = 0.5 + 0.5 * math.sin(t * 3 + ph)
        blit(canvas, spk, W / 2 + dx, H * 0.47 + dy, scale=0.5 + 0.7 * k, rot=t * 40, alpha=0.9 * gfx.clamp01(t - 0.4))
    if with_tagline:
        a = gfx.clamp01((t - 0.9) / 0.4)
        y = H * 0.86 + (1 - ease_out_cubic(a)) * 30
        draw_text_on(canvas, "两对两  卡通排球", W / 2, y, 56, WHITE, "zh", stroke=7, stroke_fill=BLUE_DARK, anchor=(0.5, 0.5), alpha=a, shadow=6)


def _cta_icon(kind: str, d: int) -> np.ndarray:
    """small flat pictograms for the follow / subscribe / triple-combo reminder (drawn here)"""
    def mk():
        ss = 3
        s = d * ss
        img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        dr = ImageDraw.Draw(img)
        c = s / 2
        ink = (27, 42, 74, 255)
        lw = int(s * 0.05)
        if kind == "follow":          # a plus in a circle
            dr.ellipse((s * 0.08, s * 0.08, s * 0.92, s * 0.92), fill=(47, 168, 255, 255), outline=ink, width=lw)
            dr.rectangle((c - s * 0.07, s * 0.25, c + s * 0.07, s * 0.75), fill=(255, 255, 255, 255))
            dr.rectangle((s * 0.25, c - s * 0.07, s * 0.75, c + s * 0.07), fill=(255, 255, 255, 255))
        elif kind == "subscribe":     # a bell
            dr.pieslice((s * 0.2, s * 0.12, s * 0.8, s * 0.72), 180, 360, fill=(255, 211, 61, 255), outline=ink, width=lw)
            dr.rectangle((s * 0.2, s * 0.42, s * 0.8, s * 0.72), fill=(255, 211, 61, 255))
            dr.line([(s * 0.2, s * 0.42), (s * 0.2, s * 0.72)], fill=ink, width=lw)
            dr.line([(s * 0.8, s * 0.42), (s * 0.8, s * 0.72)], fill=ink, width=lw)
            dr.rounded_rectangle((s * 0.1, s * 0.68, s * 0.9, s * 0.8), int(s * 0.05), fill=(255, 211, 61, 255), outline=ink, width=lw)
            dr.ellipse((c - s * 0.1, s * 0.78, c + s * 0.1, s * 0.94), fill=ink)
        else:                         # triple combo: heart
            pts = []
            for i in range(0, 361, 6):
                a_ = math.radians(i)
                x = 16 * math.sin(a_) ** 3
                y = -(13 * math.cos(a_) - 5 * math.cos(2 * a_) - 2 * math.cos(3 * a_) - math.cos(4 * a_))
                pts.append((c + x * s * 0.026, c + y * s * 0.026 - s * 0.02))
            dr.polygon(pts, fill=(255, 79, 160, 255), outline=ink, width=lw)
            dr.ellipse((s * 0.27, s * 0.22, s * 0.40, s * 0.34), fill=(255, 255, 255, 190))
        return np.array(img.resize((d, d), Image.LANCZOS))
    return cached(("ctaicon", kind, d), mk)


def end_card(canvas: np.ndarray, t: float, dur: float, t_cta: float = 99.0, en: bool = False) -> None:
    """closing card: logo, who built it, the sport list, and (from t_cta on) the follow / subscribe / triple-combo reminder"""
    canvas[:] = bg_dark(t)
    _CONFETTI.draw(canvas, t * 0.5)
    fill_rect(canvas, 0, 0, W, H, (8, 12, 28), 0.35)
    ic = cached(("endicon", 260), lambda: load_rgba(ICON, height=260))
    s = ease_out_back(gfx.clamp01(t / 0.6))
    blit(canvas, ic, W / 2, 200, scale=max(s, 0.01), alpha=gfx.clamp01(t / 0.2))
    a = gfx.clamp01((t - 0.4) / 0.5)
    draw_text_on(canvas, "GoSports", W / 2, 400, 150, WHITE, "ital", stroke=10, stroke_fill=INK, anchor=(0.5, 0.5), alpha=a, shadow=10)
    a = gfx.clamp01((t - 0.9) / 0.5)
    draw_text_on(canvas, "Built in collaboration with Claude Sonnet 5.5" if en else "由 Claude Sonnet 5.5 协作开发", W / 2, 520, 56 if not en else 44, YELLOW,
                 "lat" if en else "zh", stroke=6 if not en else 0, stroke_fill=INK, anchor=(0.5, 0.5), alpha=a)
    if not en:
        draw_text_on(canvas, "Built in collaboration with Claude Sonnet 5.5", W / 2, 580, 30, (200, 225, 235), "lat", anchor=(0.5, 0.5), alpha=a)
    a = gfx.clamp01((t - 1.4) / 0.5)
    draw_text_on(canvas, "VOLLEYBALL  ·  TABLE TENNIS  ·  FOOTBALL  ·  SHUFFLEBOARD" if en else "排球  ·  乒乓球  ·  足球  ·  沙狐球", W / 2, 668, 30 if en else 50,
                 (200, 225, 235) if en else WHITE, "lat" if en else "zh", stroke=0 if en else 5, stroke_fill=INK, anchor=(0.5, 0.5), alpha=a)
    # the reminder
    items = [("follow", "关注", "FOLLOW", 0.0), ("subscribe", "订阅", "SUBSCRIBE", 0.9), ("heart", "三连", "LIKE · COIN · SAVE", 1.9)]
    bw, bh, gap = 470, 150, 40
    x0 = W / 2 - (3 * bw + 2 * gap) / 2
    for i, (kind, zh, en_t, dt) in enumerate(items):
        k = gfx.clamp01((t - t_cta - dt) / 0.5)
        if k <= 0:
            continue
        col = (47, 168, 255) if kind == "follow" else ((255, 150, 40) if kind == "subscribe" else PINK)
        card = cached(("ctacard", bw, bh, col), lambda col=col: pill_layer(bw, bh, col, radius=75, outline=WHITE, outline_w=5, shadow=14))
        cx = x0 + i * (bw + gap) + bw / 2
        cy = 850 + (1 - ease_out_cubic(k)) * 90
        pulse = 1.0 + 0.04 * math.sin((t - t_cta) * 5 + i) if k >= 1 else ease_out_back(k)
        blit(canvas, card, cx, cy, scale=pulse, alpha=k)
        blit(canvas, _cta_icon(kind if kind != "heart" else "triple", 92), cx - bw / 2 + 85, cy, scale=pulse, alpha=k)
        if en:
            draw_text_on(canvas, en_t.split(" · ")[0] if kind != "heart" else "TRIPLE-COMBO", cx + 45, cy - 6, 44 if kind != "heart" else 36, WHITE, "lat", stroke=4, stroke_fill=INK, anchor=(0.5, 0.5), alpha=k, scale=pulse)
            draw_text_on(canvas, "LIKE · COIN · SAVE" if kind == "heart" else "", cx + 45, cy + 40, 22, (255, 240, 245), "lat", anchor=(0.5, 0.5), alpha=k)
        else:
            draw_text_on(canvas, zh, cx + 45, cy - 14, 62, WHITE, "zh", stroke=6, stroke_fill=INK, anchor=(0.5, 0.5), alpha=k, scale=pulse)
            draw_text_on(canvas, en_t, cx + 45, cy + 42, 24, (255, 255, 255), "lat", anchor=(0.5, 0.5), alpha=k)


# ------------------------------------------------------------------ feature chip (lower third)
def feature_chip(zh: str, en: str, icon_name: str | None = None, color=TEAL, width: int | None = None, en_title: bool = False) -> np.ndarray:
    """a tilted ribbon with an optional pictogram, Chinese title + English subtitle (like the game's own plates)"""
    tkind, tsize = ("disp", 44) if en_title else ("zh", 52)
    zh_w, zh_h = gfx.text_size(zh, tsize, tkind, 6)
    en_w, en_h = gfx.text_size(en, 26, "lat", 0)
    inner_w = max(zh_w, en_w + 8)
    pad_l = 40 + (92 if icon_name else 0)
    w = width or (pad_l + inner_w + 70)
    h = 118
    base = gfx.parallelogram_layer(w, h, color, skew=34, outline=WHITE, outline_w=5, shadow=12)
    out = gfx.new_layer(base.shape[1], base.shape[0])
    out = gfx.stack_layers(out, base, 0, 0)
    ox = 14 + 12
    if icon_name:
        c = circle_layer(86, WHITE, outline=None, shadow=0)
        out = gfx.stack_layers(out, c, 28 + 34, 14 + 12 + 14)
        ic = icon(icon_name, 62, tint=color)
        out = gfx.stack_layers(out, ic, 28 + 34 + 4 + 12, 14 + 12 + 14 + 12)
    t1 = text_layer(zh, tsize, WHITE, tkind, 6, TEAL_DARK if color == TEAL else INK)
    out = gfx.stack_layers(out, t1, pad_l + 34 - 6, 14 + 12 - 2)
    t2 = text_layer(en, 26, (230, 250, 245), "lat", 0, INK, pad=4)
    out = gfx.stack_layers(out, t2, pad_l + 34 - 4, 14 + 12 + 66)
    return out


# ------------------------------------------------------------------ subtitles
def subtitle_layer(zh: str, en: str | None, primary_en: bool = False) -> np.ndarray:
    if primary_en:                      # the English cut: one larger English line (or two)
        return text_layer(zh, 50, WHITE, "lat", 6, (10, 24, 52), shadow=5, pad=6)
    zl = text_layer(zh, 54, WHITE, "zh", 7, (10, 24, 52), shadow=6, pad=6)
    parts = [zl]
    if en:
        el = text_layer(en, 31, (214, 240, 250), "lat", 4, (10, 24, 52), shadow=4, pad=6)
        parts.append(el)
    w = max(p.shape[1] for p in parts)
    h = sum(p.shape[0] for p in parts) - 4 * (len(parts) - 1)
    out = gfx.new_layer(w, h)
    y = 0
    for p in parts:
        out = gfx.stack_layers(out, p, (w - p.shape[1]) // 2, y)
        y += p.shape[0] - 4
    return out


def bottom_gradient(alpha: float = 0.55, height: int = 300) -> np.ndarray:
    lay = np.zeros((height, W, 4), np.uint8)
    lay[:, :, :3] = (6, 14, 30)
    lay[:, :, 3] = (np.linspace(0, 1, height) ** 1.6 * 255 * alpha).astype(np.uint8)[:, None]
    return lay


# ------------------------------------------------------------------ chapter card: the gag moments
def burst_layer(d: int, color, outline=INK, spikes: int = 16, inner: float = 0.72) -> np.ndarray:
    """a comic starburst (spiky circle)"""
    ss = 2
    s = d * ss
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    c = s / 2
    pts = []
    for i in range(spikes * 2):
        r = c * (0.98 if i % 2 == 0 else inner)
        a = math.pi * i / spikes
        pts.append((c + r * math.cos(a), c + r * math.sin(a)))
    dr.polygon(pts, fill=tuple(color) + (255,), outline=tuple(outline) + (255,), width=10)
    return np.array(img.resize((d, d), Image.LANCZOS))


def gag_title_card(canvas: np.ndarray, t: float, dur: float) -> None:
    canvas[:] = bg_sport(t * 1.6, top=(255, 120, 170), bottom=(255, 170, 60), stripe_alpha=0.12)
    # halftone dots
    ys, xs = np.mgrid[0:H:44, 0:W:44]
    for y, x in zip(ys.ravel(), xs.ravel()):
        if (x * 7 + y * 3) % 5 < 2:
            cv2.circle(canvas, (int(x + (y // 44 % 2) * 22), int(y)), 6, (255, 255, 255), -1, cv2.LINE_AA)
    k = ease_out_elastic(gfx.clamp01(t / 0.5))
    b1 = cached(("burst", 1500), lambda: burst_layer(1500, YELLOW, INK, 18, 0.78))
    blit(canvas, b1, W / 2, H / 2, scale=0.62 * max(k, 0.01), rot=t * 22, alpha=0.95)
    b2 = cached(("burst2", 1200), lambda: burst_layer(1200, (255, 255, 255), INK, 14, 0.8))
    blit(canvas, b2, W / 2, H / 2, scale=0.5 * max(k, 0.01), rot=-t * 30, alpha=0.9)
    fish = cached(("gagfish", 460), lambda: load_rgba(ROOT / "promo_work" / "gag_sardine.png", height=460))
    blit(canvas, fish, W / 2 + 330, H / 2 - 40 + math.sin(t * 9) * 14, scale=max(k, 0.01), rot=-18 + math.sin(t * 7) * 8)
    shake = 6 * max(0.0, 1 - t / 0.5) * math.sin(t * 90)
    draw_text_on(canvas, "搞怪环节", W / 2 - 120 + shake, H / 2 - 30, 190, WHITE, "zh", stroke=18, stroke_fill=INK, anchor=(0.5, 0.5), alpha=gfx.clamp01(t / 0.15), shadow=14, scale=max(k, 0.01))
    draw_text_on(canvas, "GAG TIME!", W / 2 - 120, H / 2 + 150, 100, YELLOW, "ital", stroke=12, stroke_fill=INK, anchor=(0.5, 0.5), alpha=gfx.clamp01((t - 0.12) / 0.15), shadow=10, scale=max(k, 0.01))

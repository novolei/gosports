"""Story cards for the 'how it was made' part of the promo: chat, self-check, terminal, stats, parallel branches, series teaser."""
from __future__ import annotations

import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

import cards
import gfx
from cards import bg_dark, bg_sport, cached, draw_text_on, icon, mono_layer
from gfx import (BLUE, BLUE_DARK, CYAN, GREEN, INK, ORANGE, PINK, PINK_DARK, TEAL, TEAL_DARK, WHITE, YELLOW, H, W, blit, clamp01,
                 ease_in_out, ease_out_back, ease_out_cubic, ease_out_elastic, fill_rect, lerp, pill_layer, text_layer)

ROOT = Path(__file__).resolve().parents[1]
GREY = (150, 170, 190)


# ------------------------------------------------------------------ helpers
def wrap_zh(text: str, n: int) -> str:
    """hard wrap a CJK / mixed string at n characters, preferring to break after punctuation"""
    out, line = [], ""
    for ch in text:
        line += ch
        if len(line) >= n and ch in "，。；：、！？ ,.;:":
            out.append(line)
            line = ""
        elif len(line) >= n + 4:
            out.append(line)
            line = ""
    if line:
        out.append(line)
    return "\n".join(out)


def panel(w: int, h: int, fill=(22, 34, 62), radius: int = 30, outline=(60, 80, 120), alpha: float = 0.96, shadow: int = 22) -> np.ndarray:
    return cached(("panel", w, h, fill, radius, outline, alpha, shadow),
                  lambda: pill_layer(w, h, fill, alpha=alpha, radius=radius, outline=outline, outline_w=3 if outline else 0, shadow=shadow))


def avatar(kind: str, d: int = 96) -> np.ndarray:
    """round avatars: 'me' (teal, 我) and 'ai' (violet sparkle, drawn here - not any company's logo)"""
    def mk():
        base = gfx.circle_layer(d, (TEAL if kind == "me" else (122, 92, 255)), outline=WHITE, outline_w=4, shadow=6)
        if kind == "me":
            t = text_layer("我", int(d * 0.52), WHITE, "zh", 0, INK, pad=2)
            return gfx.stack_layers(base, t, (base.shape[1] - t.shape[1]) // 2, (base.shape[0] - t.shape[0]) // 2 - 2)
        sp = cards.sparkle_layer(int(d * 0.62), WHITE)
        return gfx.stack_layers(base, sp, (base.shape[1] - sp.shape[1]) // 2, (base.shape[0] - sp.shape[0]) // 2)
    return cached(("avatar", kind, d), mk)


def check_layer(d: int = 40, color=GREEN) -> np.ndarray:
    def mk():
        ss = 4
        s = d * ss
        img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        dr = ImageDraw.Draw(img)
        dr.ellipse((0, 0, s - 1, s - 1), fill=tuple(color) + (255,))
        dr.line([(s * 0.26, s * 0.52), (s * 0.44, s * 0.70), (s * 0.76, s * 0.32)], fill=(255, 255, 255, 255), width=int(s * 0.12), joint="curve")
        return np.array(img.resize((d, d), Image.LANCZOS))
    return cached(("check", d, color), mk)


def phone_frame(screenshot_path: str | Path, w: int = 760) -> np.ndarray:
    """a landscape phone (rounded bezel) around a screenshot"""
    def mk():
        sc = Image.open(screenshot_path).convert("RGB")
        iw = w
        ih = int(iw * sc.height / sc.width)
        bez = 18
        out = Image.new("RGBA", (iw + bez * 2 + 24, ih + bez * 2 + 24), (0, 0, 0, 0))
        d = ImageDraw.Draw(out)
        d.rounded_rectangle((12, 14, 12 + iw + bez * 2, 14 + ih + bez * 2), 44, fill=(10, 12, 20, 255), outline=(90, 100, 130, 255), width=3)
        scr = sc.resize((iw, ih), Image.LANCZOS)
        mask = Image.new("L", scr.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, iw - 1, ih - 1), 30, fill=255)
        out.paste(scr, (12 + bez, 14 + bez), mask)
        return np.array(out)
    return cached(("phone", str(screenshot_path), w), mk)


def counter_text(x: float, fmt: str = "{:,}") -> str:
    return fmt.format(int(round(x)))


# ------------------------------------------------------------------ chat card (a request -> the result)
def chat_scene(user_text: str, claude_steps: list[str], round_tag: str, result_hint: str = "", user_sub: str = ""):
    """returns fn(canvas, t, dur) for a Procedural item.  Phase 1: the request is typed into a chat bubble; phase 2: Claude's steps tick off."""
    def fn(canvas, t, dur):
        canvas[:] = bg_dark(t)
        # header
        a = clamp01(t / 0.4)
        tag = cached(("tag", round_tag), lambda: pill_layer(250, 64, PINK, radius=32, outline=WHITE, outline_w=4, shadow=8))
        blit(canvas, tag, 170 + (1 - ease_out_cubic(a)) * -80, 120, alpha=a)
        draw_text_on(canvas, round_tag, 170 + (1 - ease_out_cubic(a)) * -80, 120, 36, WHITE, "zh", anchor=(0.5, 0.5), alpha=a)
        # user bubble (right side)
        t0 = 0.5
        cps = 22.0
        n_chars = int(clamp01((t - t0) / (len(user_text) / cps)) * len(user_text))
        shown = user_text[:n_chars]
        en_ = cards.LANG == "en"
        kind_, wrap_n, fsz = ("lat", 30, 40) if en_ else ("zh", 20, 46)
        wrapped = wrap_zh(user_text, wrap_n)
        full = text_layer(wrapped, fsz, WHITE, kind_, 0, INK, pad=18, spacing=10, align="left")
        bw, bh = full.shape[1] + 40, full.shape[0] + 30
        if t > t0 - 0.05:
            bub = cached(("ubub", bw, bh), lambda: pill_layer(bw, bh, TEAL, radius=44, shadow=12))
            s = ease_out_back(clamp01((t - t0 + 0.05) / 0.35))
            bx, by = 1830 - bw / 2, 330
            blit(canvas, bub, bx, by, scale=max(s, 0.01), alpha=clamp01((t - t0 + 0.05) / 0.2))
            av = avatar("me")
            blit(canvas, av, 1830 + 18, by - bh / 2 - 8, scale=max(s, 0.01))
            # the typed part
            wr = wrap_zh(user_text, wrap_n).split("\n")
            consumed = 0
            ty = by - bh / 2 + 24
            for ln in wr:
                part = ln[:max(0, n_chars - consumed)]
                consumed += len(ln)
                if part:
                    tl = cached(("ut", part), lambda part=part: text_layer(part, fsz, WHITE, kind_, 0, INK, pad=4, align="left"))
                    blit(canvas, tl, 1830 - bw + 20 + 4, ty, anchor=(0.0, 0.0))
                ty += fsz * 1.18 + 10
            if user_sub:
                a2 = clamp01((t - t0 - 1.0) / 0.5)
                draw_text_on(canvas, user_sub, 1830, by + bh / 2 + 36, 28, GREY, "zh", anchor=(1.0, 0.5), alpha=a2)
        # Claude reply (left side), steps tick off one by one
        t1 = t0 + len(user_text) / cps + 0.5
        if t > t1:
            s = ease_out_back(clamp01((t - t1) / 0.35))
            rw, rh = 880, 150 + 78 * len(claude_steps)
            bub = cached(("cbub", rw, rh), lambda: pill_layer(rw, rh, (34, 48, 86), radius=40, outline=(122, 92, 255), outline_w=3, shadow=14))
            cx, cy = 140 + rw / 2, 640 + rh / 2 - 130
            blit(canvas, bub, cx, cy, scale=max(s, 0.01), alpha=clamp01((t - t1) / 0.2))
            blit(canvas, avatar("ai"), 140 + 6, cy - rh / 2 - 6, scale=max(s, 0.01))
            if s > 0.9:
                draw_text_on(canvas, "Claude Sonnet 5.5", 140 + 80, cy - rh / 2 + 44, 36, (200, 190, 255), "lat", anchor=(0.0, 0.5))
                for i, st in enumerate(claude_steps):
                    ts = t1 + 0.5 + i * 0.55
                    if t < ts:
                        break
                    k = clamp01((t - ts) / 0.25)
                    y = cy - rh / 2 + 130 + i * 78
                    blit(canvas, check_layer(46), 140 + 60, y, scale=ease_out_back(k), alpha=k)
                    draw_text_on(canvas, st, 140 + 110, y, 44, WHITE, "zh", anchor=(0.0, 0.5), alpha=k)
        if result_hint and t > t1 + 0.5 + len(claude_steps) * 0.55:
            k = clamp01((t - (t1 + 0.5 + len(claude_steps) * 0.55)) / 0.4)
            draw_text_on(canvas, result_hint, W / 2, 1010, 40, YELLOW, "zh", stroke=5, stroke_fill=INK, anchor=(0.5, 0.5), alpha=k)
    return fn


# ------------------------------------------------------------------ self-check card (screenshots -> verdict)
def selfcheck_scene(sheet_path: str, notes: list[tuple[str, float]], title: str = "它会自己看图验证"):
    """a screenshot contact sheet inside a 'monitor' that slowly pushes in, with a checklist; notes = [(text, appear_time)]"""
    def fn(canvas, t, dur):
        canvas[:] = bg_dark(t)
        a = clamp01(t / 0.4)
        draw_text_on(canvas, title, 120, 100, 64, WHITE, "zh", stroke=6, stroke_fill=INK, anchor=(0.0, 0.5), alpha=a)
        draw_text_on(canvas, "Claude takes screenshots and looks at them itself", 124, 168, 30, GREY, "lat", anchor=(0.0, 0.5), alpha=a)
        # monitor
        mw, mh = 1080, 620
        mon = panel(mw, mh, fill=(10, 14, 26), outline=(90, 110, 160), radius=34, alpha=1.0, shadow=28)
        s = ease_out_back(clamp01((t - 0.2) / 0.5))
        mx, my = 100 + mw / 2 + 0, 260 + mh / 2
        blit(canvas, mon, mx, my, scale=max(s, 0.01))
        sheet = cached(("sheet", sheet_path), lambda: cv2.cvtColor(np.array(Image.open(sheet_path).convert("RGB")), cv2.COLOR_RGB2BGR))
        sh, sw = sheet.shape[:2]
        # push-in over the sheet
        z = lerp(1.0, 1.9, ease_in_out(clamp01(t / max(dur, 1))))
        view_w = int(sw / z)
        view_h = int(view_w * (mh - 60) / (mw - 60))
        cxs = lerp(0.5, 0.78, ease_in_out(clamp01(t / max(dur, 1))))
        cys = lerp(0.4, 0.78, ease_in_out(clamp01(t / max(dur, 1))))
        x0 = int(min(max(cxs * sw - view_w / 2, 0), sw - view_w))
        y0 = int(min(max(cys * sh - view_h / 2, 0), max(sh - view_h, 0)))
        crop = sheet[y0:y0 + view_h, x0:x0 + view_w]
        if crop.size and s > 0.95:
            crop = cv2.resize(crop, (mw - 60, mh - 60), interpolation=cv2.INTER_AREA)
            canvas[int(my - mh / 2 + 30):int(my - mh / 2 + 30) + mh - 60, int(mx - mw / 2 + 30):int(mx - mw / 2 + 30) + mw - 60] = crop
        # checklist on the right
        for i, (txt, ts) in enumerate(notes):
            if t < ts:
                continue
            k = clamp01((t - ts) / 0.35)
            y = 330 + i * 120
            x = 1270 + (1 - ease_out_cubic(k)) * 120
            blit(canvas, check_layer(54), x, y, scale=ease_out_back(k), alpha=k)
            draw_text_on(canvas, txt, x + 46, y, 36, WHITE, "zh", stroke=4, stroke_fill=INK, anchor=(0.0, 0.5), alpha=k)
    return fn


# ------------------------------------------------------------------ terminal card
TERM_LINES = [
    ("cmd", "godot --headless -s tools/check_scripts.gd"),
    ("ok", "checked 77 scripts, failed: 0"),
    ("cmd", "godot -s tools/test_loc.gd"),
    ("ok", "LOC TEST OK"),
    ("cmd", "godot -- --screen=match --pausetest"),
    ("ok", "[pausetest] changed during 2 s of pause: nothing"),
    ("ok", "[fontscan] done: 246 text nodes, 0 not using the game fonts"),
    ("cmd", "powershell tools/build_android.ps1 -Mode sideload"),
    ("ok", "android: encryption verified (directory flag set;"),
    ("ok", "         502 packed files, none with a plain signature)"),
    ("ok", "android: apksigner verify ok (v2, v3)"),
    ("ok", "ANDROID_BUILD_OK"),
    ("cmd", "adb -s a2875a83 install -r GoSports-sideload.apk"),
    ("ok", "Success"),
]


def terminal_scene(phone_shot: str | None = None, lines=TERM_LINES, steps: list[tuple[str, int]] | None = None):
    """a fake-free terminal: every line is a real line printed during this project's own rounds.  `steps` lights up a pipeline on the right."""
    steps = steps or [("编译检查", 1), ("中英文校验", 3), ("回归测试", 6), ("加密打包", 11), ("装进手机", 13)]
    # timeline
    ev = []
    tcur = 0.4
    for kind, txt in lines:
        if kind == "cmd":
            dur = len(txt) / 55.0
            ev.append((kind, txt, tcur, dur))
            tcur += dur + 0.35
        else:
            ev.append((kind, txt, tcur, 0.0))
            tcur += 0.28
    total = tcur
    colmap = {"cmd": (235, 240, 250), "ok": (110, 231, 160), "dim": GREY}

    def fn(canvas, t, dur):
        canvas[:] = bg_dark(t, glow=(BLUE, TEAL))
        a = clamp01(t / 0.4)
        draw_text_on(canvas, "每一轮，它都这样收尾", 120, 90, 60, WHITE, "zh", stroke=6, stroke_fill=INK, anchor=(0.0, 0.5), alpha=a)
        draw_text_on(canvas, "real output lines from this project's own rounds", 124, 152, 28, GREY, "lat", anchor=(0.0, 0.5), alpha=a)
        tw, th = 1260, 650
        tx, ty = 100, 215
        win = panel(tw, th, fill=(12, 16, 28), outline=(70, 90, 130), radius=26, alpha=1.0, shadow=26)
        s = ease_out_back(clamp01((t - 0.1) / 0.45))
        blit(canvas, win, tx + tw / 2, ty + th / 2, scale=max(s, 0.01))
        if s < 0.95:
            return
        for i, c in enumerate(((255, 95, 86), (255, 189, 46), (39, 201, 63))):
            cv2.circle(canvas, (tx + 40 + i * 34, ty + 38), 11, (c[2], c[1], c[0]), -1, cv2.LINE_AA)
        draw_text_on(canvas, "claude  ·  go-sports", tx + tw / 2, ty + 38, 24, GREY, "lat", anchor=(0.5, 0.5))
        visible = [e for e in ev if e[2] <= t]
        rows = 12
        first = max(0, len(visible) - rows)
        y = ty + 100
        for kind, txt, ts, dd in visible[first:]:
            if kind == "cmd":
                typed = txt[:int(clamp01((t - ts) / max(dd, 1e-3)) * len(txt))]
                draw_text_on(canvas, "$", tx + 36, y, 30, (110, 231, 160), "mono_dummy" if False else "lat", anchor=(0.0, 0.5))
                if typed:
                    lay = cached(("mono", typed), lambda typed=typed: mono_layer(typed, 29, (235, 240, 250), bold=False))
                    blit(canvas, lay, tx + 72, y, anchor=(0.0, 0.5))
            else:
                lay = cached(("mono", txt, kind), lambda txt=txt, kind=kind: mono_layer(txt, 29, colmap[kind]))
                blit(canvas, lay, tx + 72, y, anchor=(0.0, 0.5))
            y += 46
        if int(t * 2) % 2 == 0:
            cv2.rectangle(canvas, (tx + 74, int(y - 18)), (tx + 90, int(y + 12)), (235, 240, 250), -1)
        # pipeline on the right
        px = 1500
        for i, (name, at) in enumerate(steps):
            # the step lights when its trigger line index has been printed
            idx_t = ev[min(at, len(ev) - 1)][2]
            on = t >= idx_t
            k = clamp01((t - idx_t) / 0.3) if on else 0.0
            y2 = 290 + i * 98
            col = TEAL if on else (60, 74, 104)
            chip = cached(("stepchip", name, on), lambda name=name, on=on, col=col: pill_layer(330, 76, col, radius=38, outline=WHITE if on else None, outline_w=3, shadow=8))
            blit(canvas, chip, px + 165, y2, scale=1.0 + 0.08 * (1 - k) * on)
            draw_text_on(canvas, name, px + 180, y2, 38, WHITE, "zh", anchor=(0.5, 0.5), alpha=0.5 + 0.5 * on)
            if on:
                blit(canvas, check_layer(40), px - 14, y2, scale=ease_out_back(k))
            if i < len(steps) - 1:
                cv2.line(canvas, (px + 165, y2 + 40), (px + 165, y2 + 58), (110, 130, 170), 4, cv2.LINE_AA)
        # the real phone at the end
        if phone_shot and t > ev[-1][2] + 0.2:
            k = ease_out_back(clamp01((t - ev[-1][2] - 0.2) / 0.5))
            ph = phone_frame(phone_shot, 470)
            blit(canvas, ph, 1640, 880, scale=max(k, 0.01), rot=-4 * (1 - k))
    fn.total = total
    return fn


# ------------------------------------------------------------------ stats card
def stats_scene(items: list[dict], title: str = "一个人，加一个 Claude"):
    """items: [{'value': 25836, 'label': '行代码', 'en': 'lines of code', 'color': TEAL, 'fmt': '{:,}', 'suffix': '+'}]"""
    def fn(canvas, t, dur):
        canvas[:] = bg_dark(t, glow=(PINK, BLUE))
        a = clamp01(t / 0.4)
        draw_text_on(canvas, title, W / 2, 130, 70, WHITE, "zh", stroke=7, stroke_fill=INK, anchor=(0.5, 0.5), alpha=a)
        n = len(items)
        cw, ch = 420, 520
        gap = 30
        x0 = W / 2 - (n * cw + (n - 1) * gap) / 2
        for i, it in enumerate(items):
            ts = it.get("at", 0.5 + i * 0.28)
            k = clamp01((t - ts) / 0.5)
            if k <= 0:
                continue
            col = it["color"]
            card = cached(("scard", cw, ch, col), lambda col=col: pill_layer(cw, ch, (22, 34, 62), radius=40, outline=col, outline_w=6, shadow=22))
            cx = x0 + i * (cw + gap) + cw / 2
            cy = 560 + (1 - ease_out_cubic(k)) * 120
            blit(canvas, card, cx, cy, alpha=k)
            v = it["value"] * ease_out_cubic(clamp01((t - ts - 0.2) / 1.6))
            txt = it.get("fmt", "{:,}").format(int(round(v))) + (it.get("suffix", "") if v >= it["value"] * 0.999 else "")
            draw_text_on(canvas, txt, cx, cy - 70, 104 if len(txt) < 7 else 80, col, "disp", stroke=0, anchor=(0.5, 0.5), alpha=k)
            draw_text_on(canvas, it["label"], cx, cy + 60, 56, WHITE, "zh", stroke=5, stroke_fill=INK, anchor=(0.5, 0.5), alpha=k)
            if it.get("en"):
                draw_text_on(canvas, it["en"], cx, cy + 125, 28, GREY, "lat", anchor=(0.5, 0.5), alpha=k)
    return fn


# ------------------------------------------------------------------ rounds ticker (14 rounds of conversation)
ROUNDS = [
    ("1", "核心玩法：两对两、AI、键鼠 / 手柄 / 触屏"), ("2", "HUD 与回放：VS 卡、即时回放、连击"), ("3", "整套界面语言（扁平、药丸、斜条）"),
    ("4", "中英双语、按键重设"), ("5", "轻扁平风格、更清楚的开始按钮"), ("6", "电视转播镜头、LED 广告牌、动物裁判"),
    ("7", "角色设置页、图标与启动画面"), ("8", "球场装饰收藏、摄影记者、得分卡滚动"), ("9", "字体、裁判扔道具、鹰眼回放"),
    ("10", "瞄准、时机圈、真暂停、比赛计时"), ("11", "更多搞笑道具、更精致的叹号"), ("12", "文道潮黑字体、沙丁鱼"),
    ("13", "队友生气、收藏二级菜单、广告"), ("14", "击掌跳舞庆祝、对手内讧、加密打包"),
]


def rounds_scene():
    def fn(canvas, t, dur):
        canvas[:] = bg_dark(t, glow=(TEAL, BLUE))
        a = clamp01(t / 0.4)
        draw_text_on(canvas, "十四轮对话", 130, 110, 84, WHITE, "zh", stroke=8, stroke_fill=INK, anchor=(0.0, 0.5), alpha=a)
        draw_text_on(canvas, "14 rounds of conversation", 134, 190, 34, GREY, "lat", anchor=(0.0, 0.5), alpha=a)
        # two columns of 7
        per = 7
        step = clamp01(t / max(dur - 0.8, 1.0))
        for i, (n, txt) in enumerate(ROUNDS):
            ts = 0.5 + i * (max(dur - 2.0, 2.0) / len(ROUNDS))
            k = clamp01((t - ts) / 0.35)
            if k <= 0:
                continue
            col, row = divmod(i, per)
            x = 130 + col * 900 + (1 - ease_out_cubic(k)) * 90
            y = 290 + row * 96
            chip = cached(("rchip", n), lambda n=n: pill_layer(96, 72, PINK if int(n) >= 13 else TEAL, radius=36, outline=WHITE, outline_w=4, shadow=6))
            blit(canvas, chip, x + 48, y, scale=ease_out_back(k), alpha=k)
            draw_text_on(canvas, n, x + 48, y, 40, WHITE, "disp", anchor=(0.5, 0.5), alpha=k)
            draw_text_on(canvas, txt, x + 120, y, 36, WHITE, "zh", stroke=4, stroke_fill=INK, anchor=(0.0, 0.5), alpha=k)
    return fn


# ------------------------------------------------------------------ the loop diagram (n12)
def loop_scene():
    nodes = [("说一句人话", TEAL), ("写代码", BLUE), ("运行游戏", YELLOW), ("截图 · 看图", PINK), ("发现问题 → 修好", ORANGE)]

    def fn(canvas, t, dur):
        canvas[:] = bg_dark(t, glow=(BLUE, PINK))
        a = clamp01(t / 0.4)
        draw_text_on(canvas, "写 → 跑 → 看 → 改", W / 2, 120, 80, WHITE, "zh", stroke=8, stroke_fill=INK, anchor=(0.5, 0.5), alpha=a)
        cx, cy, R = W / 2, 560, 285
        n = len(nodes)
        # ring
        ang0 = -math.pi / 2
        for i in range(n):
            a0 = ang0 + 2 * math.pi * i / n
            a1 = ang0 + 2 * math.pi * (i + 1) / n
            k = clamp01((t - 0.4 - i * 0.55) / 0.5)
            if k > 0:
                pts = [(cx + R * math.cos(lerp(a0, a1, u / 20 * k)), cy + R * math.sin(lerp(a0, a1, u / 20 * k))) for u in range(21)]
                for p, q in zip(pts[:-1], pts[1:]):
                    cv2.line(canvas, (int(p[0]), int(p[1])), (int(q[0]), int(q[1])), (180, 190, 210), 6, cv2.LINE_AA)
        for i, (name, col) in enumerate(nodes):
            ang = ang0 + 2 * math.pi * i / n
            x, y = cx + R * math.cos(ang), cy + R * math.sin(ang)
            k = clamp01((t - 0.3 - i * 0.55) / 0.45)
            if k <= 0:
                continue
            w = 330 if len(name) > 5 else 270
            chip = cached(("lchip", name, w), lambda name=name, col=col, w=w: pill_layer(w, 84, col, radius=42, outline=WHITE, outline_w=5, shadow=10))
            pulse = 1.0 + 0.06 * math.sin(t * 5 - i) if t > 0.3 + i * 0.55 + 0.5 else 1.0
            blit(canvas, chip, x, y, scale=ease_out_back(k) * pulse, alpha=k)
            draw_text_on(canvas, name, x, y, 40, WHITE if col not in (YELLOW,) else INK, "zh", anchor=(0.5, 0.5), alpha=k, scale=ease_out_back(k) * pulse)
        # a traveling dot
        ph = (t * 0.45) % 1.0
        ang = ang0 + 2 * math.pi * ph
        cv2.circle(canvas, (int(cx + R * math.cos(ang)), int(cy + R * math.sin(ang))), 16, (255, 255, 255), -1, cv2.LINE_AA)
        draw_text_on(canvas, "我只负责说：哪里不对劲", cx, cy, 44, YELLOW, "zh", stroke=5, stroke_fill=INK, anchor=(0.5, 0.5), alpha=clamp01((t - 3.2) / 0.5))
    return fn


# ------------------------------------------------------------------ parallel branches (table tennis is being built in parallel)
LANES = [("动画", "branch · animation", 35, BLUE), ("界面", "branch · UI", 29, TEAL), ("美术", "branch · art", 10, PINK), ("场馆", "branch · venue", 5, ORANGE),
         ("音效", "branch · audio", 3, YELLOW), ("整合", "branch · main line", 36, (160, 130, 255))]


def lanes_scene(lanes=LANES):
    def fn(canvas, t, dur):
        canvas[:] = bg_dark(t, glow=(PINK, TEAL))
        a = clamp01(t / 0.4)
        draw_text_on(canvas, "下一款：并行开发中", 130, 110, 76, WHITE, "zh", stroke=8, stroke_fill=INK, anchor=(0.0, 0.5), alpha=a)
        draw_text_on(canvas, "The next game is being built in parallel Claude sessions", 134, 186, 32, GREY, "lat", anchor=(0.0, 0.5), alpha=a)
        top = 280
        maxc = max(l[2] for l in lanes)
        for i, (zh, br, count, col) in enumerate(lanes):
            ts = 0.4 + i * 0.22
            k = clamp01((t - ts) / 0.4)
            if k <= 0:
                continue
            y = top + i * 104
            chip = cached(("lane", zh, col), lambda zh=zh, col=col: pill_layer(190, 72, col, radius=36, outline=WHITE, outline_w=4, shadow=6))
            blit(canvas, chip, 130 + 95 + (1 - ease_out_cubic(k)) * -120, y, alpha=k)
            draw_text_on(canvas, zh, 130 + 95 + (1 - ease_out_cubic(k)) * -120, y, 38, WHITE if col != YELLOW else INK, "zh", anchor=(0.5, 0.5), alpha=k)
            draw_text_on(canvas, br, 350, y, 26, GREY, "lat", anchor=(0.0, 0.5), alpha=k)
            # the commit trail
            x0, x1 = 690, 1640
            cv2.line(canvas, (x0, y), (x1, y), (60, 74, 104), 6, cv2.LINE_AA)
            prog = clamp01((t - ts - 0.2) / 2.6)
            nn = int(count * ease_out_cubic(prog))
            cb = (col[2], col[1], col[0])
            for j in range(nn):
                px = x0 + (x1 - x0) * (j + 0.5) / maxc
                cv2.circle(canvas, (int(px), y), 11, cb, -1, cv2.LINE_AA)
                cv2.circle(canvas, (int(px), y), 11, (255, 255, 255), 2, cv2.LINE_AA)
            draw_text_on(canvas, f"{nn}", 1700, y, 46, WHITE, "disp", anchor=(0.0, 0.5), alpha=k)
            draw_text_on(canvas, "commits", 1780, y + 6, 24, GREY, "lat", anchor=(0.0, 0.5), alpha=k)
        k = clamp01((t - 2.6) / 0.5)
        draw_text_on(canvas, "各自一个分支  ·  互不污染", W / 2, 862, 44, YELLOW, "zh", stroke=5, stroke_fill=INK, anchor=(0.5, 0.5), alpha=k)
    return fn


# ------------------------------------------------------------------ series teaser
def _icon_layer(kind: str, d: int) -> np.ndarray:
    """sport icons: the Gemini-made series icons (promo_work/series_*.png, keyed with tools/key_icon.py) and the real ball render for
    volleyball; a plain procedural drawing is the fallback when a file is missing"""
    src = {"volley": ROOT / "art_src" / "brand" / "ball_render.png", "tt": ROOT / "promo_work" / "series_tt.png",
           "fb": ROOT / "promo_work" / "series_fb.png", "sb": ROOT / "promo_work" / "series_sb.png"}.get(kind)
    if src is not None and src.exists():
        return cached(("sporticonfile", kind, d), lambda: gfx.load_rgba(src, height=d))

    def mk():
        ss = 3
        s = d * ss
        img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        dr = ImageDraw.Draw(img)
        c = s / 2
        ink = (27, 42, 74, 255)
        lw = int(s * 0.035)
        if kind == "tt":
            dr.rounded_rectangle((c - s * 0.045, c + s * 0.12, c + s * 0.045, c + s * 0.44), int(s * 0.04), fill=(222, 164, 92, 255), outline=ink, width=lw)
            dr.ellipse((c - s * 0.32, c - s * 0.40, c + s * 0.32, c + s * 0.24), fill=(235, 64, 64, 255), outline=ink, width=lw)
            dr.arc((c - s * 0.25, c - s * 0.33, c + s * 0.25, c + s * 0.17), 200, 340, fill=(255, 255, 255, 120), width=int(s * 0.03))
            dr.ellipse((c + s * 0.18, c - s * 0.42, c + s * 0.34, c - s * 0.26), fill=(255, 255, 255, 255), outline=ink, width=lw)
        elif kind == "fb":
            dr.ellipse((c - s * 0.40, c - s * 0.40, c + s * 0.40, c + s * 0.40), fill=(255, 255, 255, 255), outline=ink, width=lw)
            pent = [(c + s * 0.15 * math.cos(math.radians(a - 90)), c + s * 0.15 * math.sin(math.radians(a - 90))) for a in range(0, 360, 72)]
            dr.polygon(pent, fill=ink)
            for a in range(0, 360, 72):
                ang = math.radians(a - 90)
                p0 = (c + s * 0.15 * math.cos(ang), c + s * 0.15 * math.sin(ang))
                p1 = (c + s * 0.30 * math.cos(ang), c + s * 0.30 * math.sin(ang))
                dr.line([p0, p1], fill=ink, width=lw)
                a2 = math.radians(a - 90 + 36)
                q = (c + s * 0.40 * math.cos(a2), c + s * 0.40 * math.sin(a2))
                dr.polygon([(c + s * 0.30 * math.cos(ang) - s * 0.04, c + s * 0.30 * math.sin(ang) - s * 0.04), (c + s * 0.30 * math.cos(ang) + s * 0.07, c + s * 0.30 * math.sin(ang) + s * 0.0),
                            (c + s * 0.36 * math.cos(ang), c + s * 0.36 * math.sin(ang) + s * 0.05)], fill=ink)
        elif kind == "sb":
            dr.rounded_rectangle((s * 0.08, c + s * 0.12, s * 0.92, c + s * 0.34), int(s * 0.05), fill=(205, 150, 90, 255), outline=ink, width=lw)
            dr.rounded_rectangle((s * 0.08, c - s * 0.02, s * 0.92, c + s * 0.14), int(s * 0.04), fill=(236, 190, 120, 255), outline=ink, width=lw)
            for x, col in ((0.30, (47, 168, 255)), (0.52, (255, 79, 160)), (0.74, (255, 211, 61))):
                dr.ellipse((s * x - s * 0.1, c - s * 0.20, s * x + s * 0.1, c + s * 0.02), fill=col + (255,), outline=ink, width=lw)
                dr.ellipse((s * x - s * 0.06, c - s * 0.16, s * x + s * 0.06, c - s * 0.04), outline=(255, 255, 255, 170), width=int(s * 0.015))
            dr.line([(s * 0.18, c - s * 0.36), (s * 0.60, c - s * 0.12)], fill=(120, 80, 40, 255), width=int(s * 0.04))
        else:  # volleyball
            dr.ellipse((c - s * 0.40, c - s * 0.40, c + s * 0.40, c + s * 0.40), fill=(255, 211, 61, 255), outline=ink, width=lw)
            dr.arc((c - s * 0.40, c - s * 0.40, c + s * 0.40, c + s * 0.40), 200, 330, fill=(47, 120, 220, 255), width=int(s * 0.10))
            dr.arc((c - s * 0.20, c - s * 0.55, c + s * 0.55, c + s * 0.20), 90, 200, fill=ink, width=lw)
            dr.arc((c - s * 0.55, c - s * 0.10, c + s * 0.20, c + s * 0.55), 280, 360, fill=ink, width=lw)
        return np.array(img.resize((d, d), Image.LANCZOS))
    return cached(("sporticon", kind, d), mk)


def series_scene(times=(0.6, 1.0, 1.4, 1.8)):
    cards_ = [("排球", "VOLLEYBALL", "volley", TEAL, "已上线", "PLAYABLE NOW"),
              ("乒乓球", "TABLE TENNIS", "tt", PINK, "即将到来", "COMING SOON"),
              ("足球", "FOOTBALL", "fb", BLUE, "即将到来", "COMING SOON"),
              ("沙狐球", "SHUFFLEBOARD", "sb", ORANGE, "即将到来", "COMING SOON")]

    def fn(canvas, t, dur):
        canvas[:] = bg_sport(t * 0.7, top=(20, 150, 190), bottom=(60, 80, 200), stripe_alpha=0.07)
        cards._CONFETTI.draw(canvas, t * 0.4)
        a = clamp01(t / 0.4)
        draw_text_on(canvas, "GoSports 系列", W / 2, 120, 96, WHITE, "zh", stroke=9, stroke_fill=INK, anchor=(0.5, 0.5), alpha=a, shadow=8)
        draw_text_on(canvas, "THE GOSPORTS SERIES", W / 2, 196, 36, (225, 245, 250), "lat", anchor=(0.5, 0.5), alpha=a)
        cw, ch, gap = 392, 600, 36
        x0 = W / 2 - (len(cards_) * cw + (len(cards_) - 1) * gap) / 2
        for i, (zh, en, ic, col, st, st_en) in enumerate(cards_):
            ts = times[i]
            k = clamp01((t - ts) / 0.6)
            if k <= 0:
                continue
            kk = ease_out_back(k)
            card = cached(("sercard", cw, ch, col), lambda col=col: pill_layer(cw, ch, WHITE, radius=44, outline=col, outline_w=10, shadow=26))
            cx = x0 + i * (cw + gap) + cw / 2
            cy = 560 + (1 - ease_out_cubic(k)) * 260 + math.sin(t * 2 + i) * 6
            blit(canvas, card, cx, cy, scale=0.9 + 0.1 * kk, alpha=k)
            band = cached(("serband", cw, col), lambda col=col: pill_layer(cw - 40, 150, col, radius=36))
            blit(canvas, band, cx, cy - ch / 2 + 130, alpha=k)
            draw_text_on(canvas, zh, cx, cy - ch / 2 + 112, 66, WHITE, "zh", stroke=6, stroke_fill=INK, anchor=(0.5, 0.5), alpha=k)
            draw_text_on(canvas, en, cx, cy - ch / 2 + 168, 26, WHITE, "lat", anchor=(0.5, 0.5), alpha=k)
            blit(canvas, _icon_layer(ic, 300), cx, cy + 10 + math.sin(t * 3 + i) * 6, scale=kk, alpha=k)
            badge_col = GREEN if st == "已上线" else (YELLOW if st == "开发中" else (205, 215, 230))
            badge = cached(("serbadge", badge_col), lambda badge_col=badge_col: pill_layer(300, 84, badge_col, radius=42, outline=INK, outline_w=4, shadow=4))
            blit(canvas, badge, cx, cy + ch / 2 - 90, alpha=k)
            draw_text_on(canvas, st, cx, cy + ch / 2 - 100, 40, INK, "zh", anchor=(0.5, 0.5), alpha=k)
            draw_text_on(canvas, st_en, cx, cy + ch / 2 - 66, 20, INK, "lat", anchor=(0.5, 0.5), alpha=k)
    return fn


# ------------------------------------------------------------------ "all generated in code" (n15)
CODE_LINES = [
    ('var pu_wind := _m(angry_a, {', (150, 200, 255)),
    ('    "torso": Vector3(4, -34, 0), "body": Vector3(8, -14, 0),', (235, 240, 250)),
    ('    "handc_r": Vector3(0.5, -0.15, -0.5),', (235, 240, 250)),
    ('    "elbow_r": Vector3(1, -0.2, -0.9),', (235, 240, 250)),
    ('    "foot_r_off": Vector3(0.06, 0, -0.14)})', (235, 240, 250)),
    ('', (235, 240, 250)),
    ('"punch": {"keys": [[0.0, angry_a], [0.22, pu_wind, "smooth"],', (255, 211, 61)),
    ('           [0.34, pu_hit, "out"], [1.0, angry_a, "smooth"]]},', (255, 211, 61)),
]
GEN_TILES = [("动画", "pose specs → baked clips", BLUE), ("特效", "particles · speed lines", PINK), ("音效", "31 synthesised sounds", YELLOW),
             ("音乐", "two themes in numpy", TEAL), ("界面", "every pill, ribbon, card", ORANGE)]


def codegen_scene(tile_times: list[float]):
    """left: a real snippet of the project's pose spec typed out; bottom: five tiles light up as the narration lists them.
    The footage window (the punch that this code produces) is a Shot added on top by the edit."""
    def fn(canvas, t, dur):
        canvas[:] = bg_dark(t, glow=(ORANGE, BLUE))
        a = clamp01(t / 0.4)
        draw_text_on(canvas, "全都是代码生成的", 110, 100, 70, WHITE, "zh", stroke=7, stroke_fill=INK, anchor=(0.0, 0.5), alpha=a)
        draw_text_on(canvas, "except the character pack and the icons", 114, 168, 30, GREY, "lat", anchor=(0.0, 0.5), alpha=a)
        cw, chh = 1000, 440
        win = panel(cw, chh, fill=(12, 16, 28), outline=(70, 90, 130), radius=24, alpha=1.0, shadow=24)
        s = ease_out_back(clamp01((t - 0.15) / 0.45))
        cx0, cy0 = 90, 230
        blit(canvas, win, cx0 + cw / 2, cy0 + chh / 2, scale=max(s, 0.01))
        if s > 0.95:
            draw_text_on(canvas, "scripts/rig/clip_defs.gd", cx0 + 36, cy0 + 40, 26, GREY, "lat", anchor=(0.0, 0.5))
            total_chars = sum(len(l[0]) for l in CODE_LINES)
            typed = int(clamp01((t - 0.7) / 3.2) * total_chars)
            y = cy0 + 100
            for txt, col in CODE_LINES:
                part = txt[:max(0, typed)]
                typed -= len(txt)
                if part:
                    lay = cached(("code", part, col), lambda part=part, col=col: mono_layer(part, 27, col))
                    blit(canvas, lay, cx0 + 36, y, anchor=(0.0, 0.5))
                y += 44
        # tiles
        tw, th = 330, 150
        gap = 24
        x0 = 90
        for i, (name, sub, col) in enumerate(GEN_TILES):
            ts = tile_times[i] if i < len(tile_times) else 99
            k = clamp01((t - ts) / 0.4)
            xx = x0 + i * (tw + gap) + tw / 2
            yy = 815
            on = k > 0
            tile = cached(("gentile", name, on), lambda col=col, on=on: pill_layer(tw, th, col if on else (34, 48, 86), radius=34, outline=WHITE if on else (70, 90, 130), outline_w=4, shadow=12))
            blit(canvas, tile, xx, yy, scale=1.0 + 0.1 * (1 - k) if on else 1.0)
            draw_text_on(canvas, name, xx, yy - 22, 60, WHITE if col != YELLOW or not on else INK, "zh", anchor=(0.5, 0.5), alpha=0.5 + 0.5 * on)
            draw_text_on(canvas, sub, xx, yy + 40, 22, (235, 245, 250) if on else GREY, "lat", anchor=(0.5, 0.5), alpha=0.6 + 0.4 * on)
    return fn


ROUNDS_EN = ["Core game: 2-on-2, AI, keyboard / gamepad / touch", "HUD & replay: VS card, instant replay, combos", "A full UI language (flat, pills, ribbons)",
             "Chinese + English, key rebinding", "Lightly flat style, a clearer Start button", "TV-style cameras, LED boards, animal umpire",
             "Character loadout page, icons & splash", "Court-decor collection, press photographers, rolling score", "Fonts, umpire props, hawk-eye replay",
             "Aiming, timing ring, true pause, match clock", "More gag props, a better exclamation mark", "A new Chinese font, the sardine",
             "Angry partners, collection sub-menus, ads", "High-five & dance, rival tantrums, encrypted builds"]
cards.TR.update({zh: en for (_, zh), en in zip(ROUNDS, ROUNDS_EN)})

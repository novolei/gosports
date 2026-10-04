#!/usr/bin/env python
"""Procedural environment textures for the bright Switch-Sports-style volleyball arena.

Re-runnable and seeded (every texture has its own fixed seed).  Pure numpy + PIL.

    python tools/gen_env_textures.py              # generate everything
    python tools/gen_env_textures.py skyline wood # only matching names

Output: assets/env/*.png
"""
import os
import sys
import math
import time
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "assets", "env"))
REG = {}


def tex(name):
    def deco(fn):
        REG[name] = fn
        return fn
    return deco


# --------------------------------------------------------------------------- helpers
def hexc(s):
    s = s.lstrip("#")
    return np.array([int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


WHITE = np.array([1, 1, 1], np.float32)


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def ramp(stops, t):
    """stops: [(pos, rgb)], t: array -> (...,3) float32 piecewise-linear gradient"""
    pos = np.array([p for p, _ in stops], np.float32)
    cols = np.array([c for _, c in stops], np.float32)
    t = np.asarray(t, np.float32)
    return np.stack([np.interp(t, pos, cols[:, i]) for i in range(cols.shape[1])], axis=-1).astype(np.float32)


def gblur(a, sigma, wrap=True):
    """FFT gaussian blur of a float array (H,W[,C]); wrap=True -> periodic (tile safe)."""
    a = np.asarray(a, np.float32)
    if sigma <= 0:
        return a
    if not wrap:
        pad = int(sigma * 3) + 2
        pw = [(pad, pad), (pad, pad)] + [(0, 0)] * (a.ndim - 2)
        return gblur(np.pad(a, pw, mode="edge"), sigma, True)[pad:-pad, pad:-pad]
    H, W = a.shape[:2]
    fy = np.fft.fftfreq(H)[:, None]
    fx = np.fft.rfftfreq(W)[None, :]
    k = np.exp(-2 * (np.pi * sigma) ** 2 * (fx ** 2 + fy ** 2)).astype(np.float32)
    if a.ndim == 2:
        return np.fft.irfft2(np.fft.rfft2(a) * k, s=(H, W)).astype(np.float32)
    out = np.empty_like(a)
    for c in range(a.shape[2]):
        out[..., c] = np.fft.irfft2(np.fft.rfft2(a[..., c]) * k, s=(H, W))
    return out


def _fade(t):
    return t * t * t * (t * (t * 6 - 15) + 10)


def value_noise(h, w, cy, cx, rng, wrap=True):
    ny = cy if wrap else cy + 1
    nx = cx if wrap else cx + 1
    g = rng.random((ny, nx)).astype(np.float32)
    ys = np.arange(h, dtype=np.float32) * (cy / h)
    xs = np.arange(w, dtype=np.float32) * (cx / w)
    iy = ys.astype(np.int64)
    ix = xs.astype(np.int64)
    fy = _fade(ys - iy)
    fx = _fade(xs - ix)
    iy1 = (iy + 1) % ny if wrap else np.minimum(iy + 1, ny - 1)
    ix1 = (ix + 1) % nx if wrap else np.minimum(ix + 1, nx - 1)
    rows = g[:, ix] * (1 - fx) + g[:, ix1] * fx            # (ny, w)
    return rows[iy] * (1 - fy)[:, None] + rows[iy1] * fy[:, None]


def fbm(h, w, cy, cx, rng, octaves=4, pers=0.5, wrap=True):
    tot = np.zeros((h, w), np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        tot += amp * value_noise(h, w, cy * 2 ** o, cx * 2 ** o, rng, wrap)
        norm += amp
        amp *= pers
    return tot / norm


def sample_wrap(img, xs, ys):
    """bilinear sample of img (H,W[,C]) at float pixel coords with wrap-around"""
    H, W = img.shape[:2]
    x0 = np.floor(xs).astype(np.int64)
    y0 = np.floor(ys).astype(np.int64)
    fx = (xs - x0).astype(np.float32)
    fy = (ys - y0).astype(np.float32)
    if img.ndim == 3:
        fx = fx[..., None]
        fy = fy[..., None]
    x0m, x1m, y0m, y1m = x0 % W, (x0 + 1) % W, y0 % H, (y0 + 1) % H
    return (img[y0m, x0m] * (1 - fx) * (1 - fy) + img[y0m, x1m] * fx * (1 - fy)
            + img[y1m, x0m] * (1 - fx) * fy + img[y1m, x1m] * fx * fy)


def to_u8(a):
    return (np.clip(a, 0, 1) * 255.0 + 0.5).astype(np.uint8)


def save_rgb(a, name):
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(to_u8(a), "RGB").save(os.path.join(OUT, name), optimize=True)


def save_rgba(a, name):
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(to_u8(a), "RGBA").save(os.path.join(OUT, name), optimize=True)


def box_down(a, s):
    h, w = a.shape[:2]
    return a.reshape(h // s, s, w // s, s, *a.shape[2:]).mean(axis=(1, 3))


def pil_f(img):
    return np.asarray(img, np.float32) / 255.0


def bleed_rgb(rgb, a):
    """fill RGB of (nearly) transparent texels with nearby colour -> no dark fringes when filtered"""
    known = a > 0.02
    cur = np.where(known[..., None], rgb, 0).astype(np.float32)
    kf = known.astype(np.float32)
    for s in (1.5, 3, 6, 12, 24, 48, 96):
        num = gblur(cur * kf[..., None], s, wrap=False)
        den = gblur(kf, s, wrap=False)
        new = (~known) & (den > 0.02)
        cur[new] = num[new] / den[new][:, None]
        known = known | new
        kf = known.astype(np.float32)
    cur[~known] = 0.5
    return cur


def blit(dst_rgb, dst_a, col, m, x0, y0):
    """premultiplied 'over' of colour patch col (h,w,3) with coverage m (h,w) into dst at (x0,y0), clipped"""
    Hh, Ww = dst_a.shape
    h, w = m.shape
    xs0, ys0 = max(x0, 0), max(y0, 0)
    xs1, ys1 = min(x0 + w, Ww), min(y0 + h, Hh)
    if xs1 <= xs0 or ys1 <= ys0:
        return
    sub = (slice(ys0 - y0, ys1 - y0), slice(xs0 - x0, xs1 - x0))
    dst = (slice(ys0, ys1), slice(xs0, xs1))
    mm = m[sub]
    dst_rgb[dst] = col[sub] * mm[..., None] + dst_rgb[dst] * (1 - mm[..., None])
    dst_a[dst] = mm + dst_a[dst] * (1 - mm)


def bez2(p0, p1, p2, n):
    t = np.linspace(0, 1, n, dtype=np.float64)[:, None]
    return (1 - t) ** 2 * np.asarray(p0, np.float64) + 2 * (1 - t) * t * np.asarray(p1, np.float64) + t ** 2 * np.asarray(p2, np.float64)


def bez3(p0, p1, p2, p3, n):
    t = np.linspace(0, 1, n, dtype=np.float64)[:, None]
    p0, p1, p2, p3 = [np.asarray(p, np.float64) for p in (p0, p1, p2, p3)]
    return (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t ** 2 * p2 + t ** 3 * p3


def normals_of(pts):
    tg = np.gradient(pts, axis=0)
    ln = np.linalg.norm(tg, axis=1, keepdims=True) + 1e-9
    tg = tg / ln
    return tg, np.stack([-tg[:, 1], tg[:, 0]], axis=1)


def c255(rgb):
    return tuple(int(round(float(v) * 255)) for v in np.clip(rgb, 0, 1)) + (255,)


def draw_strip(d, pts, wl, wr, col_l, col_r):
    """filled ribbon along pts. wl/wr = half widths each side (n,), col_* = (n,3) floats 0..1"""
    tg, nm = normals_of(pts)
    L = pts + nm * wl[:, None]
    R = pts - nm * wr[:, None]
    for i in range(len(pts) - 1):
        d.polygon([tuple(pts[i]), tuple(pts[i + 1]), tuple(L[i + 1]), tuple(L[i])], fill=c255(col_l[i]))
        d.polygon([tuple(pts[i]), tuple(pts[i + 1]), tuple(R[i + 1]), tuple(R[i])], fill=c255(col_r[i]))


# --------------------------------------------------------------------------- 1. skyline
def _cloud(sky, rng, cx, by, wd, ht, alpha=0.96):
    H_, W_ = sky.shape[:2]
    x0 = int(cx - wd / 2 - 40)
    x1 = int(cx + wd / 2 + 40)
    y0 = int(by - ht * 1.5 - 40)
    y1 = int(by + 12)
    if x1 < 0 or x0 > W_ or y1 < 0 or y0 > H_:
        return
    puffs = []
    n = int(rng.integers(9, 15))
    for _ in range(n):
        u = rng.uniform(-0.5, 0.5)
        prof = (1 - (2 * u) ** 2) ** 0.6
        r = ht * (0.26 + 0.62 * prof) * rng.uniform(0.75, 1.1)
        puffs.append((cx + u * wd * 0.92, by - r * rng.uniform(0.5, 0.92), r))
    ys, xs = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    xs += 0.5
    ys += 0.5
    sdf = np.full(xs.shape, -1e3, np.float32)
    hgt = np.zeros(xs.shape, np.float32)
    nx = np.zeros(xs.shape, np.float32)
    ny = np.zeros(xs.shape, np.float32)
    nz = np.ones(xs.shape, np.float32)
    for (px, py, r) in puffs:
        dx, dy = xs - px, ys - py
        d2 = dx * dx + dy * dy
        sdf = np.maximum(sdf, r - np.sqrt(d2))
        hh = np.sqrt(np.maximum(r * r - d2, 0))
        upd = hh > hgt
        hgt = np.where(upd, hh, hgt)
        nx = np.where(upd, dx / r, nx)
        ny = np.where(upd, dy / r, ny)
        nz = np.where(upd, hh / r, nz)
    a = smoothstep(-2.0, 3.5, sdf) * np.clip((by - ys) / 7.0 + 0.5, 0, 1)
    hb = gblur(hgt, max(3.0, ht * 0.07), wrap=False)
    gy_, gx_ = np.gradient(hb)
    k = 1.4
    nx = -gx_ * k
    ny = -gy_ * k
    nz = np.ones_like(nx)
    nn = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / nn, ny / nn, nz / nn
    Ld = np.array([-0.45, -0.72, 0.52], np.float32)
    Ld /= np.linalg.norm(Ld)
    lam = nx * Ld[0] + ny * Ld[1] + nz * Ld[2]
    shade = smoothstep(0.35, 0.98, lam)
    vv = np.clip((ys - (by - ht * 1.1)) / (ht * 1.1), 0, 1)
    shade = shade * (1 - 0.30 * vv ** 1.5)
    col = ramp([(0.0, hexc("#B2CFEA")), (0.5, hexc("#E3F0FB")), (1.0, hexc("#FFFFFF"))], shade)
    # clip to canvas
    cx0, cy0 = max(x0, 0), max(y0, 0)
    cx1, cy1 = min(x1, W_), min(y1, H_)
    sl = (slice(cy0 - y0, cy1 - y0), slice(cx0 - x0, cx1 - x0))
    dst = (slice(cy0, cy1), slice(cx0, cx1))
    aa = (a[sl] * alpha)[..., None]
    sky[dst] = sky[dst] * (1 - aa) + col[sl] * aa


def _plan_layer(rng, W, ground, hmin, hmax, wmin, wmax, palette, pastel, pastel_p, shape_w, overlap, style, hpow=1.15):
    shapes = list(shape_w.keys())
    p = np.array(list(shape_w.values()), float)
    p /= p.sum()
    out = []
    x = rng.uniform(-30, 0)
    while x < W:
        wd = rng.uniform(wmin, wmax)
        hh = hmin + (hmax - hmin) * rng.random() ** hpow
        shape = shapes[int(rng.choice(len(shapes), p=p))]
        if shape == "ball":
            wd = rng.uniform(42, 58)
            hh = max(hh, (hmax - hmin) * 0.7 + hmin)
        if rng.random() < pastel_p:
            col = pastel[int(rng.integers(len(pastel)))].copy()
        else:
            col = palette[int(rng.integers(len(palette)))].copy()
        col = np.clip(col + rng.normal(0, 0.012, 3), 0, 1).astype(np.float32)
        b = dict(x=x, wd=wd, top=ground - hh, shape=shape, col=col, style=style)
        if style == "mid":
            b["cw"], b["ch"] = rng.uniform(7, 12), rng.uniform(10, 16)
        else:
            b["cw"], b["ch"] = rng.uniform(10, 17), rng.uniform(14, 24)
        b["bands"] = rng.random() < 0.28
        b["rf"] = rng.uniform(0.55, 1.0)
        b["slope"] = rng.uniform(18, 60)
        b["flip"] = bool(rng.random() < 0.5)
        b["lean"] = rng.choice([-1, 1]) * wd * rng.uniform(0.12, 0.2)
        roof = rng.choice(["none", "box", "tank", "ant", "twin", "box", "none"])
        b["roof"] = str(roof)
        b["ant_h"] = rng.uniform(22, 70) * (1.2 if style == "far" else 1.0)
        b["spire_h"] = rng.uniform(40, 110)
        b["rx"] = rng.uniform(0.2, 0.8)
        out.append(b)
        x += wd + rng.uniform(*overlap)
    return out


def _draw_building(Rg, Ag, b, S, rng):
    W2 = Ag.shape[1]
    H2 = Ag.shape[0]
    x0 = b["x"] * S
    Wd = b["wd"] * S
    T = b["top"] * S
    shape = b["shape"]
    style = b["style"]
    lean = b["lean"] * S if shape == "skew" else 0.0
    asc = 20 * S + (b["spire_h"] * S if shape in ("spire", "stepped", "ball") else 0) + (b["ant_h"] * S if b["roof"] in ("ant", "twin") else 0)
    pad = int(abs(lean)) + 6
    gx0 = int(math.floor(x0)) - pad
    gx1 = int(math.ceil(x0 + Wd)) + pad
    gy0 = int(T - asc)
    gy1 = H2
    bw, bh = gx1 - gx0, gy1 - gy0
    lx0 = x0 - gx0
    lx1 = lx0 + Wd
    lxc = (lx0 + lx1) / 2
    lt = T - gy0
    lb = bh
    body = Image.new("L", (bw, bh), 0)
    det = Image.new("L", (bw, bh), 0)
    db, dd = ImageDraw.Draw(body), ImageDraw.Draw(det)
    detf = 0.95
    roof_y = lt
    if shape in ("flat", "tower"):
        db.rectangle([lx0, lt, lx1, lb], fill=255)
        if rng.random() < 0.5:   # parapet lip
            dd.rectangle([lx0 - 1 * S, lt - 2 * S, lx1 + 1 * S, lt + 1 * S], fill=255)
    elif shape == "rounded":
        cap = Wd / 2 * b["rf"]
        db.rectangle([lx0, lt + cap, lx1, lb], fill=255)
        db.ellipse([lx0, lt, lx1, lt + 2 * cap], fill=255)
        roof_y = lt
    elif shape == "slant":
        sl = b["slope"] * S
        pts = [(lx0, lb), (lx0, lt), (lx1, lt + sl), (lx1, lb)] if b["flip"] else [(lx0, lb), (lx0, lt + sl), (lx1, lt), (lx1, lb)]
        db.polygon(pts, fill=255)
    elif shape == "skew":
        db.polygon([(lx0, lb), (lx0 + lean, lt), (lx1 + lean, lt), (lx1, lb)], fill=255)
    elif shape == "stepped":
        hh = lb - lt
        for wf, tf in ((1.0, 0.48), (0.72, 0.22), (0.46, 0.0)):
            ww = Wd * wf
            db.rectangle([lxc - ww / 2, lt + tf * min(hh, 420 * S), lxc + ww / 2, lb], fill=255)
        sp = b["spire_h"] * S * 0.7
        dd.polygon([(lxc - Wd * 0.05, lt + 1), (lxc + Wd * 0.05, lt + 1), (lxc, lt - sp)], fill=255)
    elif shape == "spire":
        db.rectangle([lx0, lt, lx1, lb], fill=255)
        sp = b["spire_h"] * S
        dd.polygon([(lxc - Wd * 0.2, lt + 1), (lxc + Wd * 0.2, lt + 1), (lxc, lt - sp)], fill=255)
    elif shape == "ball":
        podh = min(lb - lt, 90 * S) * 1.0
        dd.rectangle([lx0, lb - podh, lx1, lb], fill=255)
        sw = Wd * 0.2
        ball_cy = lt + Wd * 0.65
        dd.rectangle([lxc - sw / 2, ball_cy, lxc + sw / 2, lb], fill=255)
        dd.ellipse([lxc - Wd * 0.55, ball_cy - Wd * 0.55, lxc + Wd * 0.55, ball_cy + Wd * 0.55], fill=255)
        dd.polygon([(lxc - sw * 0.3, ball_cy - Wd * 0.4), (lxc + sw * 0.3, ball_cy - Wd * 0.4), (lxc, lt - b["spire_h"] * S * 0.7)], fill=255)
        detf = 1.0
    # roof furniture (flat-ish roofs)
    if shape in ("flat", "tower", "skew", "rounded") and b["roof"] != "none":
        rx = lx0 + Wd * b["rx"]
        ry = lt + (Wd / 2 * b["rf"] * 0.35 if shape == "rounded" else 0)
        if b["roof"] == "box":
            bwid = Wd * 0.28
            dd.rectangle([rx - bwid / 2, ry - 7 * S, rx + bwid / 2, ry + 1], fill=255)
        elif b["roof"] == "tank":
            tw = 9 * S
            dd.rectangle([rx - tw, ry - 9 * S, rx + tw, ry + 1], fill=255)
            dd.polygon([(rx - tw, ry - 9 * S), (rx + tw, ry - 9 * S), (rx, ry - 15 * S)], fill=255)
        elif b["roof"] in ("ant", "twin"):
            aw = max(2, int(1.6 * S))
            xs_a = [rx] if b["roof"] == "ant" else [rx - 6 * S, rx + 6 * S]
            for k, ax in enumerate(xs_a):
                hgt = b["ant_h"] * S * (1.0 if k == 0 else 0.62)
                dd.rectangle([ax - aw / 2, ry - hgt, ax + aw / 2, ry + 1], fill=255)
                dd.rectangle([ax - 2 * aw, ry - hgt * 0.62, ax + 2 * aw, ry - hgt * 0.62 + aw], fill=255)
    mask = ImageChops.lighter(body, det)
    m = pil_f(mask)
    bm = pil_f(body)
    dm = pil_f(det)

    ys = np.arange(bh, dtype=np.float32)[:, None]
    xs = np.arange(bw, dtype=np.float32)[None, :]
    base = b["col"]
    cols = np.empty((bh, bw, 3), np.float32)
    cols[:] = base
    yv = np.clip((ys - lt) / (520 * S), 0, 1)
    tl = {"far": 0.10, "mid": 0.16, "near": 0.10}[style]
    cols = lerp(cols, WHITE, (tl * (1 - yv))[..., None])
    xr = (xs - lx0) / Wd
    if shape in ("rounded",):
        cyl = 0.10 * np.cos((xr - 0.30) * 2.2) - 0.03
        cols = cols * (1 + cyl[..., None])
    sun = {"far": 0.0, "mid": 0.42, "near": 0.30}[style]
    if sun > 0:
        ew = max(3.5 * S, 0.055 * Wd)
        e = np.clip(1 - (xs - lx0) / ew, 0, 1) ** 1.6
        cols = lerp(cols, WHITE, (e * sun)[..., None])
    sh = smoothstep(0.86, 1.0, xr)
    cols = lerp(cols, hexc("#4A6C8E"), (sh * 0.13)[..., None])

    if style in ("mid", "near") and shape not in ("ball",):
        cw = int(round(b["cw"] * S))
        ch = int(round(b["ch"] * S))
        if b["bands"]:
            ix, iy = 0, int(ch * 0.26)
        else:
            ix, iy = int(cw * 0.22), int(ch * 0.2)
        if shape == "skew":
            shift = lean * (lb - ys) / max(1.0, (lb - lt))
            xrel = xs - lx0 - shift
        else:
            xrel = (xs - lx0) + np.zeros_like(ys)
        yrel = (ys - lt - 4 * S) + np.zeros_like(xs)
        gx = np.floor(xrel / cw).astype(np.int64)
        gy = np.floor(yrel / ch).astype(np.int64)
        px = xrel - gx * cw
        py = yrel - gy * ch
        win = (px >= ix) & (px < cw - ix) & (py >= iy) & (py < ch - iy) & (yrel >= 0)
        win &= (xrel > 3 * S) & (xrel < Wd - 3 * S)
        R = rng.random((int(bh // ch) + 4, int(bw // cw) + 4)).astype(np.float32)
        r = R[np.clip(gy, 0, R.shape[0] - 1), np.clip(gx, 0, R.shape[1] - 1)]
        if b["bands"]:
            r = 0.35 + 0.5 * R[np.clip(gy, 0, R.shape[0] - 1), 0][:, :1] * 0 + 0.3 * r
        if style == "mid":
            pane = lerp(cols, hexc("#EAF8FF"), 0.30 + 0.22 * r[..., None] - 0.12 * yv[..., None])
            pane = pane * (0.93 + 0.1 * r[..., None])
        else:
            dark = lerp(cols, hexc("#3E6E9C"), 0.50) * (0.88 + 0.22 * r[..., None])
            lit = lerp(cols, hexc("#D9F0FF"), 0.72)
            pane = np.where((r > 0.90)[..., None], lit, dark)
        wm = (win.astype(np.float32) * bm)[..., None]
        cols = cols * (1 - wm) + pane * wm
        # floor-line shading between windows
    elif style == "far":
        # faint vertical rib / floor texture only
        rib = 0.5 + 0.5 * np.sin(xs * (math.pi / (6 * S)))
        cols = cols * (1 - 0.018 * rib[..., None])

    cols = np.where((dm > 0.5)[..., None] & (bm < 0.5)[..., None], cols * detf, cols)
    for ox in (-W2, 0, W2):
        blit(Rg, Ag, cols, m, gx0 + ox, gy0)


def _render_layer(rng, buildings, W, H, S):
    Rg = np.zeros((H * S, W * S, 3), np.float32)
    Ag = np.zeros((H * S, W * S), np.float32)
    for b in buildings:
        _draw_building(Rg, Ag, b, S, rng)
    return box_down(Rg, S), box_down(Ag, S)


def _apply_haze(rgb_p, a, ground_y, top_y, hz, a0, a1):
    H = a.shape[0]
    ys = np.arange(H, dtype=np.float32)[:, None]
    amt = np.clip(a0 + a1 * np.clip((ys - top_y) / max(1.0, (ground_y - top_y)), 0, 1.4), 0, 0.95)
    return rgb_p * (1 - amt[..., None]) + a[..., None] * hz * amt[..., None]


def _foliage(rng, W, H, S):
    img = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    green_sets = [
        (hexc("#1E6B33"), hexc("#2E8B3A"), hexc("#58B83A")),
        (hexc("#23763A"), hexc("#3A9A3E"), hexc("#7FD04A")),
        (hexc("#2B8239"), hexc("#48AE41"), hexc("#9BD84A")),
    ]
    blossom = [
        (hexc("#D77AA3"), hexc("#F29BC0"), hexc("#FFD1E3")),
        (hexc("#B9A0E6"), hexc("#CDB9F5"), hexc("#EADFFF")),
        (hexc("#E8B64F"), hexc("#F6CF6A"), hexc("#FFEDAA")),
    ]

    def crown(cx, cy, r, cs):
        c0, c1, c2 = cs
        for (ox, oy, rr, c) in ((0, 0, 1.0, c0), (-0.07, -0.10, 0.90, c1), (-0.22, -0.28, 0.55, c2)):
            xx, yy, R = (cx + ox * r) * S, (cy + oy * r) * S, rr * r * S
            d.ellipse([xx - R, yy - R, xx + R, yy + R], fill=c255(c))
        # a few leaf dabs for a painterly rim
        for _ in range(4):
            a = rng.uniform(math.pi * 1.0, math.pi * 1.9)
            rr2 = r * rng.uniform(0.18, 0.3)
            px = cx + math.cos(a) * r * 0.78
            py = cy + math.sin(a) * r * 0.78
            xx, yy, R = px * S, py * S, rr2 * S
            d.ellipse([xx - R, yy - R, xx + R, yy + R], fill=c255(c1 if rng.random() < 0.6 else c2))

    rows = [(0.905, (28, 52), 0.060, 0), (0.93, (24, 42), 0.045, 1), (0.955, (20, 34), 0.040, 2)]
    for (yc, (r0, r1), step, si) in rows:
        x = rng.uniform(-20, 10)
        while x < W + 40:
            r = rng.uniform(r0, r1)
            cs = green_sets[int(rng.integers(3)) if si != 1 else int(rng.integers(3))]
            if rng.random() < 0.07 and si < 2:
                cs = blossom[int(rng.integers(3))]
            crown(x, H * yc + rng.uniform(-10, 10), r, cs)
            x += r * rng.uniform(0.85, 1.35)
    arr = np.asarray(img, np.float32) / 255.0
    rgb_p = box_down(arr[..., :3] * arr[..., 3:4], S)
    a = box_down(arr[..., 3], S)
    # ground band (bottom 6% always solid dark green)
    y0 = int(H * 0.938)
    ys = np.arange(H, dtype=np.float32)[:, None]
    t = np.clip((ys - y0) / (H - y0), 0, 1)
    band = ramp([(0, hexc("#2C8038")), (1, hexc("#1B5F2E"))], t[:, 0])[:, None, :] + (fbm(H, W, 6, 40, rng, 3, wrap=False) - 0.5)[..., None] * 0.05
    wgt = smoothstep(y0 - 3, y0 + 5, ys)
    straight = rgb_p / np.maximum(a[..., None], 1e-4)
    mixed = lerp(band, straight, (0.28 * a)[..., None])
    rgb_p = rgb_p * (1 - wgt[..., None]) + mixed * wgt[..., None]
    a = a * (1 - wgt) + wgt
    rgb_p = gblur(rgb_p, 0.9, wrap=False)
    a = gblur(a, 0.9, wrap=False)
    return rgb_p, a


@tex("skyline.png")
def gen_skyline():
    rng = np.random.default_rng(4101)
    W, H, S = 4096, 1024, 2
    top_c, hor_c = hexc("#3F9BE6"), hexc("#D6EEFB")
    yy = (np.arange(H, dtype=np.float32) + 0.5) / H
    t = np.clip(yy / 0.74, 0, 1) ** 1.12
    sky = np.repeat(lerp(top_c, hor_c, t[:, None])[:, None, :], W, axis=1).astype(np.float32)
    # soft sun bloom + a little tonal noise so the gradient is not banded
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    sun = np.exp(-(((xs - 0.68 * W) / 520) ** 2 + ((ys - 0.16 * H) / 300) ** 2))
    sky = lerp(sky, np.array([1.0, 0.98, 0.9], np.float32), (0.20 * sun)[..., None])
    sky += (fbm(H, W, 3, 12, rng, 3) - 0.5)[..., None] * 0.012

    # clouds (wrap-around aware)
    cloud_specs = []
    n_big = 7
    for i in range(n_big):
        cx = (i + rng.uniform(0.2, 0.8)) * W / n_big
        by = rng.uniform(0.14, 0.34) * H
        wd = rng.uniform(300, 620)
        ht = wd * rng.uniform(0.20, 0.28)
        cloud_specs.append((cx, by, wd, ht, 0.97))
    for i in range(6):
        cx = rng.uniform(0, W)
        by = rng.uniform(0.34, 0.44) * H
        wd = rng.uniform(220, 420)
        cloud_specs.append((cx, by, wd, wd * rng.uniform(0.12, 0.17), 0.75))
    for (cx, by, wd, ht, al) in sorted(cloud_specs, key=lambda c: c[1]):
        for ox in (-W, 0, W):
            _cloud(sky, rng, cx + ox, by, wd, ht, al)

    base_hz = hor_c * 0.55 + WHITE * 0.45 * 0.6 + hor_c * 0.45 * 0.4
    pal_far0 = [hexc(c) for c in ("#C7DDEE", "#C0D8EA", "#CBE0F0")]
    pal_far1 = [hexc(c) for c in ("#B9D3E6", "#B2CDE2", "#BDD7E9", "#B5CFE4")]
    pal_mid = [hexc(c) for c in ("#8FD0DB", "#9ED8E8", "#7DBBDC", "#A6D2EC", "#86C6D0", "#B0DCEB", "#93C8E4")]
    pas_mid = [hexc(c) for c in ("#E4C6D6", "#CFC8EE", "#BFE6D6")]
    pal_near = [hexc(c) for c in ("#6E9CC4", "#7BA5CC", "#6B8DB8", "#8AAAD0", "#7597B5", "#5E88B3", "#7FA1C9")]
    pas_near = [hexc(c) for c in ("#F0B6A8", "#C3B4EA", "#A5DEC5", "#F5D08A", "#F2A9C4")]

    out = sky
    layers = [
        # ground, plan args, haze (a0, a1), blur
        ("far0", 880, dict(hmin=190, hmax=400, wmin=44, wmax=100, palette=pal_far0, pastel=[], pastel_p=0.0,
                           shape_w={"flat": 50, "slant": 15, "rounded": 12, "stepped": 8, "spire": 10, "tower": 14},
                           overlap=(-10, 4), style="far"), (0.42, 0.28), 1.1),
        ("far1", 915, dict(hmin=220, hmax=520, wmin=60, wmax=150, palette=pal_far1, pastel=[], pastel_p=0.0,
                           shape_w={"flat": 45, "slant": 14, "rounded": 12, "stepped": 10, "spire": 10, "tower": 14, "skew": 3},
                           overlap=(-12, 4), style="far"), (0.24, 0.36), 0.7),
        ("mid", 955, dict(hmin=170, hmax=440, wmin=80, wmax=190, palette=pal_mid, pastel=pas_mid, pastel_p=0.12,
                          shape_w={"flat": 30, "slant": 14, "rounded": 14, "stepped": 12, "spire": 8, "tower": 10, "skew": 5, "ball": 2},
                          overlap=(-16, 6), style="mid"), (0.04, 0.22), 0.35),
        ("near", 990, dict(hmin=90, hmax=360, wmin=90, wmax=230, palette=pal_near, pastel=pas_near, pastel_p=0.15,
                           shape_w={"flat": 34, "slant": 14, "rounded": 12, "stepped": 8, "spire": 5, "tower": 14, "skew": 4},
                           overlap=(-16, 14), style="near"), (0.0, 0.14), 0.0),
    ]
    for (name, ground, plan, (a0, a1), blur) in layers:
        blds = _plan_layer(rng, W, ground, **plan)
        rgb_p, a = _render_layer(rng, blds, W, H, S)
        top_y = min(b["top"] for b in blds)
        rgb_p = _apply_haze(rgb_p, a, ground + 40, top_y, base_hz, a0, a1)
        if blur > 0:
            rgb_p = gblur(rgb_p, blur, wrap=False)
            a = gblur(a, blur, wrap=False)
        out = rgb_p + out * (1 - a[..., None])
    f_rgb, f_a = _foliage(rng, W, H, S)
    out = f_rgb + out * (1 - f_a[..., None])
    save_rgb(out, "skyline.png")


# --------------------------------------------------------------------------- 9. soft circle
@tex("soft_circle.png")
def gen_soft_circle():
    N = 256
    c = (np.arange(N) + 0.5) / N * 2 - 1
    d = np.sqrt(c[None, :] ** 2 + c[:, None] ** 2)
    a = 1 - smoothstep(0.0, 1.0, d)
    rgba = np.concatenate([np.ones((N, N, 3), np.float32), a[..., None]], axis=-1)
    save_rgba(rgba, "soft_circle.png")


# --------------------------------------------------------------------------- 10. light shaft
@tex("light_shaft.png")
def gen_light_shaft():
    rng = np.random.default_rng(1010)
    W, H = 128, 512
    x = (np.arange(W) + 0.5) / W
    y = (np.arange(H) + 0.5) / H
    edge = smoothstep(0.0, 0.62, 1 - np.abs(2 * x - 1))[None, :]
    fade = ((1 - smoothstep(0.0, 1.0, y)) ** 1.1)[:, None]
    n1 = value_noise(H, W, 3, 22, rng, wrap=False)
    n2 = value_noise(H, W, 5, 55, rng, wrap=False)
    n3 = value_noise(H, W, 2, 9, rng, wrap=False)
    streak = 0.55 * n1 + 0.25 * n2 + 0.20 * n3
    streak = np.clip(0.55 + (streak - 0.5) * 1.9, 0.18, 1.2)
    a = edge * fade * streak * 0.88
    a = np.clip(a, 0, 1)
    rgb = np.empty((H, W, 3), np.float32)
    rgb[:] = hexc("#FFF6D8")
    save_rgba(np.concatenate([rgb, a[..., None]], axis=-1), "light_shaft.png")


# --------------------------------------------------------------------------- 14. ring gradient
@tex("ring_gradient.png")
def gen_ring():
    W, H = 512, 16
    x = (np.arange(W) + 0.5) / W
    stops = [(0.0, hexc("#FFFFFF")), (0.20, hexc("#FFF3A6")), (0.44, hexc("#FF8FC7")), (0.68, hexc("#5FE3F5")),
             (0.88, hexc("#3E6FFF")), (1.0, hexc("#3E5CFF"))]
    # smooth (cosine) interpolation between stops for a painterly gradient
    pos = np.array([p for p, _ in stops])
    cols = np.array([c for _, c in stops])
    idx = np.clip(np.searchsorted(pos, x, side="right") - 1, 0, len(pos) - 2)
    t = (x - pos[idx]) / (pos[idx + 1] - pos[idx])
    t = t * t * (3 - 2 * t)
    rgb = cols[idx] * (1 - t[:, None]) + cols[idx + 1] * t[:, None]
    a = smoothstep(0.0, 0.14, x) * (1 - smoothstep(0.74, 1.0, x))
    row = np.concatenate([rgb, a[:, None]], axis=-1)
    save_rgba(np.repeat(row[None], H, axis=0).astype(np.float32), "ring_gradient.png")


# --------------------------------------------------------------------------- 12. confetti
@tex("confetti.png")
def gen_confetti():
    S, N = 8, 64
    m = Image.new("L", (N * S, N * S), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([6 * S, 16 * S, 58 * S, 48 * S], radius=9 * S, fill=255)
    a = pil_f(m.resize((N, N), Image.LANCZOS))
    ys, xs = np.mgrid[0:N, 0:N].astype(np.float32)
    # gentle lit-from-top-left shading, brightest = pure white so tint stays true
    sh = 1.0 - 0.08 * smoothstep(16, 48, ys) - 0.04 * smoothstep(6, 58, xs)
    # soft inner highlight band near the top edge and a faint crease line
    sh = sh + 0.10 * np.exp(-((ys - 21) / 2.2) ** 2)
    crease = np.exp(-((ys - 32 + (xs - 32) * 0.08) / 1.1) ** 2)
    sh = sh - 0.03 * crease
    rgb = np.repeat(np.clip(sh, 0, 1)[..., None], 3, axis=-1)
    save_rgba(np.concatenate([rgb, a[..., None]], axis=-1), "confetti.png")


# --------------------------------------------------------------------------- 13. star
@tex("star.png")
def gen_star():
    S, N = 4, 128
    m = Image.new("L", (N * S, N * S), 0)
    d = ImageDraw.Draw(m)
    cx = cy = N * S / 2
    R, r = 44 * S, 25 * S
    pts = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        rad = R if i % 2 == 0 else r
        pts.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad + 2 * S))
    d.polygon(pts, fill=255)
    # chubby: blur + threshold rounds the tips and inner corners
    m = m.filter(ImageFilter.GaussianBlur(7 * S / 2)).point(lambda v: 255 if v > 118 else (0 if v < 100 else int((v - 100) / 18 * 255)))
    a = pil_f(m.resize((N, N), Image.LANCZOS))
    glow = gblur(a, 8.5, wrap=False)
    glow2 = gblur(a, 3.5, wrap=False)
    ys, xs = np.mgrid[0:N, 0:N].astype(np.float32)
    rad = np.sqrt((xs - N / 2 + 0.5) ** 2 + (ys - N / 2 + 0.5) ** 2) / (N / 2)
    gl = np.clip(glow * 1.35 * 0.8 + glow2 * 0.25, 0, 1) * (1 - smoothstep(0.62, 1.0, rad))
    alpha = np.maximum(a, gl * 0.85)
    rgb = np.ones((N, N, 3), np.float32)
    save_rgba(np.concatenate([rgb, alpha[..., None]], axis=-1), "star.png")


# --------------------------------------------------------------------------- 11. window frame
@tex("window_frame.png")
def gen_window_frame():
    N = 1024
    steel = hexc("#22272B")
    hi = hexc("#434B52")
    rgba = np.zeros((N, N, 4), np.float32)
    rgba[..., :3] = steel
    bar = 7          # px width of dark steel bar on the right / bottom edges
    ys, xs = np.mgrid[0:N, 0:N].astype(np.float32)
    # distance (px) into the bar from its inner edge, along each axis
    dx = xs - (N - bar)            # >=0 inside right bar
    dy = ys - (N - bar)
    inside_r = np.clip(dx + 0.5, 0, 1) * (dx < bar)
    inside_b = np.clip(dy + 0.5, 0, 1) * (dy < bar)
    a = np.maximum(inside_r, inside_b)
    # subtle bevel: lighter 1-2px line on the pane-side edge of each bar
    hl = np.maximum(np.exp(-((dx - 0.5) / 1.1) ** 2) * (dx > -1), np.exp(-((dy - 0.5) / 1.1) ** 2) * (dy > -1))
    hl = hl * (a > 0.5)
    rgb = lerp(steel, hi, (0.55 * hl)[..., None])
    rgba[..., :3] = rgb
    rgba[..., 3] = a
    save_rgba(rgba, "window_frame.png")


# --------------------------------------------------------------------------- 7. concrete
@tex("concrete.png")
def gen_concrete():
    rng = np.random.default_rng(7007)
    N = 1024
    base = hexc("#A9ABAD")
    n_low = fbm(N, N, 3, 3, rng, 4)
    n_mid = fbm(N, N, 14, 14, rng, 3)
    n_fine = value_noise(N, N, 256, 256, rng)
    m = (n_low - 0.5) * 0.085 + (n_mid - 0.5) * 0.040 + (n_fine - 0.5) * 0.016
    warm = (fbm(N, N, 4, 4, rng, 3) - 0.5) * 0.02
    img = np.empty((N, N, 3), np.float32)
    img[:] = base
    img *= (1 + m)[..., None]
    img[..., 0] += warm * 0.5
    img[..., 2] -= warm * 0.5
    # tiny air pores
    pores = np.zeros((N, N), np.float32)
    for _ in range(110):
        px, py = int(rng.integers(N)), int(rng.integers(N))
        pores[py, px] = rng.uniform(0.4, 1.0)
    pores = gblur(pores, 1.1)
    img *= (1 - np.clip(pores * 4.0, 0, 0.08))[..., None]
    # formwork tie holes on a 256px grid + faint water stain below each
    ys, xs = np.mgrid[0:N, 0:N].astype(np.float32)
    for gy in range(4):
        for gx in range(4):
            cx, cy = 128 + 256 * gx, 128 + 256 * gy
            d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2)
            hole = 1 - smoothstep(5.0, 10.5, d)
            rim = np.exp(-((d - 12.5) / 2.6) ** 2)
            img *= (1 - 0.15 * hole)[..., None]
            img *= (1 + 0.012 * rim)[..., None]
            stain = np.exp(-((xs - cx) / (6 + 0.05 * np.maximum(ys - cy, 0))) ** 2) * smoothstep(cy, cy + 8, ys) * (1 - smoothstep(cy + 8, cy + 105, ys))
            img *= (1 - 0.022 * stain)[..., None]
    save_rgb(img, "concrete.png")


# --------------------------------------------------------------------------- 8. volleyball text
@tex("volleyball_text.png")
def gen_text():
    W, H, S = 1024, 192, 4
    word = "VOLLEYBALL"
    fp = None
    for cand in (r"C:\Windows\Fonts\ariblk.ttf", r"C:\Windows\Fonts\arialbd.ttf"):
        if os.path.exists(cand):
            fp = cand
            break
    if fp is None:
        raise RuntimeError("no bold font found")
    track = 0.15
    size = 100
    # fit total width to ~ 984 px
    for _ in range(12):
        font = ImageFont.truetype(fp, size * S)
        adv = [font.getlength(c) for c in word]
        total = sum(adv) + track * size * S * (len(word) - 1)
        size = size * (984 * S) / total
    font = ImageFont.truetype(fp, int(round(size * S)))
    adv = [font.getlength(c) for c in word]
    total = sum(adv) + track * size * S * (len(word) - 1)
    # letters are rendered with a vertical stretch to fill more of the strip
    canvas = Image.new("L", (W * S, H * S), 0)
    x = (W * S - total) / 2
    bb = font.getbbox("V")
    cap_h = bb[3] - bb[1]
    stretch = min(1.22, (H * S * 0.66) / cap_h)
    lay = Image.new("L", (W * S, int(H * S / stretch) + 4), 0)
    dl = ImageDraw.Draw(lay)
    ytop = (lay.height - cap_h) / 2 - bb[1]
    for c, a_ in zip(word, adv):
        dl.text((x, ytop), c, font=font, fill=255)
        x += a_ + track * size * S
    lay = lay.resize((W * S, H * S), Image.LANCZOS)
    # round the corners: blur + threshold
    lay = lay.filter(ImageFilter.GaussianBlur(5.5 * S / 2))
    lay = lay.point(lambda v: 255 if v > 150 else (0 if v < 112 else int((v - 112) / 38 * 255)))
    a = pil_f(lay.resize((W, H), Image.LANCZOS))
    rgb = np.ones((H, W, 3), np.float32)
    save_rgba(np.concatenate([rgb, a[..., None]], axis=-1), "volleyball_text.png")


# --------------------------------------------------------------------------- 3. wood deck
@tex("wood_deck.png")
def gen_wood():
    rng = np.random.default_rng(3003)
    N = 1024
    rows = 8
    rh = N // rows
    c_dark, c_light = hexc("#6B4128"), hexc("#8A5636")
    # long streaky grain (tileable): very stretched along x
    g1 = fbm(N, N, 70, 2, rng, 3, 0.55)
    g2 = fbm(N, N, 220, 3, rng, 2, 0.5)
    ring_warp = (fbm(N, N, 4, 3, rng, 3) - 0.5)
    ring_warp2 = (fbm(N, N, 6, 2, rng, 2) - 0.5)
    low_var = fbm(N, N, 3, 3, rng, 3)
    wear = fbm(N, N, 5, 5, rng, 4)
    img = np.zeros((N, N, 3), np.float32)
    prev_first = -999
    for r in range(rows):
        y0 = r * rh
        # 1 or 2 end joints, staggered
        nj = 1 if rng.random() < 0.55 else 2
        joints = sorted(set(int(v) for v in rng.uniform(0, N, nj)))
        if len(joints) == 1 and abs(joints[0] - prev_first) < 200:
            joints[0] = (joints[0] + 380) % N
        prev_first = joints[0]
        joints = sorted(joints)
        segs = []
        for i, j in enumerate(joints):
            j2 = joints[(i + 1) % len(joints)]
            ln = (j2 - j) % N or N
            segs.append((j, ln))
        for (jx, ln) in segs:
            xs_i = (jx + np.arange(ln)) % N                   # absolute x of this board segment
            t = rng.random()
            col = lerp(c_dark, c_light, t)
            col = col * (1 + rng.normal(0, 0.018, 3).astype(np.float32))
            shift = int(rng.integers(N))
            yoff = int(rng.integers(N))
            yy = (np.arange(rh) + yoff) % N
            xx = (xs_i + shift) % N
            G1 = g1[np.ix_(yy, xx)]
            G2 = g2[np.ix_(yy, xx)]
            # growth rings: warped sinusoid in board-local y
            ylocal = np.arange(rh, dtype=np.float32)[:, None] + 0 * xs_i[None, :].astype(np.float32)
            wp = ring_warp[np.ix_(yy, xx)] * 70 + ring_warp2[np.ix_(yy, xx)] * 28
            period = rng.uniform(15, 26)
            ph = rng.uniform(0, 6.28)
            rings = 0.5 + 0.5 * np.sin(2 * math.pi * (ylocal + wp) / period + ph)
            rings = rings ** 2.2
            streak = (G1 - 0.5) * 0.9 + (G2 - 0.5) * 0.55
            lines = np.clip((G2 - 0.62) * 3.2, 0, 1)          # occasional darker pores/lines
            shade = 1 + streak * 0.34 - rings * 0.15 - lines * 0.10
            lv = low_var[np.ix_(yy, xx)]
            shade *= 1 + (lv - 0.5) * 0.12
            wv = wear[np.ix_(yy, xx)]
            shade *= 1 + (smoothstep(0.55, 0.85, wv) - 0.3) * 0.07
            seg = col[None, None, :] * shade[..., None]
            # bevelled board edges: light on top lip, dark toward the gap
            ey = np.arange(rh, dtype=np.float32)[:, None]
            gap = 3.0
            top_hl = np.exp(-((ey - (gap + 1.5)) / 2.0) ** 2) * 0.10
            bot_sh = smoothstep(rh - 8, rh, ey) * 0.16
            top_sh = (1 - smoothstep(gap, gap + 5, ey)) * 0.08
            seg = seg * (1 + top_hl - bot_sh - top_sh)[..., None]
            # end joints: dark vertical gap at the board start (+ soft bevel at both ends)
            ex = np.arange(ln, dtype=np.float32)[None, :]
            seg = seg * (1 - 0.10 * (1 - smoothstep(3, 8, ex)) - 0.10 * smoothstep(ln - 8, ln - 2, ex))[..., None]
            gapx = 1 - smoothstep(1.2, 3.2, ex)
            gap_col = np.array([0.105, 0.065, 0.04], np.float32)
            seg = lerp(seg, gap_col, (gapx * 0.95)[..., None] * np.ones((rh, 1, 1), np.float32))
            # gap between board rows (top 3px, soft)
            gapy = 1 - smoothstep(gap - 1.2, gap + 0.6, ey)
            seg = lerp(seg, gap_col, (gapy * 0.96)[..., None] * np.ones((1, ln, 1), np.float32))
            img[np.ix_(np.arange(y0, y0 + rh), xs_i)] = seg
    # global soft wear / dirt
    img *= (1 + (fbm(N, N, 2, 2, rng, 3) - 0.5) * 0.08)[..., None]
    save_rgb(img, "wood_deck.png")


# --------------------------------------------------------------------------- 4. leaf tile
def _leaf(rgb, a, cx, cy, L, Wd, ang, base, tipc, dark, light, N, shadow=None):
    """analytic painted leaf, drawn with wrap-around into premult canvas (rgb, a)"""
    R = int(L / 2 * 1.08 + 8)
    ca, sa = math.cos(ang), math.sin(ang)
    for ox in (-N, 0, N):
        for oy in (-N, 0, N):
            x, y = cx + ox, cy + oy
            if x + R < 0 or x - R > N or y + R < 0 or y - R > N:
                continue
            x0, y0 = int(x) - R, int(y) - R
            ys, xs = np.mgrid[y0:y0 + 2 * R, x0:x0 + 2 * R].astype(np.float32)
            dx, dy = xs + 0.5 - x, ys + 0.5 - y

            def prof(ddx, ddy):
                u = (ddx * ca + ddy * sa) / (L / 2)
                v = -ddx * sa + ddy * ca
                uu = np.clip(u, -1, 1)
                tt = (uu + 1) / 2
                half = (Wd / 2) * np.maximum(np.sin(math.pi * tt), 0) ** 0.62 * (1.06 - 0.22 * tt)
                q = np.where(np.abs(u) > 1, -5, half - np.abs(v))
                return u, v, half, q

            u, v, half, q = prof(dx, dy)
            m = np.clip(q + 0.5, 0, 1)
            if shadow is not None:
                _, _, _, qs = prof(dx - shadow[0], dy - shadow[1])
                ms = np.clip(qs / 3.0 + 0.5, 0, 1) * 0.55
                blit(rgb, a, np.broadcast_to(dark * 0.55, (2 * R, 2 * R, 3)), ms, x0, y0)
            tip = smoothstep(-0.1, 1.0, u) * 0.75
            col = lerp(base, tipc, tip[..., None])
            side = np.clip(v / (half + 1e-3), -1, 1)
            col = col * (1 - 0.10 * smoothstep(-0.3, 0.9, side))[..., None]
            col = col * (1 + 0.07 * smoothstep(0.3, -0.9, side))[..., None]
            rib = np.exp(-(v / 1.6) ** 2) * (1 - smoothstep(0.55, 0.95, u)) * smoothstep(-1.0, -0.6, u)
            col = lerp(col, light, (rib * 0.32)[..., None])
            edge = smoothstep(0.0, 3.2, q)
            col = lerp(dark, col, (0.55 + 0.45 * edge)[..., None])
            blit(rgb, a, col.astype(np.float32), m, x0, y0)


@tex("leaf_tile.png")
def gen_leaf():
    rng = np.random.default_rng(4004)
    N1, S = 512, 2
    N = N1 * S
    rgb = np.zeros((N, N, 3), np.float32)
    a = np.zeros((N, N), np.float32)
    rgb[:] = hexc("#1B5E2E")
    a[:] = 1.0
    light_field = fbm(N, N, 3, 3, rng, 3)
    lf2 = fbm(N, N, 7, 7, rng, 2)
    stops = [(0.0, hexc("#1C6431")), (0.30, hexc("#1F6B33")), (0.52, hexc("#2E8B2E")), (0.76, hexc("#58B83A")), (1.0, hexc("#9BD84A"))]
    n_leaf = 520
    for i in range(n_leaf):
        cx, cy = rng.uniform(0, N), rng.uniform(0, N)
        order = i / n_leaf
        lf = 0.65 * light_field[int(cy) % N, int(cx) % N] + 0.35 * lf2[int(cy) % N, int(cx) % N]
        h = np.clip(0.04 + 0.62 * order ** 1.1 + (lf - 0.5) * 0.55 + rng.normal(0, 0.05), 0, 1)
        base = ramp(stops, h)
        tipc = lerp(base, hexc("#C6EE6A"), 0.42 + 0.2 * h)
        dark = lerp(base, hexc("#12482A"), 0.55)
        light = lerp(base, hexc("#E6F8A0"), 0.55)
        L = rng.uniform(70, 118) * S / 2 * (1.0 if order > 0.35 else 1.2)
        Wd = L * rng.uniform(0.50, 0.66)
        ang = rng.uniform(0, 2 * math.pi)
        _leaf(rgb, a, cx, cy, L, Wd, ang, base, tipc, dark, light, N, shadow=(3.5 * S / 2, 5.0 * S / 2))
    img = box_down(rgb, S)
    img = gblur(img, 0.5, wrap=True)
    save_rgb(img, "leaf_tile.png")


# --------------------------------------------------------------------------- 5. palm frond
def _rot(v, ang):
    c, s = math.cos(ang), math.sin(ang)
    return np.array([v[0] * c - v[1] * s, v[0] * s + v[1] * c])


def _finish_rgba(img_big, N):
    arr = np.asarray(img_big.resize((N, N), Image.LANCZOS), np.float32) / 255.0
    rgb = bleed_rgb(arr[..., :3], arr[..., 3])
    return np.concatenate([rgb, arr[..., 3:4]], axis=-1)


@tex("palm_frond.png")
def gen_palm():
    rng = np.random.default_rng(5005)
    N, S = 512, 4
    img = Image.new("RGBA", (N * S, N * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # midrib: slightly arching, bottom-centre to top
    P0, P1, P2 = (256 * S, 528 * S), (240 * S, 250 * S), (300 * S, 22 * S)
    mid = bez2(P0, P1, P2, 400)
    tg, nm = normals_of(mid)
    nl = 14
    leaflets = []
    for k in range(nl):
        s = 0.21 + 0.76 * (k / (nl - 1))
        for side in (-1, 1):
            leaflets.append((s, side))
    leaflets.sort(key=lambda z: z[0])

    def lenprof(s):
        if s < 0.36:
            return 0.70 + 0.30 * math.sin(min(1.0, (s - 0.2) / 0.16) * math.pi / 2)
        return lerp(1.0, 0.24, ((s - 0.36) / 0.64) ** 0.9)

    greens = dict(
        dark=hexc("#2C8A2F"), mid=hexc("#47B332"), light=hexc("#8FD14A"), hi=hexc("#C4E86A"),
        under=hexc("#2A7E3C"), outline=hexc("#2A8030"))
    for (s, side) in leaflets:
        idx = int(s * (len(mid) - 1))
        p = mid[idx]
        T = tg[idx]
        Nn = np.array([T[1], -T[0]])
        if Nn[0] < 0:
            Nn = -Nn
        Nside = Nn * side
        a0 = math.radians(lerp(80, 52, s) + rng.normal(0, 3))
        droop = math.radians(lerp(58, 78, s) + rng.normal(0, 5))
        L = 232 * S * lenprof(s) * rng.uniform(0.94, 1.05)
        d0 = T * math.cos(a0) + Nside * math.sin(a0)
        a2 = a0 + droop
        d1 = T * math.cos(a2) + Nside * math.sin(a2)
        pc = p + d0 * L * 0.55
        pe = pc + d1 * L * 0.52
        pe = pe + np.array([0, 1.0]) * L * 0.10
        pts = bez2(p, pc, pe, 46)
        t = np.linspace(0, 1, len(pts))
        wmax = 8.0 * S * rng.uniform(0.9, 1.1)
        w = wmax * (t ** 0.4) * ((1 - t) ** 0.85) / (0.4 ** 0.4 * 0.6 ** 0.85) + 0.4 * S * (1 - t)
        w = np.minimum(w, wmax * 1.15)
        w[-1] = 0
        flip = rng.random() < 0.22
        tone = rng.uniform(-0.05, 0.05)
        _, nl_ = normals_of(pts)
        lead_is_left = np.dot(nl_[len(pts) // 3], T) > 0
        up_c = ramp([(0, greens["mid"]), (0.5, greens["light"]), (1, greens["hi"])], t)
        lo_c = ramp([(0, greens["dark"]), (0.5, lerp(greens["dark"], greens["mid"], 0.6)), (1, greens["mid"])], t)
        if flip:
            up_c = lerp(lo_c, greens["under"], 0.5)
            lo_c = lerp(lo_c, greens["under"], 0.8) * 0.92
        up_c = np.clip(up_c * (1 + tone), 0, 1)
        lo_c = np.clip(lo_c * (1 + tone), 0, 1)
        colL, colR = (up_c, lo_c) if lead_is_left else (lo_c, up_c)
        ol = greens["outline"]
        draw_strip(d, pts, w + 0.9 * S, w + 0.9 * S, np.tile(ol, (len(pts), 1)), np.tile(ol, (len(pts), 1)))
        draw_strip(d, pts, w, w, colL, colR)
        fold = np.clip(up_c * 1.05 + 0.04, 0, 1)
        draw_strip(d, pts, w * 0.12, w * 0.12, fold, fold)
    # terminal leaflets at the tip
    tp = mid[-1]
    for ang in (-0.5, 0.0, 0.5):
        T = tg[-1]
        dd_ = _rot(T, ang)
        pts = bez2(tp - T * 6 * S, tp + dd_ * 28 * S, tp + dd_ * 62 * S + np.array([0, 4 * S]) * abs(ang) * 2, 24)
        t = np.linspace(0, 1, 24)
        w = 5.0 * S * (t ** 0.4) * (1 - t) ** 0.9 * 1.9
        w[-1] = 0
        ol = greens["outline"]
        draw_strip(d, pts, w + 1.6 * S, w + 1.6 * S, np.tile(ol, (24, 1)), np.tile(ol, (24, 1)))
        c = ramp([(0, greens["mid"]), (1, greens["light"])], t)
        draw_strip(d, pts, w, w, c, c * 0.93)
    # midrib on top: tapering, pale yellow-green with darker edge
    t = np.linspace(0, 1, len(mid))
    wm = (9.5 - 6.5 * t) * S / 2
    ol = hexc("#4E8F2A")
    draw_strip(d, mid, wm + 1.2 * S, wm + 1.2 * S, np.tile(ol, (len(mid), 1)), np.tile(ol, (len(mid), 1)))
    cm = ramp([(0, hexc("#9CCB52")), (1, hexc("#CFEA7A"))], t)
    draw_strip(d, mid, wm, wm, cm, np.clip(cm * 0.9, 0, 1))
    hl = np.clip(cm * 1.08 + 0.04, 0, 1)
    draw_strip(d, mid, wm * 0.35, wm * 0.35, hl, hl)
    save_rgba(_finish_rgba(img, N), "palm_frond.png")


# --------------------------------------------------------------------------- 6. fern / bird's-nest clump
@tex("fern.png")
def gen_fern():
    rng = np.random.default_rng(6006)
    N, S = 512, 4
    img = Image.new("RGBA", (N * S, N * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    base_pt = np.array([256.0, 506.0]) * S
    nf = 33
    fronds = [lerp(-80, 80, (i + rng.uniform(-0.3, 0.3)) / (nf - 1)) for i in range(nf)]
    order = sorted(range(nf), key=lambda i: -abs(fronds[i]) + rng.uniform(-8, 8))
    greens = dict(
        dark=hexc("#1F6B33"), mid=hexc("#2E9B3A"), lt=hexc("#58C23E"), hi=hexc("#9BD84A"), rib=hexc("#C9EA7E"), ol=hexc("#195A2A"))

    def dirv(a):
        return np.array([math.sin(a), -math.cos(a)])

    for rank, i in enumerate(order):
        th = math.radians(fronds[i])
        inner = 1 - abs(fronds[i]) / 90.0
        L = (205 + 255 * inner ** 1.15) * S * rng.uniform(0.9, 1.05) * lerp(1.0, 0.85, float(smoothstep(45, 80, abs(fronds[i]))))
        sg = 1 if th >= 0 else -1
        p0 = base_pt + np.array([rng.uniform(-7, 7) * S, rng.uniform(-3, 3) * S])
        n = 70
        wmax = rng.uniform(30, 40) * S * (0.78 + 0.35 * inner)
        for _try in range(30):
            p1 = p0 + dirv(th * 0.62) * L * 0.38
            p2 = p0 + dirv(th * 0.95) * L * 0.74 + np.array([0, 1]) * L * 0.05 * abs(math.sin(th))
            p3 = p0 + dirv(th * 1.22) * L + np.array([0, 1]) * L * (0.07 + 0.22 * (1 - inner) ** 1.4) * abs(math.sin(th))
            pts = bez3(p0, p1, p2, p3, n)
            if np.abs(pts[:, 0] - 256 * S).max() + wmax * 0.9 < 250 * S and pts[:, 1].min() - wmax * 0.2 > 6 * S:
                break
            L *= 0.97
        t = np.linspace(0, 1, n)
        prof = np.minimum(1.0, (t / 0.18) ** 0.55) * (1 - t ** 2.2) ** 0.7
        wav_l = 1 + 0.085 * np.sin(2 * math.pi * (t * rng.uniform(4.5, 7)) + rng.uniform(0, 6.28)) * smoothstep(0.1, 0.4, t)
        wav_r = 1 + 0.085 * np.sin(2 * math.pi * (t * rng.uniform(4.5, 7)) + rng.uniform(0, 6.28)) * smoothstep(0.1, 0.4, t)
        wl = wmax * prof * wav_l
        wr = wmax * prof * wav_r
        wl[-1] = wr[-1] = 0
        lift = np.clip(0.25 + 0.75 * inner + rng.normal(0, 0.06), 0, 1)
        cbase = lerp(greens["dark"], greens["mid"], lift)
        cmid = lerp(greens["mid"], greens["lt"], lift)
        ctip = lerp(greens["lt"], greens["hi"], np.clip(lift * 0.9 + 0.1, 0, 1))
        cc = ramp([(0, cbase), (0.4, cmid), (1, ctip)], t)
        tg_, nm_ = normals_of(pts)
        colL = np.clip(cc * 1.07, 0, 1)
        colR = np.clip(cc * 0.90, 0, 1)
        if sg < 0:
            colL, colR = colR, colL
        ol = np.tile(greens["ol"], (n, 1))
        draw_strip(d, pts, wl + 1.8 * S, wr + 1.8 * S, ol, ol)
        draw_strip(d, pts, wl, wr, colL, colR)
        for tv in np.linspace(0.08, 0.9, 16):
            k = int(tv * (n - 1))
            pcen = pts[k]
            Tk, Nk = tg_[k], nm_[k]
            for sd, wk in ((1, wl[k]), (-1, wr[k])):
                if wk < 4 * S:
                    continue
                dirw = Tk * 0.62 + Nk * sd * 0.78
                pe = pcen + dirw * wk * 0.92
                vc = np.clip(cc[k] * (1.10 if sd == (1 if sg > 0 else -1) else 0.97) + 0.03, 0, 1)
                d.line([tuple(pcen), tuple(pe)], fill=c255(vc), width=int(0.9 * S))
        wm = np.maximum(2.0 * S * (1 - 0.7 * t), 0.5 * S)
        cr = ramp([(0, hexc("#B6D869")), (1, greens["rib"])], t)
        draw_strip(d, pts, wm, wm, cr, np.clip(cr * 0.92, 0, 1))
    d.ellipse([(256 - 22) * S, (503 - 12) * S, (256 + 22) * S, (503 + 12) * S], fill=c255(hexc("#4A3A1E")))
    save_rgba(_finish_rgba(img, N), "fern.png")


# --------------------------------------------------------------------------- 2. banner paint
def _brush(base_img, P, wmax, cols, S, rng, bristles=64, alpha=1.0, lenjit=0.22):
    """one painterly dry-brush swoosh along bezier P (4 pts, 1x coords) composited into base_img (RGBA)"""
    W2, H2 = base_img.size
    n = 260
    pts = bez3(*[np.asarray(p, np.float64) * S for p in P], n)
    t = np.linspace(0, 1, n)
    tg, nm = normals_of(pts)
    wprof = np.sin(math.pi * np.clip(t, 0, 1) ** 0.82) ** 0.55
    wprof = wprof * (1 + 0.10 * np.sin(t * 9 + rng.uniform(0, 6)))
    wr = wmax * S * wprof
    cstops = [(i / (len(cols) - 1), hexc(c)) for i, c in enumerate(cols)]
    cc = ramp(cstops, t)
    layer = Image.new("RGBA", (W2, H2), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    body_w = 0.90
    draw_strip(d, pts, wr * body_w, wr * body_w, np.clip(cc, 0, 1), np.clip(cc * 0.97, 0, 1))
    streak = Image.new("RGBA", (W2, H2), (0, 0, 0, 0))
    ds = ImageDraw.Draw(streak)
    for j in range(bristles):
        v = np.sign(rng.uniform(-1, 1)) * (rng.uniform(0, 1) ** 0.55)
        av = abs(v)
        edge = smoothstep(0.7, 1.0, av)
        t0 = rng.uniform(0.0, 0.05 + 0.20 * edge ** 1.5)
        t1 = 1 - rng.uniform(0.0, 0.06 + lenjit * edge ** 1.5 * 1.4)
        if t1 - t0 < 0.1:
            continue
        i0, i1 = int(t0 * (n - 1)), int(t1 * (n - 1))
        line = pts[i0:i1 + 1] + nm[i0:i1 + 1] * (v * wr[i0:i1 + 1, None] * (1.0 + 0.02 * rng.normal()))
        br = 1 + rng.normal(0, 0.055) + 0.04 * (1 if v < 0 else -0.6)
        col = np.clip(cc[(i0 + i1) // 2] * br, 0, 1)
        wdt = max(2, int(wmax * S * 2 / bristles * rng.uniform(1.4, 2.6)))
        al = int(255 * rng.uniform(0.18, 0.5)) if av < 0.8 else int(255 * rng.uniform(0.75, 1.0))
        ds.line([tuple(p) for p in line], fill=tuple(int(c * 255) for c in col) + (al,), width=wdt, joint="curve")
    for j in range(5):
        v = rng.uniform(-0.55, 0.55)
        i0, i1 = int(0.06 * (n - 1)), int(rng.uniform(0.6, 0.92) * (n - 1))
        line = pts[i0:i1] + nm[i0:i1] * (v * wr[i0:i1, None])
        col = np.clip(cc[(i0 + i1) // 2] * rng.choice([0.9, 1.1]) + (0.04 if rng.random() < 0.5 else 0), 0, 1)
        ds.line([tuple(p) for p in line], fill=tuple(int(c * 255) for c in col) + (70,), width=max(2, int(wmax * S * 0.05)), joint="curve")
    layer = Image.alpha_composite(layer, streak)
    if alpha < 1.0:
        arr = np.asarray(layer).copy()
        arr[..., 3] = (arr[..., 3].astype(np.float32) * alpha).astype(np.uint8)
        layer = Image.fromarray(arr, "RGBA")
    return Image.alpha_composite(base_img, layer)


def _ink_blob(d, cx, cy, r, rng, S):
    for _ in range(int(rng.integers(6, 11))):
        a = rng.uniform(0, 2 * math.pi)
        rr = r * rng.uniform(0.0, 0.55)
        rad = r * rng.uniform(0.35, 0.75)
        x, y = cx + math.cos(a) * rr, cy + math.sin(a) * rr
        d.ellipse([(x - rad) * S, (y - rad) * S, (x + rad) * S, (y + rad) * S], fill=(22, 20, 24, 255))


@tex("banner_paint.png")
def gen_banner():
    rng = np.random.default_rng(2002)
    W, H, S = 1024, 2048, 2
    W2, H2 = W * S, H * S
    bg = hexc("#F4F1EC")
    paper = (fbm(H2, W2, 9, 5, rng, 4, wrap=False) - 0.5) * 0.020 + (value_noise(H2, W2, H2 // 2, W2 // 2, rng, wrap=False) - 0.5) * 0.012
    base = np.empty((H2, W2, 3), np.float32)
    base[:] = bg
    base *= (1 + paper)[..., None]
    img = Image.fromarray(to_u8(base), "RGB").convert("RGBA")
    wash = Image.new("RGBA", (W2, H2), (0, 0, 0, 0))
    dw = ImageDraw.Draw(wash)
    for (cx, cy, rx, ry, c) in [(200, 360, 360, 220, (255, 196, 225, 90)), (800, 1050, 380, 240, (190, 235, 250, 90)),
                                (250, 1700, 420, 230, (255, 235, 170, 80)), (800, 1900, 300, 200, (220, 200, 255, 80))]:
        dw.ellipse([(cx - rx) * S, (cy - ry) * S, (cx + rx) * S, (cy + ry) * S], fill=c)
    wash = wash.filter(ImageFilter.GaussianBlur(70 * S))
    img = Image.alpha_composite(img, wash)

    strokes = [
        (((-160, 560), (360, 430), (560, -110), (1190, 120)), 150, ["#FF3D9A", "#FF5C74", "#FF8A1F"], 1.0),
        (((-150, 280), (320, 780), (700, 240), (1200, 900)), 128, ["#FFD21F", "#FFB11F", "#FF8A1F"], 0.97),
        (((1190, 420), (700, 130), (320, 560), (-160, 330)), 64, ["#8E3DFF", "#B03DE0", "#FF3D9A"], 0.95),
        (((-170, 1500), (300, 1000), (700, 1330), (1210, 790)), 175, ["#1FC8E8", "#2F9BFF", "#2F6BFF"], 0.98),
        (((1170, 1020), (700, 1280), (300, 900), (-100, 1270)), 60, ["#FF3D9A", "#FF8A1F"], 0.93),
        (((-160, 1220), (420, 1960), (700, 1100), (1190, 1880)), 150, ["#2F6BFF", "#6A4DFF", "#8E3DFF"], 0.97),
        (((1190, 1500), (760, 1480), (500, 1760), (-90, 1640)), 62, ["#FFD21F", "#FF8A1F", "#FF3D9A"], 0.94),
        (((-130, 2070), (300, 1700), (700, 2280), (1200, 1760)), 145, ["#8E3DFF", "#FF3D9A", "#FF8A1F"], 0.97),
        (((900, -60), (1040, 380), (570, 700), (740, 1150)), 76, ["#1FC8E8", "#2F6BFF"], 0.90),
        (((140, 760), (-60, 1050), (280, 1400), (120, 1780)), 56, ["#FFD21F", "#FF8A1F"], 0.9),
        (((1140, 1700), (850, 1560), (700, 2010), (240, 2130)), 52, ["#1FC8E8", "#8E3DFF"], 0.9),
    ]
    for (P, wmax, cols, al) in strokes:
        img = _brush(img, P, wmax, cols, S, rng, bristles=int(34 + wmax * 0.5), alpha=al)

    ink = Image.new("RGBA", (W2, H2), (0, 0, 0, 0))
    di = ImageDraw.Draw(ink)
    for (cx, cy, r) in [(760, 330, 34), (180, 900, 26), (870, 1430, 40), (300, 1590, 22), (640, 1880, 30)]:
        _ink_blob(di, cx, cy, r, rng, S)
        ang = rng.uniform(0, 2 * math.pi)
        for _ in range(int(rng.integers(14, 24))):
            a = ang + rng.normal(0, 0.9)
            dist = r * rng.uniform(1.0, 4.2) * rng.uniform(0.8, 1.6)
            rr = max(1.2, r * 0.22 * rng.uniform(0.15, 1.0) / (1 + dist / (r * 3.5)))
            x, y = cx + math.cos(a) * dist, cy + math.sin(a) * dist
            di.ellipse([(x - rr) * S, (y - rr) * S, (x + rr) * S, (y + rr) * S], fill=(22, 20, 24, 255))
    for (P, w) in [(((90, 140), (350, 60), (520, 260), (800, 120)), 7), (((200, 1760), (380, 1700), (520, 1820), (860, 1700)), 6),
                   (((960, 780), (820, 900), (900, 1020), (700, 1130)), 5)]:
        pts = bez3(*[np.asarray(p, np.float64) * S for p in P], 160)
        t = np.linspace(0, 1, 160)
        w_ = w * S * (np.sin(math.pi * t ** 0.9) ** 0.8)
        w_[0] = w_[-1] = 0
        ink_c = np.tile(hexc("#161418"), (160, 1))
        draw_strip(di, pts, w_, w_, ink_c, ink_c)
    img = Image.alpha_composite(img, ink)
    out = pil_f(img.convert("RGB").resize((W, H), Image.LANCZOS))
    save_rgb(out, "banner_paint.png")


# =========================== MORE GENERATORS BELOW ===========================


def main():
    os.makedirs(OUT, exist_ok=True)
    names = sys.argv[1:]
    todo = [n for n in REG if (not names or any(k in n for k in names))]
    for n in todo:
        t0 = time.time()
        REG[n]()
        print("%-20s %.1fs" % (n, time.time() - t0), flush=True)


if __name__ == "__main__":
    main()

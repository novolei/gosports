"""Soundtrack for the promo: an arrangement of the game's own themes (tools/gen_audio.py: bgm_match 126 BPM, bgm_menu 104 BPM), both
time-stretched to 120 BPM (one bar = exactly 2.000 s) and re-cut into sections that follow the edit, with risers / crashes / impacts
between them.  Fully synthesised, no samples.  Output: promo_work/music.wav (48 kHz stereo float).

  python promo/music.py [--total 190]
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import gen_audio as G  # noqa: E402

SR = 48000
BAR = 2.0                      # seconds at 120 BPM


def to48(x: np.ndarray, src_sr: int = 44100) -> np.ndarray:
    """(2, n) or (n,) at 44.1 kHz -> (n, 2) float32 at 48 kHz"""
    if x.ndim == 1:
        x = np.stack([x, x])
    y = signal.resample_poly(x, 160, 147, axis=1)
    return y.T.astype(np.float32)


def stretch(st: np.ndarray, factor: float) -> np.ndarray:
    """tempo change by `factor` (>1 = faster) with ffmpeg atempo; st is (2, n) at 44.1 kHz; returns (n, 2) at 48 kHz"""
    with tempfile.TemporaryDirectory() as td:
        a, b = Path(td) / "a.wav", Path(td) / "b.wav"
        sf.write(a, st.T, G.SR, subtype="FLOAT")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(a), "-af", f"atempo={factor:.6f},aresample={SR}", str(b)], check=True)
        y, sr = sf.read(b, dtype="float32")
    return y


def bars(a: np.ndarray, b0: int, n: int) -> np.ndarray:
    s = int(round(b0 * BAR * SR))
    e = s + int(round(n * BAR * SR))
    out = a[s:e]
    if len(out) < e - s:
        out = np.concatenate([out, np.zeros((e - s - len(out), 2), np.float32)])
    return out


def xfade_join(parts: list[np.ndarray], fade: float = 0.04) -> np.ndarray:
    k = int(fade * SR)
    out = parts[0].copy()
    for p in parts[1:]:
        p = p.copy()
        if k > 0 and len(out) > k and len(p) > k:
            ramp = np.linspace(0, 1, k, dtype=np.float32)[:, None]
            out[-k:] = out[-k:] * (1 - ramp) + p[:k] * ramp
            out = np.concatenate([out, p[k:]])
        else:
            out = np.concatenate([out, p])
    return out


def lowpass_sweep(a: np.ndarray, f0: float, f1: float) -> np.ndarray:
    """exponential low-pass opening from f0 to f1 over the clip"""
    n = len(a)
    out = np.zeros_like(a)
    blocks = 64
    edges = np.linspace(0, n, blocks + 1).astype(int)
    zi = [None, None]
    for i in range(blocks):
        fc = f0 * (f1 / f0) ** (i / (blocks - 1))
        sos = signal.butter(2, min(fc, SR * 0.45) / (SR / 2), btype="low", output="sos")
        for ch in range(2):
            if zi[ch] is None:
                zi[ch] = signal.sosfilt_zi(sos) * a[edges[i], ch]
            y, zi[ch] = signal.sosfilt(sos, a[edges[i]:edges[i + 1], ch], zi=zi[ch])
            out[edges[i]:edges[i + 1], ch] = y
    return out


def fx_riser(d: float) -> np.ndarray:
    return to48(G.riser(d) * 0.9)


def fx_crash(d=2.0, tau=0.7) -> np.ndarray:
    return to48(G.crash(d, tau, 1))


def fx_impact() -> np.ndarray:
    """sub drop + kick for the big downbeats"""
    k = G.kick(1.0, 0.6)
    n = int(0.9 * G.SR)
    t = np.arange(n) / G.SR
    sub = np.sin(2 * np.pi * (48 * np.exp(-t * 3.0) + 36) * t) * np.exp(-t * 3.2) * 0.9
    out = np.zeros(n)
    out[: len(k)] += k[:n] * 0.8
    out += sub
    return to48(out)


def build(total: float, sections: list[tuple[str, float, float]]) -> np.ndarray:
    """sections: [(kind, start_s, end_s)], kinds: intro | build | main | break | story | finale | tail"""
    print("  rendering the game's themes ...", flush=True)
    m_st, _ = G.build_match()
    u_st, _ = G.build_menu()
    match = stretch(m_st, 120.0 / 126.0)
    menu = stretch(u_st, 120.0 / 104.0)
    print(f"  match loop {len(match) / SR:.2f} s, menu loop {len(menu) / SR:.2f} s (16 bars = 32 s each)")
    n_total = int(total * SR) + SR * 4
    out = np.zeros((n_total, 2), np.float32)

    def put(a, t0, gain=1.0):
        s = int(round(t0 * SR))
        e = min(n_total, s + len(a))
        if e > s:
            out[s:e] += a[: e - s] * gain

    for kind, t0, t1 in sections:
        nb = max(1, int(round((t1 - t0) / BAR)))
        if kind == "intro":
            seg = lowpass_sweep(bars(match, 0, nb), 250.0, 14000.0)
            seg *= np.linspace(0.55, 1.0, len(seg), dtype=np.float32)[:, None]
            put(seg, t0)
            put(fx_riser(t1 - t0), t0, 0.55)
        elif kind == "build":
            parts = [bars(match, 4 + (i % 4), 1) for i in range(nb)]
            put(xfade_join(parts), t0)
        elif kind == "main":
            order = [12, 13, 14, 15]
            parts = [bars(match, order[i % 4], 1) for i in range(nb)]
            put(xfade_join(parts), t0)
        elif kind == "break":
            parts = [bars(match, 8 + (i % 4), 1) for i in range(nb)]
            put(xfade_join(parts), t0)
        elif kind == "story":
            parts = [bars(menu, i % 16, 1) for i in range(nb)]
            put(xfade_join(parts), t0, 0.95)
        elif kind == "finale":
            order = [12, 13, 14, 15, 8, 9, 10, 11, 12, 13, 14, 15]
            parts = [bars(match, order[i % len(order)], 1) for i in range(nb)]
            put(xfade_join(parts), t0)
        elif kind == "tail":
            seg = bars(match, 12, 1)
            seg = seg * np.linspace(1.0, 0.0, len(seg), dtype=np.float32)[:, None] ** 1.5
            put(seg, t0, 0.9)
        # transitions: a riser into every section start (except the first), crash + impact on it
        if kind != "intro":
            if t0 >= BAR:
                put(fx_riser(min(2.0, t0)), t0 - 2.0, 0.6)
            put(fx_crash(), t0, 0.55)
            put(fx_impact(), t0, 0.7)
    # the very first big downbeat after the intro is placed by the caller via sections ("build" starts at the logo hit)
    peak = np.abs(out).max()
    if peak > 0.95:
        out *= 0.95 / peak
    return out[: int(total * SR)]


def default_sections(total: float):
    """bar-aligned sections; the edit's story section lives between 84 s and 148 s"""
    T = float(np.ceil(total / BAR) * BAR)
    return [("intro", 0.0, 6.0), ("build", 6.0, 16.0), ("main", 16.0, 64.0), ("break", 64.0, 84.0),
            ("story", 84.0, 148.0), ("finale", 148.0, T - 6.0), ("tail", T - 6.0, T)]


def sections_from_edit(lang: str):
    """bar-aligned sections that follow the edit of the given language (chapter boundaries from promo/timeline.py)"""
    import os
    os.environ["PROMO_LANG"] = lang
    sys.path.insert(0, str(ROOT / "promo"))
    import timeline as TL
    start = TL.make_schedule(lang)
    sec = TL.make_sections(start, lang)
    r2 = lambda x: float(round(x / BAR) * BAR)
    total = float(np.ceil((sec["outro"][1] + 0.4) / BAR) * BAR)
    play = r2(sec["play"][0])
    gag = r2(sec["gag"][0])
    cele = r2(sec["celebrate"][0] + 0.3)
    modes_end = r2(sec["modes"][1])
    story_end = r2(sec["series"][0])
    return total, [("intro", 0.0, 6.0), ("build", 6.0, play), ("main", play, gag), ("break", gag, cele), ("main", cele, modes_end),
                   ("story", modes_end, story_end), ("finale", story_end, total - 6.0), ("tail", total - 6.0, total)]


if __name__ == "__main__":
    total = 190.0
    lang = "zh"
    if "--lang" in sys.argv:
        lang = sys.argv[sys.argv.index("--lang") + 1]
    if "--total" in sys.argv:
        total = float(sys.argv[sys.argv.index("--total") + 1])
        secs = default_sections(total)
    else:
        total, secs = sections_from_edit(lang)
    print("sections:", [(k, a, b) for k, a, b in secs])
    wav = build(total, secs)
    out = ROOT / "promo_work" / f"music_{lang}.wav"
    sf.write(out, wav, SR, subtype="FLOAT")
    print(f"wrote {out}  {len(wav) / SR:.1f} s  peak {np.abs(wav).max():.2f}  rms {np.sqrt((wav ** 2).mean()):.3f}")

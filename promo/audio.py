"""Audio side of the promo: decode helpers, a bus mixer with narration ducking, and the final loudness pass.

  mix = Mixer(total_seconds)
  mix.add("vo", vo_array, start=9.1)                 # buses: vo, music, game (clip audio), sfx
  mix.add("sfx", sfx_array, start=5.9, gain_db=-6)
  wav = mix.render(duck_db={"music": -9, "game": -7, "sfx": -3})
"""
from __future__ import annotations

import subprocess
from pathlib import Path

import numpy as np
import soundfile as sf

SR = 48000
ROOT = Path(__file__).resolve().parents[1]


def load(path: str | Path, start: float = 0.0, dur: float | None = None) -> np.ndarray:
    """decode any audio / video file to float32 stereo (n, 2) at 48 kHz"""
    cmd = ["ffmpeg", "-v", "error", "-ss", f"{start:.4f}"]
    if dur is not None:
        cmd += ["-t", f"{dur:.4f}"]
    cmd += ["-i", str(path), "-vn", "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"]
    raw = subprocess.run(cmd, capture_output=True).stdout
    a = np.frombuffer(raw, np.float32).reshape(-1, 2).copy()
    return a


def db(x: float) -> float:
    return 10 ** (x / 20.0)


def fade(a: np.ndarray, fi: float = 0.0, fo: float = 0.0) -> np.ndarray:
    a = a.copy()
    n = len(a)
    ni, no = int(fi * SR), int(fo * SR)
    if ni > 0:
        a[:ni] *= np.linspace(0, 1, min(ni, n))[:, None] ** 1.5
    if no > 0:
        a[-no:] *= np.linspace(1, 0, min(no, n))[:, None] ** 1.5
    return a


def envelope(a: np.ndarray, win: float = 0.05) -> np.ndarray:
    m = np.abs(a).max(axis=1)
    k = max(1, int(win * SR))
    c = np.cumsum(np.insert(m, 0, 0.0))
    # moving average of |x|
    e = (c[k:] - c[:-k]) / k
    e = np.concatenate([np.full(k // 2, e[0] if len(e) else 0.0), e, np.full(len(m) - len(e) - k // 2, e[-1] if len(e) else 0.0)])
    return e[: len(m)]


def smooth_gate(env: np.ndarray, thr: float, attack: float = 0.05, release: float = 0.45) -> np.ndarray:
    """0..1 'narration active' signal with fast attack and slow release (for ducking)"""
    on = (env > thr).astype(np.float32)
    out = np.zeros_like(on)
    ka = 1.0 - np.exp(-1.0 / (attack * SR))
    kr = 1.0 - np.exp(-1.0 / (release * SR))
    # block-wise one-pole to keep it fast in numpy: process in 480-sample hops
    hop = 480
    g = 0.0
    for i in range(0, len(on), hop):
        target = float(on[i:i + hop].max())
        k = ka if target > g else kr
        k_h = 1 - (1 - k) ** hop
        g = g + (target - g) * k_h
        out[i:i + hop] = g
    return out


class Mixer:
    def __init__(self, total: float):
        self.n = int(total * SR) + SR
        self.buses = {k: np.zeros((self.n, 2), np.float32) for k in ("vo", "music", "game", "sfx")}

    def add(self, bus: str, a: np.ndarray, start: float, gain_db: float = 0.0, fi: float = 0.0, fo: float = 0.0) -> None:
        if a.ndim == 1:
            a = np.stack([a, a], axis=1)
        a = fade(a, fi, fo) * db(gain_db)
        s = int(round(start * SR))
        if s < 0:
            a = a[-s:]
            s = 0
        e = min(self.n, s + len(a))
        if e <= s:
            return
        self.buses[bus][s:e] += a[: e - s]

    def render(self, duck_db: dict | None = None, vo_thr: float = 0.012, master_db: float = 0.0, ceiling_db: float = -1.0) -> np.ndarray:
        duck_db = duck_db or {"music": -9.0, "game": -8.0, "sfx": -3.0}
        gate = smooth_gate(envelope(self.buses["vo"]), vo_thr)
        out = self.buses["vo"].copy()
        for bus, depth in duck_db.items():
            g = 1.0 - gate * (1.0 - db(depth))
            out += self.buses[bus] * g[:, None]
        for bus in self.buses:
            if bus not in duck_db and bus != "vo":
                out += self.buses[bus]
        out *= db(master_db)
        # soft limiter
        ceil = db(ceiling_db)
        peak = np.abs(out).max()
        if peak > ceil:
            knee = 0.8 * ceil
            x = np.abs(out)
            over = x > knee
            y = np.sign(out) * np.where(over, knee + (ceil - knee) * np.tanh((x - knee) / (ceil - knee)), x)
            out = y.astype(np.float32)
        return out

    @staticmethod
    def write(path: str | Path, a: np.ndarray) -> None:
        sf.write(str(path), a, SR, subtype="PCM_24")

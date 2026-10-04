#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Synthesises ALL audio assets of the go-sports volleyball game (no external samples).

    python tools/gen_audio.py            # everything
    python tools/gen_audio.py sfx        # only sound effects
    python tools/gen_audio.py music      # only music (needs ffmpeg with libvorbis)

Output
    assets/audio/sfx/*.wav     16-bit mono 44.1 kHz, peak ~ -3 dBFS (crowd_loop: -12 dBFS)
    assets/audio/music/*.ogg   libvorbis q4 stereo 44.1 kHz (temporary wavs live in the system temp dir)
    assets/audio/README.md     inventory (durations, BPM, bars, loop lengths)

Needs numpy + scipy.  Deterministic: every asset seeds its own RNG from its name.
"""
import os
import sys
import wave
import shutil
import zlib
import tempfile
import subprocess
from functools import lru_cache

import numpy as np
from scipy import signal
from scipy.ndimage import maximum_filter1d, uniform_filter1d

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
AUDIO_DIR = os.path.join(ROOT, 'assets', 'audio')
SFX_DIR = os.path.join(AUDIO_DIR, 'sfx')
MUS_DIR = os.path.join(AUDIO_DIR, 'music')

rng = np.random.default_rng(0)


def seed(name):
    global rng
    rng = np.random.default_rng(zlib.crc32(name.encode('ascii')))


# ----------------------------------------------------------------------------------------
# basic helpers
# ----------------------------------------------------------------------------------------
def N(d):
    return int(round(d * SR))


def tn(n):
    return np.arange(n) / SR


def mtof(m):
    return 440.0 * 2.0 ** ((np.asarray(m, dtype=float) - 69.0) / 12.0)


_NOTE = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def nm(name):
    """'C#5' -> midi number"""
    v = _NOTE[name[0]]
    i = 1
    if name[i] in '#b':
        v += 1 if name[i] == '#' else -1
        i += 1
    return 12 * (int(name[i:]) + 1) + v


def peak(x):
    return float(np.max(np.abs(x))) if len(x) else 0.0


def nrm(x, p=1.0):
    m = peak(x)
    return x * (p / m) if m > 1e-12 else x


def fit(x, n):
    if len(x) >= n:
        return x[:n].copy()
    return np.concatenate([x, np.zeros(n - len(x))])


def noise(n):
    return rng.standard_normal(n)


def smooth_rand(n, rate_hz):
    """slow random curve in [-1, 1] (linear interpolation between random points)"""
    k = int(n / SR * rate_hz) + 3
    pts = rng.uniform(-1, 1, k)
    return np.interp(np.arange(n) / SR * rate_hz, np.arange(k), pts)


def layer(d, parts):
    """parts = [(signal, start_seconds, gain)] -> mono array of exactly d seconds"""
    out = np.zeros(N(d))
    for sig, t0, g in parts:
        s = N(t0)
        if s >= len(out):
            continue
        e = min(len(out), s + len(sig))
        out[s:e] += g * sig[:e - s]
    return out


# ----------------------------------------------------------------------------------------
# filters
# ----------------------------------------------------------------------------------------
def bq(kind, f, q=0.7071):
    """RBJ biquad as one SOS row"""
    f = float(min(max(f, 15.0), SR * 0.47))
    w0 = 2 * np.pi * f / SR
    c = np.cos(w0)
    al = np.sin(w0) / (2 * q)
    if kind == 'lp':
        b = np.array([(1 - c) / 2, 1 - c, (1 - c) / 2])
    elif kind == 'hp':
        b = np.array([(1 + c) / 2, -(1 + c), (1 + c) / 2])
    elif kind == 'bp':
        b = np.array([al, 0.0, -al])
    else:
        raise ValueError(kind)
    a = np.array([1 + al, -2 * c, 1 - al])
    return np.concatenate([b / a[0], [1.0], a[1:] / a[0]])[None, :]


def lp(x, f, q=0.7071, n=1):
    return signal.sosfilt(np.vstack([bq('lp', f, q)] * n), x, axis=-1)


def hp(x, f, q=0.7071, n=1):
    return signal.sosfilt(np.vstack([bq('hp', f, q)] * n), x, axis=-1)


def bp(x, f, q=1.0):
    return signal.sosfilt(bq('bp', f, q), x, axis=-1)


def band(x, lo, hi, n=1):
    return lp(hp(x, lo, n=n), hi, n=n)


def sweep(x, fcs, kind='lp', q=0.7071, block=128):
    """time varying biquad. fcs: array (Hz per sample) or tuple (f0, f1) exponential sweep"""
    n = len(x)
    if isinstance(fcs, tuple):
        fcs = fcs[0] * (fcs[1] / fcs[0]) ** (np.arange(n) / max(1, n - 1))
    out = np.empty(n)
    zi = np.zeros((1, 2))
    for s in range(0, n, block):
        e = min(n, s + block)
        f = fcs[min(n - 1, s + block // 2)]
        out[s:e], zi = signal.sosfilt(bq(kind, f, q), x[s:e], zi=zi)
    return out


def circ_filter(x, sos):
    """steady-state (periodic) response of an IIR filter -> loop safe"""
    n = x.shape[-1]
    f = np.fft.rfftfreq(n)
    _, h = signal.sosfreqz(sos, worN=2 * np.pi * f)
    return np.fft.irfft(np.fft.rfft(x, axis=-1) * h, n, axis=-1)


# ----------------------------------------------------------------------------------------
# envelopes / oscillators
# ----------------------------------------------------------------------------------------
def env_exp(n, tau, atk=0.0005):
    t = tn(n)
    e = np.exp(-t / tau)
    if atk > 0:
        e = e * np.minimum(1.0, t / atk)
    return e


def gate_env(n, dg, atk=0.005, rel=0.05):
    t = tn(n)
    e = np.minimum(1.0, t / max(atk, 1e-4))
    return np.where(t < dg, e, e * np.exp(-(t - dg) / rel))


def phase_of(f):
    return 2 * np.pi * np.cumsum(f) / SR


def sin_sweep(f0, f1, ts, n):
    t = tn(n)
    return np.sin(phase_of(f1 + (f0 - f1) * np.exp(-t / ts)))


def thump(f0, f1, ts, tau, d, atk=0.001, sat=0.0):
    """pitch-swept sine thump (f0 -> f1 with time constant ts, amplitude decay tau)"""
    n = N(d)
    y = sin_sweep(f0, f1, ts, n) * env_exp(n, tau, atk)
    if sat > 0:
        y = np.tanh(sat * y) / np.tanh(sat)
    return y


def nburst(d, tau, lo=None, hi=None, atk=0.0004, q=0.7071):
    n = N(d)
    x = noise(n)
    if lo:
        x = hp(x, lo, q)
    if hi:
        x = lp(x, hi, q)
    return nrm(x * env_exp(n, tau, atk))


def softclip(x, k=1.0):
    return np.tanh(k * x)


# ----------------------------------------------------------------------------------------
# reverb / echo / stereo mixing
# ----------------------------------------------------------------------------------------
def make_ir(rt60, pre=0.012, damp=3500.0, sid=1):
    r = np.random.default_rng(4000 + sid)
    n = N(rt60 * 1.15)
    t = tn(n)
    x = r.standard_normal(n)
    lo = lp(x, damp) * np.exp(-6.9 * t / rt60)
    hi = band(r.standard_normal(n), damp, 9000) * np.exp(-6.9 * t / (rt60 * 0.5)) * 0.5
    ir = lp(lo + hi, 9000) * np.minimum(1.0, t / 0.005)
    ir = np.concatenate([np.zeros(N(pre)), ir])
    return ir / np.sqrt(np.sum(ir ** 2))


def conv_wet(x, ir, circular):
    full = signal.fftconvolve(x, ir)
    if not circular:
        return full
    n = len(x)
    out = full[:n].copy()
    rest = full[n:]
    while len(rest):
        m = min(len(rest), n)
        out[:m] += rest[:m]
        rest = rest[m:]
    return out


def reverb(st, rt60=1.2, mix=0.2, circular=True, pre=0.012, damp=3500.0):
    """stereo in -> stereo out (dry + decorrelated wet). circular=True wraps the tail around (loops)."""
    mono = st.mean(axis=0)
    wl = conv_wet(mono, make_ir(rt60, pre, damp, 1), circular)
    wr = conv_wet(mono, make_ir(rt60, pre, damp, 2), circular)
    if circular:
        return st + mix * np.vstack([wl, wr])
    n = max(len(wl), st.shape[1])
    out = np.zeros((2, n))
    out[:, :st.shape[1]] = st
    out[0, :len(wl)] += mix * wl
    out[1, :len(wr)] += mix * wr
    return out


def mono_reverb(x, rt60=0.5, mix=0.2, pre=0.008, damp=4000.0):
    """mono SFX reverb; output is the same length as the input"""
    w = signal.fftconvolve(x, make_ir(rt60, pre, damp, 3))[:len(x)]
    return x + mix * w


def pingpong(st, delay_s, fb=0.42, taps=5, mix=0.3, damp=3500.0, circular=True):
    ds = N(delay_s)
    src = lp(st.mean(axis=0), damp)
    out = np.zeros_like(st)
    for k in range(1, taps + 1):
        if circular:
            sh = np.roll(src, k * ds)
        else:
            sh = np.zeros_like(src)
            if k * ds < len(src):
                sh[k * ds:] = src[:len(src) - k * ds]
        g = mix * fb ** (k - 1)
        ch = k % 2
        out[ch] += g * sh
        out[1 - ch] += 0.3 * g * sh
    return st + out


class Mix:
    """stereo accumulation buffer. wrap=True: anything running past the end is mixed back onto the start."""

    def __init__(self, n, wrap=True):
        self.n = n
        self.wrap = wrap
        self.buf = np.zeros((2, n))

    def _put(self, ch, sig, s):
        n = self.n
        if self.wrap:
            s %= n
        elif s < 0 or s >= n:
            return
        pos, L = 0, len(sig)
        while pos < L:
            m = min(L - pos, n - s)
            self.buf[ch, s:s + m] += sig[pos:pos + m]
            pos += m
            s = 0
            if not self.wrap:
                break

    def add(self, sig, t, gain=1.0, pan=0.0, haas=0.0):
        ang = (pan + 1.0) * np.pi / 4
        gl = np.sqrt(2) * np.cos(ang)
        gr = np.sqrt(2) * np.sin(ang)
        s = int(round(t * SR))
        h = int(round(haas * SR / 1000.0))
        dl, dr = (0, h) if pan <= 0 else (h, 0)
        self._put(0, sig * (gain * gl), s + dl)
        self._put(1, sig * (gain * gr), s + dr)


# ----------------------------------------------------------------------------------------
# loudness / mastering
# ----------------------------------------------------------------------------------------
def k_weight(x):
    G, Q, fc = 3.99984385397, 0.7071752369554193, 1681.9744509555319
    K = np.tan(np.pi * fc / SR)
    Vh = 10 ** (G / 20)
    Vb = Vh ** 0.4845
    a0 = 1 + K / Q + K * K
    b = np.array([(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0])
    a = np.array([1.0, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0])
    y = signal.lfilter(b, a, x, axis=-1)
    fc2, Q2 = 38.13547087613982, 0.5003270373253953
    K = np.tan(np.pi * fc2 / SR)
    a0 = 1 + K / Q2 + K * K
    b2 = np.array([1.0, -2.0, 1.0])
    a2 = np.array([1.0, 2 * (K * K - 1) / a0, (1 - K / Q2 + K * K) / a0])
    return signal.lfilter(b2, a2, y, axis=-1)


def lufs(x):
    """approximate BS.1770 integrated loudness of a (ch, n) array"""
    y = k_weight(x)
    n = y.shape[1]
    blk, hop = int(0.4 * SR), int(0.1 * SR)
    if n < blk:
        return -0.691 + 10 * np.log10(np.mean(np.sum(y ** 2, axis=0)) + 1e-12)
    cs = np.concatenate([np.zeros((y.shape[0], 1)), np.cumsum(y ** 2, axis=1)], axis=1)
    st = np.arange(0, n - blk + 1, hop)
    z = np.sum((cs[:, st + blk] - cs[:, st]) / blk, axis=0)
    l = -0.691 + 10 * np.log10(z + 1e-12)
    g1 = z[l > -70]
    if len(g1) == 0:
        return -70.0
    rel = -0.691 + 10 * np.log10(np.mean(g1)) - 10
    g2 = z[l > rel]
    return -0.691 + 10 * np.log10(np.mean(g2))


def softknee(x, th=0.6):
    a = np.abs(x)
    return np.where(a < th, x, np.sign(x) * (th + (1 - th) * np.tanh((a - th) / (1 - th))))


def limiter(x, ceil, look_ms=4.0, circular=True):
    mode = 'wrap' if circular else 'nearest'
    w = int(look_ms * SR / 1000) * 2 + 1
    pk = np.max(np.abs(x), axis=0)
    m = maximum_filter1d(pk, size=w, mode=mode)
    g = np.minimum(1.0, ceil / np.maximum(m, 1e-9))
    g = uniform_filter1d(g, size=w, mode=mode)
    return x * g


def shelf_hi(f, gain_db, S=1.0):
    """RBJ high shelf as one SOS row"""
    A = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f / SR
    c, sn = np.cos(w0), np.sin(w0)
    al = sn / 2 * np.sqrt((A + 1 / A) * (1 / S - 1) + 2)
    sq = 2 * np.sqrt(A) * al
    b = np.array([A * ((A + 1) + (A - 1) * c + sq), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - sq)])
    a = np.array([(A + 1) - (A - 1) * c + sq, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - sq])
    return np.concatenate([b / a[0], [1.0], a[1:] / a[0]])[None, :]


def master(st, circular, target=-16.0, ceil_db=-1.0, label=''):
    """band-limit, normalise to ~target LUFS, soft clip, look-ahead limit to ceiling"""
    ceil = 10 ** (ceil_db / 20)
    sos = np.vstack([signal.butter(2, 28, 'highpass', fs=SR, output='sos'),
                     shelf_hi(3500.0, 2.5),
                     signal.butter(2, 16000, 'lowpass', fs=SR, output='sos')])
    if circular:
        x = circ_filter(st, sos)
    else:
        x = signal.sosfilt(sos, st, axis=-1)
    pre0 = 10 ** ((target - lufs(x)) / 20)
    pre = pre0
    y = x
    for _ in range(8):
        y = limiter(softknee(x * pre), ceil, circular=circular)
        l = lufs(y)
        if abs(l - target) < 0.35 or pre > pre0 * 4.0:
            break
        pre *= 10 ** ((target - l) / 20)
    y = np.clip(y, -ceil, ceil)
    print('    master %-12s pre-gain %+.1f dB  -> %.1f LUFS, peak %.2f dBFS' %
          (label, 20 * np.log10(pre), lufs(y), 20 * np.log10(peak(y))))
    return y


# ----------------------------------------------------------------------------------------
# file output
# ----------------------------------------------------------------------------------------
def write_wav(path, x, ch=1, sampwidth=2):
    x = np.asarray(x, dtype=np.float64)
    data = x if ch == 1 else x.T.reshape(-1)
    if sampwidth == 2:
        pcm = np.clip(np.round(data * 32767.0), -32768, 32767).astype('<i2')
    else:
        pcm = np.clip(np.round(data * 2147483647.0), -2147483648, 2147483647).astype('<i4')
    with wave.open(path, 'wb') as w:
        w.setnchannels(ch)
        w.setsampwidth(sampwidth)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def finalize(x, d, peak_db=-3.0, fade_in=0.005, fade_out=None):
    """exact length, fade in/out (no clicks), peak normalise"""
    n = N(d)
    x = fit(x, n)
    fo = fade_out if fade_out is not None else min(0.03, 0.2 * d)
    nfi, nfo = N(fade_in), N(fo)
    if nfi:
        x[:nfi] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(nfi) / nfi)
    if nfo:
        x[-nfo:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(nfo) / nfo)
    return nrm(x, 10 ** (peak_db / 20))


# ----------------------------------------------------------------------------------------
# SOUND EFFECTS
# ----------------------------------------------------------------------------------------
def glass(f, d, vel=1.0):
    """glass / bell chime (inharmonic partials)"""
    n = N(d)
    t = tn(n)
    y = np.zeros(n)
    for r, a, k in ((1.0, 1.0, 0.5), (2.756, 0.5, 0.28), (5.404, 0.28, 0.16), (8.933, 0.12, 0.09)):
        if f * r < 14000:
            y += a * np.sin(2 * np.pi * f * r * t) * np.exp(-t / (d * k))
    return vel * y * np.minimum(1.0, t / 0.002)


@lru_cache(maxsize=None)
def marimba(m, d=1.0, vel=1.0):
    """sine + fast decaying 4x (and 10x) partial + soft mallet knock"""
    f = float(mtof(m))
    n = N(d)
    t = tn(n)
    tau = float(np.clip(0.75 * (330.0 / f) ** 0.55, 0.10, 1.1))
    y = np.sin(2 * np.pi * f * t) * np.exp(-t / tau)
    y += 0.30 * np.sin(2 * np.pi * 3.99 * f * t) * np.exp(-t / (tau * 0.16))
    if 9.9 * f < 15000:
        y += 0.07 * np.sin(2 * np.pi * 9.9 * f * t) * np.exp(-t / (tau * 0.05))
    r = np.random.default_rng(int(m) * 7 + 3)
    k = N(0.012)
    kn = lp(r.standard_normal(k), 2500) * np.exp(-np.arange(k) / SR / 0.003)
    y[:k] += 0.12 * kn
    y *= np.minimum(1.0, t / 0.0008)
    y *= np.minimum(1.0, np.maximum(0.0, (d - t) / 0.02))
    return vel * y


def impact_spike(d):
    snap = nburst(0.07, 0.011, lo=1500, hi=7500)
    body = nburst(0.14, 0.030, lo=350, hi=2600)
    th = thump(200, 62, 0.022, 0.085, d, atk=0.0008, sat=2.2)
    crack = nburst(0.01, 0.0015, lo=3000, hi=9000)
    return layer(d, [(snap, 0.003, 0.95), (body, 0.003, 0.65), (th, 0.003, 1.15), (crack, 0.003, 0.5)])


def sfx_hit_bump():
    d = 0.25
    th = thump(145, 80, 0.045, 0.075, d, atk=0.002, sat=1.6)
    th2 = thump(290, 160, 0.045, 0.03, d, atk=0.002)
    nz = nburst(0.10, 0.02, hi=650, q=0.8)
    return layer(d, [(th, 0.003, 1.0), (th2, 0.003, 0.25), (nz, 0.003, 0.55)])


def sfx_hit_set():
    d = 0.18
    tok = thump(500, 400, 0.012, 0.032, d, atk=0.0008)
    pop = thump(1000, 800, 0.010, 0.018, d, atk=0.0008)
    click = nburst(0.03, 0.005, lo=1800, hi=6000)
    air = nburst(0.05, 0.012, lo=600, hi=2500)
    return layer(d, [(tok, 0.003, 1.0), (pop, 0.003, 0.35), (click, 0.003, 0.6), (air, 0.003, 0.3)])


def sfx_hit_spike():
    return impact_spike(0.30)


def sfx_hit_serve():
    d = 0.28
    n = N(0.09)
    wh = sweep(noise(n), (500, 3500), 'bp', q=1.2) * np.linspace(0, 1, n) ** 2
    wh = nrm(wh)
    snap = nburst(0.06, 0.014, lo=900, hi=5000)
    body = nburst(0.12, 0.03, lo=300, hi=2000)
    th = thump(165, 85, 0.028, 0.075, d, atk=0.0008, sat=1.8)
    t0 = 0.09
    return layer(d, [(wh, 0.0, 0.40), (snap, t0, 0.8), (body, t0, 0.55), (th, t0, 1.0)])


def sfx_hit_perfect():
    d = 0.45
    imp = impact_spike(d)
    notes = [84, 88, 91, 96, 100]
    parts = [(imp, 0.0, 0.9)]
    for i, m in enumerate(notes):
        parts.append((glass(float(mtof(m)), 0.36, 1.0), 0.03 + 0.045 * i, 0.30 + 0.06 * i))
    return layer(d, parts)


def sfx_bounce():
    d = 0.30
    n = N(d)
    body = thump(240, 120, 0.03, 0.07, d, atk=0.0015, sat=1.3)
    imp = np.zeros(n)
    imp[:N(0.003)] = noise(N(0.003))
    ring = bp(imp, 310, 9.0) + 0.6 * bp(imp, 520, 10.0)
    ring = nrm(ring) * np.exp(-tn(n) / 0.07)
    tick = nburst(0.012, 0.003, hi=1800)
    return layer(d, [(body, 0.003, 1.0), (ring, 0.003, 0.55), (tick, 0.003, 0.3)])


def sfx_net_hit():
    d = 0.45
    n = N(d)
    t = tn(n)
    thud = thump(125, 72, 0.03, 0.05, d, atk=0.002, sat=1.4)
    imp = np.zeros(n)
    tt = 0.0
    while tt < 0.40:
        tt += rng.exponential(1.0 / np.interp(tt, [0, 0.4], [140, 35]))
        s = N(tt)
        if s < n:
            imp[s] += rng.uniform(0.3, 1.0) * rng.choice([-1, 1]) * np.exp(-tt / 0.22)
    rat = bp(imp, 3600, 5.0) + 0.7 * bp(imp, 5200, 6.0) + 0.4 * bp(imp, 2400, 4.0)
    rat = nrm(rat)
    hiss = nrm(band(noise(n), 1800, 6000) * np.exp(-t / 0.12)) * np.minimum(1.0, t / 0.004)
    return layer(d, [(thud, 0.003, 1.0), (rat, 0.014, 0.7), (hiss, 0.01, 0.25)])


def sfx_block():
    d = 0.35
    th = thump(130, 52, 0.04, 0.12, d, atk=0.001, sat=2.0)
    wood = thump(310, 210, 0.02, 0.05, d, atk=0.001)
    slap = nburst(0.07, 0.014, lo=1000, hi=5000)
    low = nburst(0.12, 0.03, lo=150, hi=900)
    return layer(d, [(th, 0.003, 1.2), (wood, 0.003, 0.5), (slap, 0.003, 0.8), (low, 0.003, 0.6)])


def sfx_jump():
    d = 0.20
    n = N(d)
    t = tn(n)
    f = 240 * (580 / 240) ** np.minimum(1, t / 0.14)
    ph = phase_of(f)
    boing = (np.sin(ph) + 0.3 * np.sin(2 * ph)) * (1 + 0.18 * np.sin(2 * np.pi * 34 * t)) * env_exp(n, 0.085, 0.004)
    m = N(0.06)
    ts = tn(m)
    sq = np.sin(phase_of(2300 + 700 * (ts / 0.06))) * np.exp(-ts / 0.02) * (1 + 0.5 * np.sin(2 * np.pi * 55 * ts))
    return layer(d, [(boing, 0.0, 0.9), (sq, 0.0, 0.15)])


def sfx_body_bump():
    """two bodies brushing / bumping: soft cloth + muffled thud"""
    d = 0.22
    th = thump(125, 62, 0.03, 0.06, d, atk=0.002, sat=1.1)
    cl = nburst(0.09, 0.025, lo=300, hi=2200)
    return layer(d, [(th, 0.002, 1.0), (cl, 0.0, 0.5)])


def sfx_crash():
    """hard collision: heavy thump + wide noise slam + cartoon 'bonk'"""
    d = 0.55
    n = N(d)
    t = tn(n)
    th = thump(100, 42, 0.05, 0.14, d, atk=0.002, sat=1.7)
    nz = nburst(0.22, 0.07, lo=200, hi=3500)
    bonk = np.sin(phase_of(540 - 320 * np.clip(t / 0.12, 0, 1))) * np.exp(-t / 0.09)
    tap = nburst(0.03, 0.006, lo=1500, hi=5000)
    return layer(d, [(th, 0.002, 1.0), (nz, 0.002, 0.7), (bonk, 0.01, 0.35), (tap, 0.002, 0.4)])


def sfx_dizzy():
    """cartoon dizziness: wobbling descending whistle + a few little bell pings"""
    d = 1.1
    n = N(d)
    t = tn(n)
    f = 880 - 320 * t / d + 70 * np.sin(2 * np.pi * 6.5 * t)
    wob = np.sin(phase_of(f)) * (0.55 + 0.45 * np.sin(2 * np.pi * 4.0 * t)) * np.exp(-t / 0.8) * np.minimum(1.0, t / 0.03)
    parts = [(wob, 0.0, 0.45)]
    for i, (fq, t0) in enumerate(((1568, 0.05), (1318, 0.22), (1760, 0.4), (1175, 0.58))):
        parts.append((glass(fq, 0.45, 0.5), t0, 0.35))
    return layer(d, parts)


def sfx_land():
    d = 0.15
    th = thump(130, 70, 0.02, 0.04, d, atk=0.0015, sat=1.3)
    nz = nburst(0.05, 0.012, hi=900)
    tap = nburst(0.02, 0.004, lo=1200, hi=4000)
    return layer(d, [(th, 0.002, 1.0), (nz, 0.002, 0.6), (tap, 0.002, 0.25)])


def sfx_dive():
    d = 0.45
    n = N(d)
    t = tn(n)
    sw = sweep(noise(n), (3200, 900), 'bp', q=1.1)
    sw = nrm(sw * np.sin(np.pi * np.clip(t / 0.36, 0, 1)) ** 1.5)
    sc = lp(noise(n), 1500, n=2)
    mod = np.clip(0.55 + 0.6 * smooth_rand(n, 45), 0, None)
    sc = nrm(sc * mod * np.sin(np.pi * np.clip((t - 0.08) / 0.32, 0, 1)))
    th = thump(120, 65, 0.03, 0.07, d, sat=1.3)
    return layer(d, [(sw, 0.0, 0.7), (sc, 0.0, 0.55), (th, 0.05, 0.6)])


def _step(f, bf, squeak=False):
    d = 0.09
    tap = thump(f, f * 0.7, 0.01, 0.018, d, atk=0.0008)
    nz = nburst(0.03, 0.006, lo=bf * 0.6, hi=bf * 1.8)
    parts = [(tap, 0.002, 0.8), (nz, 0.002, 0.6)]
    if squeak:
        n = N(0.03)
        ts = tn(n)
        parts.append((np.sin(phase_of(2400 - 600 * ts / 0.03)) * np.exp(-ts / 0.01), 0.004, 0.14))
    return layer(d, parts)


def sfx_step1():
    return _step(240, 2200)


def sfx_step2():
    return _step(285, 2700)


def sfx_step3():
    return _step(205, 1900, squeak=True)


def sfx_toss():
    d = 0.30
    n = N(d)
    t = tn(n)
    env = np.sin(np.pi * np.clip(t / 0.28, 0, 1) ** 1.35) ** 1.5
    w = nrm(sweep(noise(n), (450, 2800), 'bp', q=1.4) * env)
    tone = np.sin(phase_of(300 + 500 * (t / d) ** 1.2)) * env
    flick = nburst(0.04, 0.008, lo=800, hi=4000)
    return layer(d, [(w, 0.0, 0.9), (tone, 0.0, 0.10), (flick, 0.0, 0.25)])


def sfx_swing_miss():
    d = 0.30
    n = N(d)
    t = tn(n)
    fc = np.where(t < 0.13, 600 * (3400 / 600) ** (t / 0.13), 3400 * (1300 / 3400) ** ((t - 0.13) / 0.17))
    env = np.exp(-((t - 0.13) / 0.065) ** 2)
    w = nrm(sweep(noise(n), fc, 'bp', q=1.0) * env)
    low = nrm(lp(noise(n), 700, n=2) * env)
    return layer(d, [(w, 0.0, 0.9), (low, 0.0, 0.35)])


def whistle(d, f0=2850.0, trill=26.0, bend=0.0, vib=0.0, rel=0.05):
    n = N(d)
    t = tn(n)
    fb = f0 * (1 + bend * np.exp(-t / 0.05)) * (1 + vib * np.sin(2 * np.pi * 5.5 * t) * np.minimum(1, t / 0.3))
    fm = fb * (1 + 0.010 * np.sin(2 * np.pi * trill * t))
    am = 0.62 + 0.38 * np.sin(2 * np.pi * trill * t + 0.6)
    ph = phase_of(fm)
    tone = np.sin(ph) + 0.28 * np.sin(2 * ph) + 0.10 * np.sin(3 * ph)
    tone2 = 0.55 * np.sin(phase_of(fm * 1.065))
    breath = band(noise(n), 2000, 4800) * 0.22
    sig = (tone + tone2 + breath) * am
    env = np.minimum(1, t / 0.018) * np.clip((d - t) / rel, 0, 1)
    return lp(sig, 6500) * env


def sfx_whistle_short():
    return whistle(0.35)


def sfx_whistle_long():
    return whistle(0.9, bend=0.02, vib=0.004, rel=0.08)


def sfx_cheer():
    d = 2.5
    n = N(d)
    t = tn(n)
    rise = np.clip(t / 0.55, 0, 1)
    rise = rise * rise * (3 - 2 * rise)
    fall = np.where(t > 1.35, np.exp(-(t - 1.35) / 0.55), 1.0)
    w = smooth_rand(n, 4.0)
    env = rise * fall * np.clip(1 + 0.22 * w, 0.4, None)
    roar = band(noise(n), 350, 1300) + 0.55 * band(noise(n), 1300, 3400) + 0.5 * lp(noise(n), 260)
    roar = roar / np.std(roar)
    voices = np.zeros(n)
    for _ in range(16):
        st = rng.uniform(0.0, 0.7)
        dur = rng.uniform(0.6, 1.5)
        f0 = rng.uniform(240, 520)
        m = N(dur)
        tv = tn(m)
        f = f0 * (1 + 0.35 * np.sin(np.pi * np.minimum(1, tv / dur * 0.9)))
        ph = phase_of(f)
        v = sum(np.sin(h * ph) / h for h in range(1, 9))
        v = bp(v, rng.uniform(700, 1200), 1.2) * np.sin(np.pi * np.arange(m) / m) ** 1.5
        s = N(st)
        e = min(n, s + m)
        voices[s:e] += v[:e - s]
    voices = voices / (np.std(voices) + 1e-9)
    kernels = [nburst(0.03, rng.uniform(0.004, 0.008), lo=900, hi=rng.uniform(3000, 4800)) for _ in range(6)]
    cl = np.zeros(n)
    tt = 0.30
    xs = [0.3, 0.9, 1.9, 2.5]
    while tt < 2.45:
        tt += rng.exponential(1.0 / np.interp(tt, xs, [25, 70, 70, 30]))
        s = N(tt)
        if s >= n:
            break
        k = kernels[rng.integers(len(kernels))]
        a = rng.uniform(0.25, 1.0) * np.interp(tt, xs, [0.5, 1.0, 1.0, 0.4])
        e = min(n, s + len(k))
        cl[s:e] += a * k[:e - s]
    cl = cl / (np.std(cl[N(0.9):N(1.9)]) + 1e-9)
    clap_env = np.clip(np.minimum(1, t / 0.3) * fall, 0, 1)
    return env * (0.8 * roar + 0.30 * voices * np.clip(rise * 1.2, 0, 1)) + 0.60 * cl * clap_env


def sfx_crowd_loop():
    d = 8.0
    L = N(d)
    X = N(0.8)
    n = L + X
    t = tn(n)
    c1 = 520 + 300 * smooth_rand(n, 0.5)
    c2 = 1500 + 600 * smooth_rand(n, 0.4)
    m1 = sweep(noise(n), c1, 'bp', q=0.9)
    m2 = sweep(noise(n), c2, 'bp', q=1.0) * 0.5
    rumble = lp(noise(n), 220, n=2) * 0.5
    sig = m1 / np.std(m1) + 0.5 * m2 / np.std(m2) + 0.4 * rumble / np.std(rumble)
    # babble: many overlapping syllable-modulated vowel voices (reads as a distant crowd)
    babble = np.zeros(n)
    for _ in range(26):
        f0 = rng.uniform(105, 250)
        ph = phase_of(f0 * (1 + 0.10 * smooth_rand(n, 2.0)))
        v = sum(np.sin(h * ph) / h for h in range(1, 13))
        v = bp(v, rng.uniform(350, 800), 1.6) + 0.6 * bp(v, rng.uniform(900, 2200), 1.8)
        syl = np.clip(smooth_rand(n, rng.uniform(3.0, 6.0)) + 0.25, 0, None) ** 1.5
        babble += v * syl
    babble = babble / np.std(babble)
    sig = sig * 0.5 + 1.0 * babble
    flut = (1 + 0.12 * smooth_rand(n, 5.0)) * (1 + 0.10 * smooth_rand(n, 9.0)) * (1 + 0.22 * smooth_rand(n, 0.7))
    sig = sig * flut
    for _ in range(9):
        st = rng.uniform(0, d)
        dur = rng.uniform(0.7, 1.2)
        f0 = rng.uniform(190, 270)
        m = N(dur)
        tv = tn(m)
        ph = phase_of(f0 * (1 + 0.12 * np.sin(np.pi * tv / dur)))
        v = sum(np.sin(h * ph) / h for h in range(1, 8))
        v = bp(v, rng.uniform(500, 900), 1.0) * np.sin(np.pi * np.arange(m) / m) ** 2
        s = N(st)
        e = min(n, s + m)
        sig[s:e] += 0.55 * v[:e - s] / (np.std(v) + 1e-9)
    # tame outliers, then loop crossfade (equal power) so the end flows into the start
    sig = np.tanh(sig / (2.6 * np.std(sig))) * 2.6 * np.std(sig)
    a = np.arange(X) / X
    r = sig[:L].copy()
    r[:X] = sig[:X] * np.sin(a * np.pi / 2) + sig[L:L + X] * np.cos(a * np.pi / 2)
    return r


def sfx_ui_click():
    d = 0.12
    n = N(d)
    t = tn(n)
    f = 1300 - 900 * np.exp(-t / 0.018)
    ph = phase_of(f)
    pop = (np.sin(ph) + 0.2 * np.sin(2 * ph)) * env_exp(n, 0.028, 0.001)
    click = nburst(0.01, 0.002, lo=1500, hi=6000)
    return layer(d, [(pop, 0.004, 1.0), (click, 0.004, 0.12)])


def sfx_ui_hover():
    d = 0.06
    tk = thump(2400, 2200, 0.01, 0.008, d, atk=0.0008)
    nz = nburst(0.01, 0.002, lo=3000, hi=8000)
    return layer(d, [(tk, 0.001, 0.5), (nz, 0.001, 0.2)])


def sfx_ui_confirm():
    d = 0.35
    a = marimba(84, 0.30)
    b = marimba(91, 0.28)
    g = glass(float(mtof(103)), 0.2)
    return layer(d, [(a, 0.0, 0.9), (b, 0.11, 1.0), (g, 0.11, 0.12)])


def _blip(f, d, glide=-0.04):
    n = N(d)
    t = tn(n)
    ph = phase_of(f * (1 + glide * t / d))
    return (np.sin(ph) + 0.25 * np.sin(2 * ph)) * env_exp(n, d * 0.45, 0.003)


def sfx_ui_back():
    d = 0.2
    return layer(d, [(_blip(784.0, 0.10), 0.0, 0.9), (_blip(587.0, 0.11), 0.09, 1.0)])


def sfx_ui_swoosh():
    d = 0.5
    n = N(d)
    t = tn(n)
    env = np.sin(np.pi * np.clip(t / 0.46, 0, 1) ** 1.25) ** 2
    w = nrm(sweep(noise(n), (250, 5200), 'bp', q=1.0) * env)
    low = nrm(sweep(noise(n), (150, 1200), 'lp', q=0.9) * env)
    return layer(d, [(w, 0.0, 0.85), (low, 0.0, 0.4)])


def _beep(f, d_sus, tail, bell=0.12):
    n = N(d_sus + tail)
    t = tn(n)
    y = np.sin(2 * np.pi * f * t) + 0.22 * np.sin(4 * np.pi * f * t)
    y += bell * np.sin(2 * np.pi * 2.76 * f * t) * np.exp(-t / 0.06)
    return y * gate_env(n, d_sus, atk=0.003, rel=tail / 4)


def sfx_countdown():
    return _beep(880.0, 0.14, 0.11)


def sfx_go():
    d = 0.5
    parts = []
    for i, (f, g) in enumerate(((1760.0, 1.0), (2217.5, 0.45), (2637.0, 0.30))):
        parts.append((_beep(f, 0.20 - 0.01 * i, 0.30, bell=0.15), 0.012 * i, g))
    return layer(d, parts)


def sfx_perfect():
    d = 0.5
    parts = []
    for i, m in enumerate([84, 88, 91, 96, 100]):
        parts.append((glass(float(mtof(m)), 0.4), 0.045 * i, 0.55 + 0.1 * i))
    sp = nburst(0.30, 0.07, lo=7000)
    parts.append((sp, 0.02, 0.06))
    return layer(d, parts)


def sfx_point_win():
    d = 1.4
    parts = []
    for i, m in enumerate([72, 76, 79, 84]):
        parts.append((marimba(m, 0.7), 0.15 * i, 0.9))
    parts.append((marimba(60, 0.9), 0.0, 0.5))
    t0 = 0.66
    for m, g in ((84, 0.9), (88, 0.8), (79, 0.7), (60, 0.7)):
        parts.append((marimba(m, 0.75), t0, g))
    parts.append((glass(float(mtof(96)), 0.6), t0, 0.18))
    x = layer(d, parts)
    return mono_reverb(x, 0.5, 0.2)


def _muted(m, d, slide=0.0, vib=0.0, tail=0.15, wah=(350.0, 1300.0)):
    """muted trombone-ish synth: saw -> swept resonant low-pass ('wah')"""
    f = float(mtof(m))
    n = N(d + tail)
    t = tn(n)
    ft = f * 2 ** ((slide * np.clip((t - 0.15 * d) / (0.85 * d), 0, 1)) / 12)
    ft = ft * (1 + vib * np.sin(2 * np.pi * 5.0 * t) * np.minimum(1, t / 0.25))
    ph = phase_of(ft)
    y = sum(np.sin(h * ph) / h for h in range(1, 24) if f * h < 4200)
    fcs = wah[0] + (wah[1] - wah[0]) * np.sin(np.pi * np.minimum(1, t / d))
    y = sweep(y, fcs, 'lp', q=2.0)
    return y * gate_env(n, d, atk=0.03, rel=0.08) * 0.5


def sfx_point_lose():
    d = 1.2
    parts = [(_muted(70, 0.28), 0.0, 1.0),
             (_muted(69, 0.28), 0.30, 1.0),
             (_muted(68, 0.55, slide=-1.6, vib=0.012, wah=(350.0, 1500.0)), 0.60, 1.0)]
    x = layer(d, parts)
    return mono_reverb(x, 0.35, 0.15)


def _crash(d=1.6, tau=0.5):
    n = N(d)
    t = tn(n)
    x = band(noise(n), 5000, 12500) + 0.4 * band(noise(n), 2500, 5000)
    return nrm(x * np.exp(-t / tau) * np.minimum(1, t / 0.002))


def sfx_match_point():
    d = 1.0
    n = N(d)
    parts = []
    roll_end = 0.78
    t = 0.0
    while t < roll_end:
        frac = t / roll_end
        a = 0.2 + 0.8 * frac
        h = nburst(0.06, 0.018, lo=600, hi=5000)
        tone = thump(190, 160, 0.01, 0.03, 0.06, atk=0.0008)
        parts.append((h, t, 0.8 * a))
        parts.append((tone, t, 0.45 * a))
        t += 0.075 - 0.053 * frac
    tt = tn(n)
    sw = nrm(hp(noise(n), 4500, n=2) * np.clip(tt / roll_end, 0, 1) ** 2 * np.where(tt < roll_end, 1.0, np.exp(-(tt - roll_end) / 0.12)))
    parts.append((sw, 0.0, 0.55))
    t0 = roll_end
    parts.append((glass(float(mtof(84)), 0.35), t0, 1.0))
    parts.append((glass(float(mtof(91)), 0.30), t0, 0.35))
    parts.append((marimba(60, 0.3), t0, 0.6))
    parts.append((thump(120, 55, 0.03, 0.08, 0.25, sat=1.5), t0, 0.9))
    parts.append((_crash(0.25, 0.1), t0, 0.5))
    return layer(d, parts)


# name, duration, function, finalize kwargs
def sfx_whoosh():
    """arm swing through the air (spike / serve wind-up)"""
    d = 0.28
    n = N(d)
    t = tn(n)
    fc = 500 * (3600 / 500) ** np.clip(t / 0.2, 0, 1)
    env = np.sin(np.pi * np.clip(t / 0.26, 0, 1)) ** 1.6
    w = nrm(sweep(noise(n), fc, 'bp', q=0.9) * env)
    low = nrm(lp(noise(n), 500, n=2) * env)
    return layer(d, [(w, 0.0, 0.9), (low, 0.0, 0.3)])


def sfx_crowd_oh():
    """the crowd gasping 'oooh' at a close call or a great save"""
    d = 1.0
    n = N(d)
    t = tn(n)
    env = np.sin(np.pi * np.clip(t / 0.95, 0, 1)) ** 1.2
    voices = np.zeros(n)
    for _ in range(10):
        f0 = rng.uniform(190, 330)
        f = f0 * (1 + 0.18 * np.sin(np.pi * np.clip(t / 0.9, 0, 1)))
        ph = phase_of(f)
        v = sum(np.sin(h * ph) / h ** 1.3 for h in range(1, 7))
        voices += bp(v, rng.uniform(450, 700), 1.4)
    voices = voices / (np.std(voices) + 1e-9)
    air = band(noise(n), 300, 1600)
    air = air / (np.std(air) + 1e-9)
    return env * (0.7 * voices + 0.45 * air)


def sfx_fever():
    """fever time starts: rising marimba arpeggio + shimmer sweep"""
    d = 1.1
    n = N(d)
    t = tn(n)
    parts = []
    for i, m in enumerate((72, 76, 79, 84, 88)):
        parts.append((marimba(m, 0.5, 0.9), 0.07 * i, 0.85))
    parts.append((glass(float(mtof(108)), 0.7, 0.5), 0.3, 0.3))
    sw = nrm(sweep(noise(n), 400 * (6000 / 400) ** np.clip(t / 0.5, 0, 1), 'bp', q=1.5) * np.sin(np.pi * np.clip(t / 0.6, 0, 1)) ** 2)
    parts.append((sw, 0.0, 0.35))
    return layer(d, parts)


def sfx_levelup():
    """level up fanfare"""
    d = 1.3
    parts = [(marimba(m, 0.6, 1.0), t0, 0.9) for m, t0 in ((72, 0.0), (76, 0.12), (79, 0.24), (84, 0.40))]
    parts.append((glass(float(mtof(96)), 0.9, 0.6), 0.4, 0.4))
    parts.append((marimba(91, 0.8, 1.0), 0.40, 0.8))
    return layer(d, parts)


def sfx_xp_tick():
    """tiny blip while the XP bar fills"""
    d = 0.06
    return layer(d, [(_blip(1500, 0.05), 0.0, 0.9)])


SFX_SPEC = [
    ('hit_bump', 0.25, sfx_hit_bump, {}),
    ('hit_set', 0.18, sfx_hit_set, {}),
    ('hit_spike', 0.30, sfx_hit_spike, {}),
    ('hit_serve', 0.28, sfx_hit_serve, {}),
    ('hit_perfect', 0.45, sfx_hit_perfect, {}),
    ('bounce', 0.30, sfx_bounce, {}),
    ('net_hit', 0.45, sfx_net_hit, {}),
    ('block', 0.35, sfx_block, {}),
    ('jump', 0.20, sfx_jump, {}),
    ('land', 0.15, sfx_land, {}),
    ('body_bump', 0.22, sfx_body_bump, {}),
    ('crash', 0.55, sfx_crash, {}),
    ('dizzy', 1.1, sfx_dizzy, {'fade_out': 0.15}),
    ('whoosh', 0.28, sfx_whoosh, {}),
    ('crowd_oh', 1.0, sfx_crowd_oh, {'fade_out': 0.12}),
    ('fever', 1.1, sfx_fever, {}),
    ('levelup', 1.3, sfx_levelup, {}),
    ('xp_tick', 0.06, sfx_xp_tick, {}),
    ('dive', 0.45, sfx_dive, {}),
    ('step1', 0.09, sfx_step1, {}),
    ('step2', 0.09, sfx_step2, {}),
    ('step3', 0.09, sfx_step3, {}),
    ('toss', 0.30, sfx_toss, {}),
    ('swing_miss', 0.30, sfx_swing_miss, {}),
    ('whistle_short', 0.35, sfx_whistle_short, {}),
    ('whistle_long', 0.9, sfx_whistle_long, {}),
    ('cheer', 2.5, sfx_cheer, {'fade_out': 0.25}),
    ('crowd_loop', 8.0, sfx_crowd_loop, {'peak_db': -12.0, 'fade_in': 0.0, 'fade_out': 0.0}),
    ('ui_click', 0.12, sfx_ui_click, {}),
    ('ui_hover', 0.06, sfx_ui_hover, {}),
    ('ui_confirm', 0.35, sfx_ui_confirm, {}),
    ('ui_back', 0.2, sfx_ui_back, {}),
    ('ui_swoosh', 0.5, sfx_ui_swoosh, {}),
    ('countdown', 0.25, sfx_countdown, {}),
    ('go', 0.5, sfx_go, {}),
    ('perfect', 0.5, sfx_perfect, {}),
    ('point_win', 1.4, sfx_point_win, {'fade_out': 0.12}),
    ('point_lose', 1.2, sfx_point_lose, {'fade_out': 0.12}),
    ('match_point', 1.0, sfx_match_point, {'fade_out': 0.04}),
]


def gen_sfx(only=None):
    os.makedirs(SFX_DIR, exist_ok=True)
    for name, d, fn, kw in SFX_SPEC:
        if only and name not in only:
            continue
        seed(name)
        x = finalize(fn(), d, **kw)
        assert np.all(np.isfinite(x)), name
        write_wav(os.path.join(SFX_DIR, name + '.wav'), x, 1, 2)
        print('  sfx %-14s %6d samples  %.3f s' % (name, len(x), len(x) / SR))


# ----------------------------------------------------------------------------------------
# MUSIC instruments
# ----------------------------------------------------------------------------------------
@lru_cache(maxsize=None)
def pluck(m, d=0.9, tau0=0.45, pos=0.16):
    """ukulele-ish pluck: additive harmonics, higher partials die faster, pick-position comb, pick noise"""
    f = float(mtof(m))
    n = N(d)
    t = tn(n)
    y = np.zeros(n)
    H = int(min(16, (SR * 0.42) / f))
    for h in range(1, H + 1):
        a = (0.35 + abs(np.sin(np.pi * h * pos))) / h ** 1.1
        tau = tau0 / (1 + 0.55 * (h - 1))
        y += a * np.sin(2 * np.pi * f * h * t) * np.exp(-t / tau)
    y *= np.minimum(1.0, t / 0.0015)
    r = np.random.default_rng(int(m) * 11 + 5)
    k = N(0.02)
    y[:k] += 0.10 * band(r.standard_normal(k), 1500, 5000) * np.exp(-np.arange(k) / SR / 0.003)
    y *= np.minimum(1.0, np.maximum(0.0, (d - t) / 0.03))
    return y * 0.45


@lru_cache(maxsize=None)
def bass_soft(m, d, tail=0.12):
    f = float(mtof(m))
    n = N(d + tail)
    t = tn(n)
    y = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(4 * np.pi * f * t) * np.exp(-t / 0.25) \
        + 0.12 * np.sin(6 * np.pi * f * t) * np.exp(-t / 0.12)
    env = gate_env(n, d, atk=0.006, rel=0.06) * (0.65 + 0.35 * np.exp(-t / 0.3))
    return np.tanh(1.3 * y * env) * 0.8


@lru_cache(maxsize=None)
def bass_pluck(m, d, tail=0.06):
    """plucky saw/square-ish bass: harmonics fall away quickly (filter envelope) + sub sine"""
    f = float(mtof(m))
    n = N(d + tail)
    t = tn(n)
    y = 0.7 * np.sin(2 * np.pi * f * t)
    for h in range(1, 14):
        if f * h > 4000:
            break
        a = (1.0 / h) * (1.0 if h % 2 else 0.5)
        tau = 0.30 / (1 + 0.7 * (h - 1)) + 0.02
        y += 0.6 * a * np.sin(2 * np.pi * f * h * t) * np.exp(-t / tau)
    env = gate_env(n, d, atk=0.003, rel=0.03)
    return np.tanh(1.2 * y) * env * 0.8


@lru_cache(maxsize=None)
def lead_soft(m, d, tail=0.12):
    """soft square lead with delayed vibrato, low-passed (no harsh highs)"""
    f = float(mtof(m))
    n = N(d + tail)
    t = tn(n)
    ft = f * (1 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.12) / 0.2, 0, 1))
    ph = phase_of(ft)
    y = sum(np.sin(h * ph) / h for h in range(1, 14, 2) if f * h < 5000)
    y = lp(y, 3200)
    return y * gate_env(n, d, atk=0.01, rel=0.07) * 0.5


@lru_cache(maxsize=None)
def stab(notes, d=0.2):
    """bright, short chord stab: detuned saw stack with fast decaying upper partials"""
    n = N(d + 0.25)
    t = tn(n)
    y = np.zeros(n)
    for m in notes:
        f = float(mtof(m))
        for det in (-0.0035, 0.0035):
            for h in range(1, 11):
                if f * h > 6000:
                    break
                tau = 0.17 / (1 + 0.35 * (h - 1))
                y += (1.0 / h) * np.sin(2 * np.pi * f * (1 + det) * h * t) * np.exp(-t / tau)
    y = lp(y * gate_env(n, d, atk=0.002, rel=0.05), 5500)
    return y / (len(notes) * 2) * 1.2


@lru_cache(maxsize=None)
def pad(m, d):
    f = float(mtof(m))
    n = N(d)
    t = tn(n)
    r = np.random.default_rng(int(m) * 3)
    y = np.zeros(n)
    for det, a in ((0.997, 1.0), (1.0, 1.0), (1.003, 1.0)):
        y += a * np.sin(2 * np.pi * f * det * t + r.uniform(0, 6.28))
    y += 0.3 * np.sin(4 * np.pi * f * t + r.uniform(0, 6.28))
    env = np.minimum(1.0, t / 0.35) * np.minimum(1.0, np.maximum(0.0, (d - t) / 0.5))
    return y * env / 3.3


@lru_cache(maxsize=None)
def kick(vel=1.0, d=0.38, soft=False):
    n = N(d)
    t = tn(n)
    f = 44 + 86 * np.exp(-t / 0.030)
    y = np.sin(phase_of(f)) * np.exp(-t / 0.13)
    r = np.random.default_rng(99)
    click = lp(r.standard_normal(n), 3000) * np.exp(-t / 0.003) * (0.05 if soft else 0.12)
    y = (np.tanh(1.6 * (y + click)) / np.tanh(1.6)) * np.minimum(1.0, t / 0.0008)
    y *= np.minimum(1.0, np.maximum(0.0, (d - t) / 0.03))
    return vel * y


@lru_cache(maxsize=None)
def clap(variant=0, d=0.28):
    r = np.random.default_rng(300 + variant)
    n = N(d)
    t = tn(n)
    y = np.zeros(n)
    for off, a in ((0, 1.0), (0.009, 0.85), (0.019, 0.7)):
        s = N(off)
        y[s:] += band(r.standard_normal(n - s), 900, 3200) * np.exp(-t[:n - s] / 0.006) * a
    s = N(0.028)
    y[s:] += band(r.standard_normal(n - s), 700, 3000) * np.exp(-t[:n - s] / 0.065) * 0.9
    y += 0.35 * np.sin(2 * np.pi * 185 * t) * np.exp(-t / 0.05) * peak(y) * 0.7
    y *= np.minimum(1.0, t / 0.0005) * np.minimum(1.0, np.maximum(0.0, (d - t) / 0.02))
    return nrm(y, 0.8)


@lru_cache(maxsize=None)
def hat(is_open=False, variant=0):
    r = np.random.default_rng(500 + variant)
    n = N(0.35 if is_open else 0.07)
    t = tn(n)
    x = lp(hp(r.standard_normal(n), 6500, n=2), 13000)
    x *= np.exp(-t / (0.10 if is_open else 0.014)) * np.minimum(1.0, t / 0.0004)
    x *= np.minimum(1.0, np.maximum(0.0, (n / SR - t) / 0.01))
    return nrm(x, 0.5)


@lru_cache(maxsize=None)
def shaker(variant=0):
    r = np.random.default_rng(700 + variant)
    n = N(0.10)
    t = tn(n)
    x = band(r.standard_normal(n), 4500, 9500) * np.minimum(1.0, t / 0.012) * np.exp(-t / 0.03)
    x *= np.minimum(1.0, np.maximum(0.0, (n / SR - t) / 0.01))
    return nrm(x, 0.5)


@lru_cache(maxsize=None)
def rim():
    n = N(0.09)
    t = tn(n)
    r = np.random.default_rng(31)
    y = np.sin(2 * np.pi * 1650 * t) * np.exp(-t / 0.006) + 0.7 * np.sin(2 * np.pi * 880 * t) * np.exp(-t / 0.012)
    y += 0.5 * band(r.standard_normal(n), 1500, 6000) * np.exp(-t / 0.003)
    y *= np.minimum(1.0, t / 0.0005) * np.minimum(1.0, np.maximum(0.0, (n / SR - t) / 0.01))
    return nrm(y, 0.7)


@lru_cache(maxsize=None)
def crash(d=1.6, tau=0.5, variant=0):
    r = np.random.default_rng(900 + variant)
    n = N(d)
    t = tn(n)
    x = band(r.standard_normal(n), 5000, 12500) + 0.4 * band(r.standard_normal(n), 2500, 5000)
    x *= np.exp(-t / tau) * np.minimum(1.0, t / 0.002) * np.minimum(1.0, np.maximum(0.0, (d - t) / 0.05))
    return nrm(x, 0.7)


def riser(d):
    n = N(d)
    t = tn(n)
    x = sweep(noise(n), (400, 6500), 'bp', q=1.2)
    x *= (t / d) ** 2 * np.minimum(1.0, np.maximum(0.0, (d - t) / 0.01))
    return nrm(x, 0.7)


def brass(m, d, vel=1.0, tail=0.25, vib=0.0):
    f = float(mtof(m))
    n = N(d + tail)
    t = tn(n)
    ft = f * (1 - 0.03 * np.exp(-t / 0.03))
    ft = ft * (1 + vib * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.15) / 0.3, 0, 1))
    y = np.zeros(n)
    for det in (-0.004, 0.0, 0.004):
        ph = phase_of(ft * (1 + det))
        for h in range(1, 15):
            if f * h > 5500:
                break
            att = 1 - np.exp(-t / (0.012 + 0.011 * h))
            y += (1.0 / h ** 0.95) * att * np.sin(h * ph)
    y = lp(y, 4800) * gate_env(n, d, atk=0.02, rel=0.07) / 3.0
    return vel * y


def duck_env(n, period_s, depth=0.5, rel=0.16):
    s = np.mod(np.arange(n) / SR, period_s)
    return 1.0 - depth * np.exp(-s / rel) * np.minimum(1.0, s / 0.0015)


def parse_bar(txt):
    out = []
    for tok in txt.split():
        nme, s, l = tok.split(':')
        out.append((float(s), nm(nme), float(l)))
    return out


def scale_step(m, k, tonic=0, scale=(0, 2, 4, 5, 7, 9, 11)):
    pcs = [(tonic + s) % 12 for s in scale]
    step = 1 if k > 0 else -1
    for _ in range(abs(k)):
        m += step
        while m % 12 not in pcs:
            m += step
    return m


# ----------------------------------------------------------------------------------------
# bgm_menu : relaxed sunny pop, C major, 104 BPM, 16 bars
# ----------------------------------------------------------------------------------------
def build_menu():
    seed('bgm_menu')
    bpm, bars = 104.0, 16
    beat = 60.0 / bpm
    bar = 4 * beat
    slot = beat / 2
    n = int(round(bars * bar * SR))
    B = {k: Mix(n) for k in ('uke', 'mel', 'bell', 'bass', 'perc', 'pad')}
    chords = ['C', 'G', 'Am', 'F', 'C', 'G', 'F', 'G'] * 2
    UKE = {'C': [60, 64, 67, 72], 'G': [62, 67, 67, 71], 'Am': [60, 64, 69, 69], 'F': [60, 65, 69, 69]}
    ROOT = {'C': 36, 'G': 43, 'Am': 45, 'F': 41}
    PAD = {'C': [60, 64, 67], 'G': [59, 62, 67], 'Am': [60, 64, 69], 'F': [60, 65, 69]}
    strum_pat = [(0, 'd', 1.0), (2, 'd', 0.8), (3, 'u', 0.6), (5, 'u', 0.55), (6, 'd', 0.9), (7, 'u', 0.5)]
    bass_pat = [(0, 0, 2), (3, 7, 1), (4, 0, 2), (6, 12, 1), (7, 7, 1)]

    A = [parse_bar(s) for s in (
        'E5:0:1 G5:1:1 C6:2:3 G5:5:1 E5:6:2',
        'D5:0:1 G5:1:1 B5:2:3 G5:5:1 D5:6:2',
        'E5:0:1 A5:1:1 C6:2:2 B5:4:1 A5:5:1 G5:6:2',
        'F5:0:1 A5:1:1 C6:2:2 A5:4:2 F5:6:2',
        'E5:0:1 G5:1:1 C6:2:3 D6:5:1 E6:6:2',
        'D6:0:2 B5:2:1 G5:3:1 B5:4:2 D6:6:2',
        'C6:0:2 A5:2:1 F5:3:1 A5:4:1 C6:5:1 A5:6:2',
        'B5:0:2 G5:2:1 D5:3:1 G5:4:4')]
    Bv = A[:6] + [parse_bar('C6:0:1 A5:1:1 F6:2:2 E6:4:1 C6:5:1 A5:6:2'),
                  parse_bar('B5:0:1 D6:1:1 G6:2:2 F6:4:1 D6:5:1 B5:6:2')]
    melody = A + Bv

    for b in range(bars):
        t0 = b * bar
        c = chords[b]
        second = b >= 8
        # ukulele strums
        for s, dirn, v in strum_pat:
            notes = sorted(UKE[c])
            if dirn == 'u':
                notes = notes[::-1][:3]
            for i, m in enumerate(notes):
                B['uke'].add(pluck(m, 0.55), t0 + s * slot + i * 0.007, 0.8 * v * (0.85 if dirn == 'u' else 1.0),
                             pan=-0.25, haas=7)
        # warm bass
        for s, semi, ln in bass_pat:
            B['bass'].add(bass_soft(ROOT[c] + semi, ln * slot * 0.9), t0 + s * slot,
                          1.0 if s == 0 else 0.8)
        # pad
        for m in PAD[c]:
            B['pad'].add(pad(m, bar + 0.5), t0 - 0.12, 1.0, pan=0.0, haas=12)
        # groove: shaker, rim, soft kick
        for s in range(8):
            B['perc'].add(shaker(s % 3), t0 + s * slot, 0.55 if s % 2 == 0 else 0.9, pan=0.35)
            B['perc'].add(shaker((s + 1) % 3), t0 + (s + 0.5) * slot, 0.22, pan=0.4)
        for s, v in ((2, 0.85), (6, 0.85)):
            B['perc'].add(rim(), t0 + s * slot, v, pan=-0.3)
        if second:
            B['perc'].add(rim(), t0 + 7.5 * slot, 0.35, pan=-0.3)
        B['perc'].add(kick(0.5, soft=True), t0, 0.55, pan=0.0)
        B['perc'].add(kick(0.35, soft=True), t0 + 4 * slot, 0.4, pan=0.0)
        # melody
        for s, m, ln in melody[b]:
            ts = t0 + s * slot
            d = min(1.1, ln * slot + 0.45)
            B['mel'].add(marimba(m, d, 1.0), ts, 0.9 if ln < 2 else 1.0, pan=0.12)
            if second:
                if ln >= 3 or (s == 0 and ln >= 1):
                    g = scale_step(m, -1)
                    B['mel'].add(marimba(g, 0.2, 1.0), ts - 0.5 * slot * 0.6, 0.35, pan=0.12)
                if ln >= 2:
                    B['bell'].add(glass(float(mtof(m + 12)), 0.5), ts, 0.16, pan=-0.35, haas=10)

    # polish / sends
    mel = reverb(pingpong(B['mel'].buf, 0.75 * beat, fb=0.45, taps=4, mix=0.33), 1.5, 0.28)
    bell = reverb(B['bell'].buf, 1.6, 0.35)
    uke = reverb(B['uke'].buf, 1.1, 0.18)
    pad_b = reverb(B['pad'].buf, 1.8, 0.30)
    perc = reverb(B['perc'].buf, 0.5, 0.08)
    bass = B['bass'].buf
    mix = 0.50 * uke + 0.75 * mel + 0.45 * bell + 0.80 * bass + 0.70 * perc + 0.22 * pad_b
    return master(mix, True, label='bgm_menu'), dict(bpm=bpm, bars=bars, n=n)


# ----------------------------------------------------------------------------------------
# bgm_match : energetic cute sports track, D major (I-V-vi-IV), 126 BPM, 16 bars
# ----------------------------------------------------------------------------------------
def build_match():
    seed('bgm_match')
    bpm, bars = 126.0, 16
    beat = 60.0 / bpm
    bar = 4 * beat
    slot = beat / 4
    n = int(round(bars * bar * SR))
    B = {k: Mix(n) for k in ('kick', 'clap', 'hat', 'bass', 'stab', 'mel', 'lead', 'arp', 'fx')}
    prog = ['D', 'A', 'Bm', 'G']
    ROOT = {'D': 38, 'A': 45, 'Bm': 47, 'G': 43}
    STAB = {'D': (62, 66, 69, 74), 'A': (61, 64, 69, 73), 'Bm': (62, 66, 71, 74), 'G': (62, 67, 71, 74)}
    ARP = {'D': [66, 69, 74, 78], 'A': [64, 69, 73, 76], 'Bm': [66, 71, 74, 78], 'G': [67, 71, 74, 79]}
    bass_pat = [(0, 0, 2), (3, 0, 1), (6, 12, 1), (8, 0, 2), (11, 7, 1), (14, 12, 1)]
    arp_idx = [0, 1, 2, 3, 2, 1, 2, 3, 0, 1, 2, 3, 2, 1, 2, 3]

    M1 = [parse_bar(s) for s in (
        'F#5:0:2 A5:2:2 D6:4:4 C#6:8:2 A5:10:2 F#5:12:4',
        'E5:0:2 A5:2:2 C#6:4:4 B5:8:2 A5:10:2 E5:12:4',
        'D5:0:2 F#5:2:2 B5:4:4 A5:8:2 F#5:10:2 D5:12:2 F#5:14:2',
        'B5:0:2 D6:2:2 B5:4:2 G5:6:2 A5:8:2 B5:10:2 A5:12:4')]
    M2 = [parse_bar(s) for s in (
        'A5:0:3 D6:3:1 F#6:4:4 E6:8:2 D6:10:2 A5:12:4',
        'C#6:0:3 E6:3:1 E6:4:4 D6:8:2 C#6:10:2 A5:12:4',
        'D6:0:2 B5:2:2 F#5:4:2 B5:6:2 D6:8:4 C#6:12:4',
        'B5:0:2 D6:2:2 E6:4:4 D6:8:2 B5:10:2 A5:12:4')]
    M1v = M1[:3] + [parse_bar('B5:0:2 D6:2:2 B5:4:2 G5:6:2 A5:8:1 B5:9:1 C#6:10:2 D6:12:4')]
    melody = M1 + M1 + M2 + M1v          # bars 1-4, 5-8, 9-12, 13-16
    lead_bars = set(range(4, 16))
    for b in range(bars):
        c = prog[b % 4]
        t0 = b * bar
        phase = b // 4            # 0 intro, 1 build, 2 breakdown-lite, 3 full
        # kick (four on the floor)
        for k in range(4):
            B['kick'].add(kick(1.0 if phase != 2 else 0.8), t0 + k * beat, 1.0)
        # clap / snare on 2 & 4
        for k, s in enumerate((4, 12)):
            v = 0.55 if phase == 2 else (0.85 if phase == 0 else 1.0)
            if b == 15 and s == 12:
                continue
            B['clap'].add(clap(k + 2 * (b % 2)), t0 + s * slot, v, pan=0.05)
        if b == 15:   # fill into the loop point
            for i, s in enumerate((8, 10, 12, 13, 14, 15)):
                B['clap'].add(clap(i % 4), t0 + s * slot, 0.45 + 0.1 * i, pan=0.05)
        # hats
        for s in range(0, 16, 2):
            if s == 14 and b % 4 == 3:
                continue
            B['hat'].add(hat(False, (s // 2) % 3), t0 + s * slot, 0.9 if s % 4 == 2 else 0.5, pan=0.2)
        if b % 4 == 3:
            B['hat'].add(hat(True, 0), t0 + 14 * slot, 0.7, pan=0.2)
        if phase in (1, 3):
            for s in range(1, 16, 2):
                B['hat'].add(hat(False, (s // 2) % 3), t0 + s * slot, 0.28, pan=0.3)
        # bass
        for s, semi, ln in bass_pat:
            B['bass'].add(bass_pluck(ROOT[c] + semi, ln * slot * 0.9), t0 + s * slot, 1.0 if s % 8 == 0 else 0.8)
        # stabs (offbeat) or arps in the breakdown
        if phase != 2:
            offs = [2, 6, 10, 14] if b % 4 != 3 else [2, 6, 10, 12, 14]
            for i, s in enumerate(offs):
                B['stab'].add(stab(STAB[c], 0.14), t0 + s * slot, 1.0 if s % 8 == 2 else 0.8,
                              pan=-0.15 if i % 2 == 0 else 0.15, haas=11)
        else:
            for i, ix in enumerate(arp_idx):
                m = ARP[c][ix]
                B['arp'].add(pluck(m, 0.28, tau0=0.12), t0 + i * slot, 0.8 if i % 4 == 0 else 0.55,
                             pan=-0.45 if i % 2 == 0 else 0.45)
        # melody (marimba always, soft synth lead from bar 5)
        for s, m, ln in melody[b]:
            ts = t0 + s * slot
            B['mel'].add(marimba(m, min(1.0, ln * slot + 0.35)), ts, 1.0, pan=0.1)
            if b in lead_bars:
                B['lead'].add(lead_soft(m, ln * slot * 0.92), ts, 0.8, pan=-0.1, haas=9)
        # crash on every 4th downbeat
        if b % 4 == 0:
            B['fx'].add(crash(1.8, 0.55, b // 4), t0, 0.6 if b == 0 else 0.45, pan=0.1)
    B['fx'].add(riser(2 * bar), 14 * bar, 0.55)

    duck = duck_env(n, beat, 0.50, 0.17)
    duck_lead = duck_env(n, beat, 0.25, 0.14)
    stab_b = reverb(B['stab'].buf * duck, 0.6, 0.15)
    arp_b = reverb(pingpong(B['arp'].buf * duck, 0.75 * beat, fb=0.4, taps=4, mix=0.3), 0.9, 0.2)
    mel_b = reverb(B['mel'].buf, 1.0, 0.22)
    lead_b = reverb(B['lead'].buf * duck_lead, 1.0, 0.2)
    clap_b = reverb(B['clap'].buf, 0.55, 0.22)
    fx_b = B['fx'].buf
    mix = 0.85 * B['kick'].buf + 0.70 * clap_b + 0.65 * B['hat'].buf + 0.75 * B['bass'].buf * (0.7 + 0.3 * duck) \
        + 0.38 * stab_b + 0.70 * mel_b + 0.35 * lead_b + 0.40 * arp_b + 0.50 * fx_b
    return master(mix, True, label='bgm_match'), dict(bpm=bpm, bars=bars, n=n)


# ----------------------------------------------------------------------------------------
# jingles (no loop)
# ----------------------------------------------------------------------------------------
def build_jingle_win():
    seed('jingle_win')
    d = 5.0
    n = N(d)
    B = {k: Mix(n, wrap=False) for k in ('brass', 'mar', 'fx')}
    C = [60, 64, 67, 72]
    for i, t in enumerate((0.0, 0.25, 0.5)):
        for m in C:
            B['brass'].add(brass(m, 0.17, 0.8), t, 1.0, pan=0.0, haas=6)
    for m in (60, 65, 69, 72):
        B['brass'].add(brass(m, 0.42, 0.9), 0.75, 1.0, haas=6)
    for m in (62, 67, 71, 74):
        B['brass'].add(brass(m, 0.20, 0.9), 1.25, 1.0, haas=6)
    for m in (60, 64, 67, 72, 76):
        B['brass'].add(brass(m, 2.2, 1.0, vib=0.004), 1.5, 1.0, haas=6)
    B['brass'].add(brass(48, 2.2, 1.0, vib=0.003), 1.5, 1.2)
    B['brass'].add(brass(36, 1.0, 0.8), 1.5, 0.8)
    run = [72, 74, 76, 79, 81, 84, 86, 88, 91, 96]
    for i, m in enumerate(run):
        B['mar'].add(marimba(m, 0.5), 1.5 + 0.055 * i, 0.75 + 0.02 * i, pan=0.25 if i % 2 else -0.25)
    for m in (84, 88, 91):
        B['mar'].add(marimba(m, 0.8), 1.5, 0.6, pan=0.0)
    for i, m in enumerate((96, 100, 103)):
        B['fx'].add(glass(float(mtof(m)), 0.7), 2.1 + 0.06 * i, 0.22, pan=-0.3 + 0.3 * i)
    B['fx'].add(crash(2.2, 0.7, 3), 1.5, 0.65)
    B['fx'].add(crash(1.0, 0.25, 4), 0.0, 0.2)
    B['fx'].add(kick(0.9, 0.5), 1.5, 0.5)
    mix = reverb(B['brass'].buf * 0.8 + B['mar'].buf * 0.8 + B['fx'].buf, 1.0, 0.22, circular=False)
    mix = mix[:, :n]
    mix[:, -N(0.4):] *= (0.5 + 0.5 * np.cos(np.pi * np.arange(N(0.4)) / N(0.4)))
    return master(mix, False, label='jingle_win'), n


def build_jingle_lose():
    seed('jingle_lose')
    d = 4.0
    n = N(d)
    B = {k: Mix(n, wrap=False) for k in ('mar', 'syn')}
    for i, (m, t, dd) in enumerate(((76, 0.0, 0.5), (74, 0.32, 0.5), (72, 0.64, 0.5), (69, 0.96, 0.9))):
        B['mar'].add(marimba(m, dd + 0.3), t, 1.0, pan=0.15)
    for m in (45, 48, 52):
        B['syn'].add(_muted(m, 3.2, wah=(300.0, 600.0)), 0.0, 0.35, pan=-0.1, haas=8)
    B['syn'].add(_muted(57, 0.42, wah=(350.0, 1300.0)), 1.55, 0.9, pan=0.05)
    B['syn'].add(_muted(56, 0.42, wah=(350.0, 1300.0)), 2.05, 0.9, pan=0.05)
    B['syn'].add(_muted(55, 1.0, slide=-1.8, vib=0.012, wah=(350.0, 1500.0)), 2.55, 1.0, pan=0.05)
    mix = reverb(B['mar'].buf * 0.9 + B['syn'].buf * 0.8, 0.9, 0.22, circular=False)[:, :n]
    mix[:, -N(0.5):] *= (0.5 + 0.5 * np.cos(np.pi * np.arange(N(0.5)) / N(0.5)))
    return master(mix, False, label='jingle_lose'), n


# ----------------------------------------------------------------------------------------
# music output
# ----------------------------------------------------------------------------------------
def encode_ogg(st, name, tmpdir):
    wav = os.path.join(tmpdir, name + '.wav')
    write_wav(wav, st, 2, 4)
    out = os.path.join(MUS_DIR, name + '.ogg')
    subprocess.run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-i', wav,
                    '-c:a', 'libvorbis', '-q:a', '4', '-ar', str(SR), '-ac', '2', out], check=True)
    return out


def gen_music():
    os.makedirs(MUS_DIR, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix='gosports_audio_')
    info = {}
    try:
        for name, fn in (('bgm_menu', build_menu), ('bgm_match', build_match)):
            print('  building', name, '...')
            st, meta = fn()
            assert np.all(np.isfinite(st)), name
            assert st.shape[1] == meta['n']
            encode_ogg(st, name, tmp)
            info[name] = meta
        for name, fn in (('jingle_win', build_jingle_win), ('jingle_lose', build_jingle_lose)):
            print('  building', name, '...')
            st, n = fn()
            assert np.all(np.isfinite(st)), name
            encode_ogg(st, name, tmp)
            info[name] = dict(n=n)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return info


# ----------------------------------------------------------------------------------------
# verification + README
# ----------------------------------------------------------------------------------------
def read_wav(path):
    with wave.open(path, 'rb') as w:
        n, ch, sw, fr = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(n)
    assert sw == 2 and fr == SR, (path, sw, fr)
    x = np.frombuffer(raw, dtype='<i2').astype(np.float64) / 32768.0
    return x.reshape(-1, ch).T, ch


def decode_ogg(path):
    r = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                       capture_output=True, check=True)
    return np.frombuffer(r.stdout, dtype='<f4').astype(np.float64).reshape(-1, 2).T


def verify():
    ok = True
    rows = {}
    print('\nVERIFY sfx')
    for name, d, _, _ in SFX_SPEC:
        p = os.path.join(SFX_DIR, name + '.wav')
        if not os.path.isfile(p):
            print('  MISSING', p)
            ok = False
            continue
        x, ch = read_wav(p)
        n = x.shape[1]
        pk = peak(x)
        rms = float(np.sqrt(np.mean(x ** 2)))
        bad = (not np.all(np.isfinite(x))) or pk < 1e-3 or ch != 1 or n != N(d)
        edge = max(abs(x[0, 0]), abs(x[0, -1]))
        print('  %-14s n=%7d (%.3fs) peak %6.2f dBFS rms %6.1f dBFS edge %.4f %s' %
              (name, n, n / SR, 20 * np.log10(pk + 1e-12), 20 * np.log10(rms + 1e-12), edge, 'FAIL' if bad else 'ok'))
        ok &= not bad
        rows[name] = n
    print('VERIFY music')
    for name in ('bgm_menu', 'bgm_match', 'jingle_win', 'jingle_lose'):
        p = os.path.join(MUS_DIR, name + '.ogg')
        if not os.path.isfile(p):
            print('  MISSING', p)
            ok = False
            continue
        x = decode_ogg(p)
        n = x.shape[1]
        pk = peak(x)
        l = lufs(x)
        jump = float(np.max(np.abs(x[:, 0] - x[:, -1])))
        typ = float(np.mean(np.abs(np.diff(x, axis=1))))
        bad = (not np.all(np.isfinite(x))) or pk < 0.05 or pk > 1.0
        print('  %-12s n=%8d (%.3fs) peak %6.2f dBFS  %.1f LUFS  loop-seam step %.4f (typ step %.4f) %s' %
              (name, n, n / SR, 20 * np.log10(pk + 1e-12), l, jump, typ, 'FAIL' if bad else 'ok'))
        ok &= not bad
        rows[name] = n
    return ok, rows


def write_readme(rows, info):
    L = []
    L.append('# go-sports audio assets\n')
    L.append('All files are synthesised by `tools/gen_audio.py` (numpy/scipy only, no samples). '
             'Re-run `python tools/gen_audio.py` to regenerate; it is deterministic.\n')
    L.append('## SFX (`sfx/*.wav`, 16-bit PCM, mono, 44100 Hz, peak about -3 dBFS)\n')
    L.append('| file | duration (s) | samples |')
    L.append('|---|---|---|')
    for name, d, _, _ in SFX_SPEC:
        n = rows[name]
        extra = ''
        if name == 'crowd_loop':
            extra = ' (seamless loop, peak about -12 dBFS, no fades)'
        L.append('| %s.wav%s | %.3f | %d |' % (name, extra, n / SR, n))
    L.append('\nNotes: every one-shot has a 5 ms fade-in and a short fade-out. Impact sounds start their transient '
             'about 3 ms in so the fade-in does not soften the hit. `step1..3` are 3 variations for random picking. '
             '`hover/click/step` are normalised like everything else, so set their volume in the engine.\n')
    L.append('## Music (`music/*.ogg`, libvorbis q4, stereo, 44100 Hz)\n')
    L.append('| file | BPM | bars | key | loop / total length (s) | samples | loops? |')
    L.append('|---|---|---|---|---|---|---|')
    keys = {'bgm_menu': 'C major', 'bgm_match': 'D major (I-V-vi-IV)'}
    for name in ('bgm_menu', 'bgm_match'):
        m = info[name]
        n = rows[name]
        L.append('| %s.ogg | %g | %d | %s | %.4f | %d | yes, seamless (tail of last bar is mixed onto bar 1) |' %
                 (name, m['bpm'], m['bars'], keys[name], n / SR, n))
    for name, key in (('jingle_win', 'C major'), ('jingle_lose', 'A minor')):
        n = rows[name]
        L.append('| %s.ogg | - | - | %s | %.3f | %d | no (one-shot) |' % (name, key, n / SR, n))
    L.append('\nBar length: bgm_menu = 4 x 60/104 s = 2.3077 s (16 bars = 36.9231 s, rounded to the nearest sample); '
             'bgm_match = 4 x 60/126 s = 1.9048 s (16 bars = 30.4762 s, exactly 1344000 samples). '
             'Music is mastered to about -16 LUFS integrated with a -1 dBFS look-ahead limiter ceiling '
             '(actual peaks are about -4.5 dBFS); the jingles use the same target.')
    L.append('\nLoop usage in Godot: set `loop = true` on the imported OggVorbis stream of `bgm_menu` and `bgm_match` '
             '(the length is an exact whole number of bars, so `loop_offset = 0` is correct). '
             '`sfx/crowd_loop.wav` is a loopable ambience: in the WAV import settings set Loop Mode = Forward '
             '(begin 0, end = last sample).\n')
    L.append('## Regenerating\n')
    L.append('`python tools/gen_audio.py [sfx|music|all]` - requires numpy, scipy and `ffmpeg` with libvorbis on PATH '
             '(music only). Temporary music wavs are written to the system temp dir and deleted afterwards.')
    with open(os.path.join(AUDIO_DIR, 'README.md'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(L) + '\n')


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    os.makedirs(AUDIO_DIR, exist_ok=True)
    info = {}
    if what in ('all', 'sfx'):
        print('SFX')
        gen_sfx(sys.argv[2:] or None)
    if what in ('all', 'music'):
        print('MUSIC')
        info = gen_music()
    ok, rows = verify()
    if what == 'all':
        write_readme(rows, info)
        print('README written')
    print('ALL OK' if ok else 'PROBLEMS FOUND')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())

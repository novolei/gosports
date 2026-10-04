"""Subtitle timing: where does each subtitle chunk of a narration line start / end?
The chunk boundaries are placed proportionally by (non-punctuation) character count over the SPEAKING part of the clip and then snapped to the
nearest real pause (>= 80 ms of silence) within 0.5 s, so a comma in the text lines up with the breath in the audio."""
from __future__ import annotations

import json
import re
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
PUNCT = re.compile(r"[\s，。；：、！？,.;:!?—\-「」“”\"'（）()]")


def speech_activity(wav: np.ndarray, sr: int, thr_rel: float = 0.045, hop: float = 0.01):
    """-> (t_start, t_end, gaps[(g0, g1)]) of the speech in a mono clip"""
    h = max(1, int(sr * hop))
    n = len(wav) // h
    env = np.sqrt((wav[: n * h].reshape(n, h) ** 2).mean(axis=1))
    thr = max(env.max() * thr_rel, 1e-4)
    act = env > thr
    if not act.any():
        return 0.0, len(wav) / sr, []
    i0 = int(np.argmax(act))
    i1 = n - int(np.argmax(act[::-1]))
    gaps = []
    run = None
    for i in range(i0, i1):
        if not act[i]:
            run = i if run is None else run
        elif run is not None:
            if (i - run) * hop >= 0.08:
                gaps.append((run * hop, i * hop))
            run = None
    return i0 * hop, i1 * hop, gaps


def chunk_spans(line_id: str, chunks: list, tts_dir: Path | None = None, lang: str = "zh"):
    """-> [(t0, t1)] seconds relative to the start of the line's audio, one per chunk"""
    tts_dir = tts_dir or ROOT / "promo_work" / "tts" / lang
    wav, sr = sf.read(tts_dir / f"{line_id}.wav", dtype="float32")
    if wav.ndim > 1:
        wav = wav.mean(axis=1)
    a, b, gaps = speech_activity(wav, sr)
    if len(chunks) == 1:
        return [(max(0.0, a - 0.05), b + 0.25)]
    counts = [max(1, len(PUNCT.sub("", c[0 if lang == "zh" else 1]))) for c in chunks]
    tot = sum(counts)
    bounds = []
    acc = 0
    for c in counts[:-1]:
        acc += c
        tgt = a + (b - a) * acc / tot
        best = tgt
        bd = 0.5
        for g0, g1 in gaps:
            mid = (g0 + g1) / 2
            if abs(mid - tgt) < bd:
                bd = abs(mid - tgt)
                best = mid
        bounds.append(best)
    edges = [max(0.0, a - 0.05)] + bounds + [b + 0.25]
    return [(edges[i], edges[i + 1]) for i in range(len(chunks))]


if __name__ == "__main__":
    script = json.loads((ROOT / "promo" / "script.json").read_text(encoding="utf-8"))
    for ln in script["lines"]:
        sp = chunk_spans(ln["id"], ln["chunks"])
        print(ln["id"], " | ".join(f"{a:.2f}-{b:.2f}" for a, b in sp))

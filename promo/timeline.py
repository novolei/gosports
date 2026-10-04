"""The narration schedule of the promo (seconds on the final timeline) and helpers shared by the edit / audio builders."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = json.loads((ROOT / "promo" / "script.json").read_text(encoding="utf-8"))
LINES = {l["id"]: l for l in SCRIPT["lines"]}
ORDER = [l["id"] for l in SCRIPT["lines"]]


def _durs(lang: str = "zh") -> dict:
    t = json.loads((ROOT / "promo_work" / "tts" / lang / "timing.json").read_text(encoding="utf-8"))
    return {k: v["dur"] for k, v in t.items()}


def make_schedule(lang: str = "zh") -> dict:
    """start time of every narration line.  Gaps are chosen per boundary so the sections breathe where the story changes."""
    d = _durs(lang)
    gap_after = {"n02": 0.5, "n06": 0.8, "g05": 0.7, "n09": 0.9, "n16": 0.9, "n19": 0.9, "n20": 0.7}
    start = {}
    t = 6.5                                   # n01 starts right after the logo pops (logo hit at 6.0)
    for i, lid in enumerate(ORDER):
        start[lid] = round(t, 3)
        t += d[lid] + gap_after.get(lid, 0.5)
        if lid == "n01":
            t = 9.9                           # n02 starts after the logo card
        if lid == "n02":
            t = max(t, 17.4)                  # the gameplay chapter starts on a bar line
    return start


def make_sections(start: dict, lang: str = "zh") -> dict:
    """chapter boundaries derived from the schedule (used by the edit and by the music arranger)"""
    d = _durs(lang)
    end = lambda lid: start[lid] + d[lid]
    return {
        "logo": (6.0, 9.6),
        "intro_vo": (9.9, end("n02")),
        "play": (start["n03"] - 0.1, end("n06") + 0.2),
        "gag_title": (start["g01"] - 0.9, start["g01"] + 0.1),
        "gag": (start["g01"], end("g05") + 0.3),
        "celebrate": (start["n08"] - 0.1, end("n08") + 0.2),
        "modes": (start["n09"] - 0.1, end("n09") + 0.3),
        "story": (start["n10"] - 0.4, end("n16") + 0.4),
        "series": (start["n17"] - 0.4, end("n19") + 0.5),
        "outro": (start["n20"] - 0.4, end("n21") + 3.2),
    }


if __name__ == "__main__":
    s = make_schedule()
    for k in ORDER:
        print(k, s[k], round(s[k] + _durs()[k], 2))
    print(json.dumps(make_sections(s), indent=1))

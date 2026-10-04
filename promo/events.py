"""Read the game's own --log output of a recording to find the moments worth cutting to (times are match seconds, = movie seconds +-0.3)."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HIT = re.compile(r"^\[hit\] t=([\d.]+) team=(\d) (\S+) (\w+) (\w+) touch=(\d)")


def hits(clip: str, kind: str | None = None, quality: str | None = None, team: int | None = None):
    out = []
    p = ROOT / "promo_work" / "rec" / f"{clip}.log"
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        m = HIT.match(line)
        if not m:
            continue
        t, tm, name, k, q, touch = float(m.group(1)), int(m.group(2)), m.group(3), m.group(4), m.group(5), int(m.group(6))
        if kind and k != kind:
            continue
        if quality and q != quality:
            continue
        if team is not None and tm != team:
            continue
        out.append((t, tm, name, k, q, touch))
    return out


if __name__ == "__main__":
    clip = sys.argv[1]
    for k in ("serve", "spike", "block", "dive", "dig", "set", "bump"):
        h = hits(clip, k)
        print(k, len(h), [round(x[0], 1) for x in h][:40])

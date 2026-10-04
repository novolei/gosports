"""Export the subtitles of the promo as .srt files from the same timing the burned-in captions use.

  gosports_promo.zh.srt   Chinese captions, timed to the Chinese cut
  gosports_promo.bi.srt   Chinese + English lines, timed to the Chinese cut
  gosports_promo.en.srt   English captions, timed to the English cut (English narration)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import align
import timeline as TL

ROOT = Path(__file__).resolve().parents[1]


def ts(t: float) -> str:
    t = max(0.0, t)
    h, rem = divmod(t, 3600)
    m, s = divmod(rem, 60)
    ms = int(round((s - int(s)) * 1000))
    sec = int(s)
    if ms == 1000:
        sec, ms = sec + 1, 0
    return f"{int(h):02d}:{int(m):02d}:{sec:02d},{ms:03d}"


def build(lang: str, mode: str) -> str:
    start = TL.make_schedule(lang)
    rows, n = [], 0
    for lid in TL.ORDER:
        ln = TL.LINES[lid]
        spans = align.chunk_spans(lid, ln["chunks"], lang=lang)
        for (zh, en), (a, b) in zip(ln["chunks"], spans):
            n += 1
            txt = {"zh": zh, "en": en, "bi": zh + "\n" + en}[mode]
            rows.append(f"{n}\n{ts(start[lid] + a)} --> {ts(start[lid] + b)}\n{txt}\n")
    return "\n".join(rows)


def main(out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, lang, mode in (("zh", "zh", "zh"), ("bi", "zh", "bi"), ("en", "en", "en")):
        (out_dir / f"gosports_promo.{name}.srt").write_text(build(lang, mode), encoding="utf-8")
    print("wrote zh / bi / en srt ->", out_dir)


if __name__ == "__main__":
    main(ROOT / "promo" / "publish")

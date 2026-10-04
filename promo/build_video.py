"""Assemble the GoSports promo: timeline (shots + cards + chips + subtitles) -> frames; audio (narration + music + game audio + sfx) -> wav; mux.

  python promo/build_video.py preview            # 960x540, fast preset, whole film -> promo_work/out/preview.mp4
  python promo/build_video.py stills 6.0 20.5 …  # PNG stills of given times -> promo_work/out/stills/
  python promo/build_video.py audio              # mix the soundtrack only -> promo_work/out/mix.wav
  python promo/build_video.py final              # 1920x1080 60 fps, crf 16 -> promo_work/out/gosports_promo.mp4
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audio as A  # noqa: E402
import align  # noqa: E402
import cards  # noqa: E402
import cards2  # noqa: E402
import gfx  # noqa: E402
import nle  # noqa: E402
import timeline as TL  # noqa: E402
from nle import FadeBlack, Flash, LayerItem, Procedural, Shot, Timeline  # noqa: E402

import os  # noqa: E402

LANG = os.environ.get("PROMO_LANG", "zh")           # "zh" (Chinese narration, bilingual captions) or "en" (English narration, English captions)
cards.LANG = LANG
ROOT = Path(__file__).resolve().parents[1]
REC = ROOT / "promo_work" / "rec"
OUT = ROOT / "promo_work" / "out"
TTS = ROOT / "promo_work" / "tts" / LANG
SFX = ROOT / "assets" / "audio" / "sfx"
FPS = 60

START = TL.make_schedule(LANG)
SEC = TL.make_sections(START, LANG)
DUR = {k: v["dur"] for k, v in json.loads((TTS / "timing.json").read_text(encoding="utf-8")).items()}
TOTAL = SEC["outro"][1] + 0.4


def rec(name: str) -> str:
    p = REC / f"{name}.avi"
    if not p.exists():
        print(f"  ! missing recording {name}, using the old m1_day", file=sys.stderr)
        p = ROOT / "promo_work" / "rec_old" / "m1_day.avi"
        if not p.exists():
            p = REC / "m1_day.avi"
    return str(p)


# ================================================================== grading / helpers
def grade_pop(frame):
    """a touch more punch for the game footage (contrast + saturation), cheap"""
    import cv2
    f = cv2.convertScaleAbs(frame, alpha=1.06, beta=-6)
    hsv = cv2.cvtColor(f, cv2.COLOR_BGR2HSV).astype(np.float32)
    hsv[:, :, 1] = np.clip(hsv[:, :, 1] * 1.10, 0, 255)
    return cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2BGR)


class Edit:
    """collects items and audio events"""

    def __init__(self):
        self.tl = Timeline(fps=FPS)
        self.sfx: list[tuple[str, float, float]] = []             # (file stem, time, gain dB)
        self.clip_audio: list[tuple[str, float, float, float, float, float]] = []   # (rec name, src_in, dur, start, speed, gain dB)

    def shot(self, name: str, src_in: float, dur: float, start: float, *, audio_db: float | None = -10.0, **kw) -> Shot:
        kw.setdefault("grade", grade_pop)
        s = Shot(rec(name), src_in, dur, start, **kw)
        self.tl.add(s)
        if audio_db is not None:
            self.clip_audio.append((name, src_in, dur, start, kw.get("speed", 1.0), audio_db))
        return s

    def chip(self, title, sub, icon_name, start, dur, color=gfx.TEAL, pos=(60, 830), z=30):
        """title = (zh, en) pair (or a plain string); sub = the English caption under it"""
        if isinstance(title, tuple):
            title = title[1] if LANG == "en" else title[0]
        layer = cards.feature_chip(title, sub, icon_name, color, en_title=(LANG == "en"))
        self.tl.add(LayerItem(layer, start, start + dur, pos=pos, anchor=(0.0, 0.5), z=z,
                              anim_in=nle.slide_in("left", 220, 0.5), anim_out=nle.slide_out("left", 220, 0.3)))
        self.sfx.append(("ui_swoosh", start, -14.0))

    def proc(self, fn, start, end, z=5):
        self.tl.add(Procedural(fn, start, end, z=z))

    def add_sfx(self, name, t, db=-8.0):
        self.sfx.append((name, t, db))


# ================================================================== subtitles
def add_subtitles(ed: Edit, lang_pairs=True):
    band_on = []
    for lid in TL.ORDER:
        ln = TL.LINES[lid]
        spans = align.chunk_spans(lid, ln["chunks"], lang=LANG)
        for (zh, en), (a, b) in zip(ln["chunks"], spans):
            t0 = START[lid] + a
            t1 = START[lid] + b
            if LANG == "en":
                layer = cards.subtitle_layer(_wrap_en(en), None, primary_en=True)
            else:
                layer = cards.subtitle_layer(_wrap_sub(zh), en if lang_pairs else None)
            ed.tl.add(LayerItem(layer, t0, t1, pos=(gfx.W / 2, 985), anchor=(0.5, 0.5), z=80,
                                anim_in=nle.fade_in(0.12), anim_out=nle.fade_out(0.12)))
        band_on.append((START[lid] + spans[0][0], START[lid] + spans[-1][1]))
    # a soft dark band under the text, only while somebody talks
    band = cards.bottom_gradient(0.50, 300)
    for a, b in _merge(band_on, 0.35):
        ed.tl.add(LayerItem(band, a, b, pos=(0, gfx.H), anchor=(0.0, 1.0), z=70, anim_in=nle.fade_in(0.25), anim_out=nle.fade_out(0.35)))


def _wrap_sub(zh: str, n: int = 27) -> str:
    """long Chinese subtitle chunks go onto two lines: after a punctuation mark or a space, never inside a Latin word / number"""
    if len(zh) <= n:
        return zh
    mid = len(zh) / 2
    cands = []
    for i in range(1, len(zh)):
        prev, nxt = zh[i - 1], zh[i]
        ok = prev in "，；：、。—！？ " or nxt == " " or (ord(prev) > 0x2E80 and ord(nxt) > 0x2E80)
        if ok:
            cands.append(i)
    if not cands:
        return zh
    c = min(cands, key=lambda i: abs(i - mid))
    return zh[:c].rstrip() + "\n" + zh[c:].lstrip()


def _wrap_en(en: str, n: int = 62) -> str:
    """long English caption chunks go onto two lines at a space near the middle"""
    if len(en) <= n:
        return en
    mid = len(en) // 2
    best = min((i for i, c in enumerate(en) if c == " "), key=lambda i: abs(i - mid))
    return en[:best] + "\n" + en[best + 1:]


def _merge(spans, gap):
    spans = sorted(spans)
    out = [list(spans[0])]
    for a, b in spans[1:]:
        if a - out[-1][1] <= gap:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return [tuple(x) for x in out]


# ================================================================== the film
def close_gaps(ed: Edit, max_gap: float = 1.0) -> None:
    """chapters are cut independently, so tiny holes can remain between the last shot of one and the first of the next: stretch the item
    that ends right before each hole (a Shot keeps playing its source, a card holds its last state) so the picture is never black"""
    base = sorted((i for i in ed.tl.items if (isinstance(i, Shot) and i.rect is None) or isinstance(i, Procedural)), key=lambda i: i.start)
    cover_end = 0.0
    last = None
    for it in base:
        if it.start > cover_end + 1e-3 and last is not None:
            gap = it.start - cover_end
            if gap <= max_gap:
                last.end = it.start + 0.02
                if isinstance(last, Shot):
                    last.dur = last.end - last.start
            else:
                print(f"  ! gap of {gap:.2f} s at {cover_end:.2f} s left open")
        if it.end >= cover_end:
            cover_end = it.end
            last = it


def build_film() -> Edit:
    ed = Edit()
    import film_scenes  # the actual shot list lives next to the footage choices
    film_scenes.assemble(ed, START, SEC, DUR)
    close_gaps(ed)
    add_subtitles(ed)
    return ed


# ================================================================== audio
def build_audio(ed: Edit, music_path: Path | None = None) -> np.ndarray:
    mix = A.Mixer(TOTAL)
    for lid in TL.ORDER:
        mix.add("vo", A.load(TTS / f"{lid}.wav"), START[lid], gain_db=0.0, fi=0.01, fo=0.03)
    if music_path and music_path.exists():
        mix.add("music", A.load(music_path), 0.0, gain_db=-5.0)
    for name, t, db in ed.sfx:
        p = SFX / f"{name}.wav"
        if p.exists():
            mix.add("sfx", A.load(p), t, gain_db=db)
    for name, src_in, dur, start, speed, db in ed.clip_audio:
        p = REC / f"{name}.avi"
        if not p.exists():
            continue
        a = A.load(p, start=src_in, dur=dur * speed)
        if speed != 1.0:
            continue
        mix.add("game", a, start, gain_db=db, fi=0.04, fo=0.06)
    return mix.render(master_db=3.5)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "preview"
    OUT.mkdir(parents=True, exist_ok=True)
    ed = build_film()
    print(f"timeline: {ed.tl.duration:.1f} s, {len(ed.tl.items)} items, narration ends {START['n21'] + DUR['n21']:.1f} s")
    if cmd == "stills":
        import cv2
        d = OUT / "stills"
        d.mkdir(exist_ok=True)
        for t in [float(x) for x in sys.argv[2:]]:
            cv2.imwrite(str(d / f"t{t:07.2f}.png"), ed.tl.frame_at(t))
        ed.tl.close()
        return
    if cmd == "gaps":
        # report every stretch where no full-frame layer (a Shot without a rect, or a Procedural card) covers the picture
        base = [i for i in ed.tl.items if (isinstance(i, Shot) and i.rect is None) or isinstance(i, Procedural)]
        t, gap0 = 0.0, None
        while t < ed.tl.duration:
            cov = any(i.start <= t < i.end for i in base)
            if not cov and gap0 is None:
                gap0 = t
            if cov and gap0 is not None:
                print(f"  GAP {gap0:.2f}-{t:.2f} s ({t - gap0:.2f} s)")
                gap0 = None
            t += 1 / 60
        if gap0 is not None:
            print(f"  GAP {gap0:.2f}-end")
        print("gap scan done")
        ed.tl.close()
        return
    if cmd == "shotsheet":
        # one contact sheet per 8 footage shots: start / middle / end thumbnails of every Shot of the edit (to proof-read the picks)
        import cv2
        shots = sorted((i for i in ed.tl.items if isinstance(i, Shot) and i.rect is None), key=lambda i: i.start)
        d = OUT / "shotsheets"
        d.mkdir(exist_ok=True)
        per = 8
        for k in range(0, len(shots), per):
            rows = []
            for sh in shots[k:k + per]:
                ims = []
                for f in (0.08, 0.5, 0.92):
                    t = sh.start + sh.dur * f
                    fr = ed.tl.frame_at(min(t, sh.end - 1 / 60))
                    fr = cv2.resize(fr, (480, 270), interpolation=cv2.INTER_AREA)
                    cv2.putText(fr, f"{sh.start:.1f}s {Path(sh.path).stem} @{sh.src_in:.1f}", (6, 22), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2, cv2.LINE_AA)
                    ims.append(fr)
                rows.append(np.hstack(ims))
            cv2.imwrite(str(d / f"shots_{k // per:02d}.jpg"), np.vstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 85])
        print("sheets:", (len(shots) + per - 1) // per, "->", d)
        ed.tl.close()
        return
    mus = ROOT / "promo_work" / f"music_{LANG}.wav"
    if cmd == "audio":
        wav = build_audio(ed, mus)
        A.Mixer.write(OUT / f"mix_{LANG}.wav", wav)
        print("wrote", OUT / f"mix_{LANG}.wav")
        return
    wav = build_audio(ed, mus)
    A.Mixer.write(OUT / f"mix_{LANG}.wav", wav)
    if cmd == "preview":
        ed.tl.render(str(OUT / f"preview_{LANG}.mp4"), crf=26, preset="veryfast", scale=0.5, audio=str(OUT / f"mix_{LANG}.wav"), nvenc=True)
    else:
        t0 = float(os.environ.get("PROMO_T0", "0")); t1 = float(os.environ["PROMO_T1"]) if "PROMO_T1" in os.environ else None
        suffix = "" if t1 is None and t0 == 0 else f"_seg{int(t0)}-{int(t1 or 0)}"
        ed.tl.render(str(OUT / f"gosports_promo_{LANG}{suffix}.mp4"), t0=t0, t1=t1, crf=16, preset="medium", audio=str(OUT / f"mix_{LANG}.wav"))


if __name__ == "__main__":
    main()

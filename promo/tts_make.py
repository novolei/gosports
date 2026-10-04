"""Local narration for the GoSports promo video, with the Minitanks tutorial-voice toolchain (VoxCPM2, Apache-2.0).

Same recipe as H:/GDP/mini-tanks/tools/audio/tutorial_voice_*.py: the FIRST line designs an original voice from a text description,
every other line clones that reference with a per-line delivery direction, so the whole narration is one consistent voice.

Run with the Minitanks venv (CUDA torch + voxcpm):
  H:/GDP/mini-tanks/.tools/tutorial-voice/voxcpm/Scripts/python.exe promo/tts_make.py design [--n 4]   # candidate voices for line n01
  H:/GDP/mini-tanks/.tools/tutorial-voice/voxcpm/Scripts/python.exe promo/tts_make.py pick 2          # candidate 2 becomes the reference
  H:/GDP/mini-tanks/.tools/tutorial-voice/voxcpm/Scripts/python.exe promo/tts_make.py render --lang zh [--only n03,n04]
Output (git-ignored): promo_work/tts/<lang>/<id>.wav (48 kHz mono) + timing.json.  Check with promo/tts_check.py (faster-whisper ASR).
"""
from pathlib import Path
import argparse
import json
import shutil
import time

import numpy as np
import soundfile as sf
import torch
from voxcpm import VoxCPM

ROOT = Path(__file__).resolve().parents[1]
MODEL = Path("H:/GDP/mini-tanks/.tools/tutorial-voice/models/VoxCPM2")
OUT = ROOT / "promo_work" / "tts"
SCRIPT = json.loads((ROOT / "promo" / "script.json").read_text(encoding="utf-8"))


def load_model() -> VoxCPM:
    return VoxCPM.from_pretrained(str(MODEL), load_denoiser=False, device="cuda")


def direction(lang: str, mood: str, first: bool) -> str:
    role = SCRIPT["voice"][lang]
    if not first:
        role = "同一位解说员。" if lang == "zh" else "The same narrator. "
    return f"({role}{SCRIPT['moods'][mood][lang]})"


def save(path: Path, audio, sr: int) -> float:
    audio = np.asarray(audio, dtype=np.float32)
    peak = float(np.max(np.abs(audio))) if audio.size else 1.0
    if peak > 0.97:
        audio = audio * (0.97 / peak)
    sf.write(path, audio, sr)
    return len(audio) / float(sr)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=("design", "pick", "render"))
    ap.add_argument("arg", nargs="?")
    ap.add_argument("--n", type=int, default=4)
    ap.add_argument("--lang", default="zh")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    ref = OUT / f"ref_{a.lang}.wav"
    lines = SCRIPT["lines"]
    if a.cmd == "pick":
        src = OUT / f"cand_{a.lang}_{int(a.arg)}.wav"
        shutil.copy2(src, ref)
        print(f"reference for {a.lang} = {src.name}")
        return
    model = load_model()
    sr = model.tts_model.sample_rate
    if a.cmd == "design":
        first = lines[0]
        for k in range(1, a.n + 1):
            torch.manual_seed(7100 + k * 31)
            t0 = time.time()
            wav = model.generate(text=direction(a.lang, first["mood"], True) + first[a.lang], cfg_value=2.0,
                                 inference_timesteps=10, normalize=False, retry_badcase=True)
            dur = save(OUT / f"cand_{a.lang}_{k}.wav", wav, sr)
            print(f"cand {k}: {dur:.2f} s audio in {time.time() - t0:.1f} s", flush=True)
        return
    if not ref.exists():
        raise SystemExit(f"pick a reference first ({ref})")
    only = set(x for x in a.only.split(",") if x)
    dest = OUT / a.lang
    dest.mkdir(parents=True, exist_ok=True)
    timing_path = dest / "timing.json"
    timing = json.loads(timing_path.read_text(encoding="utf-8")) if timing_path.exists() else {}
    for i, ln in enumerate(lines):
        if only and ln["id"] not in only:
            continue
        torch.manual_seed(9100 + i * 17)
        t0 = time.time()
        wav = model.generate(text=direction(a.lang, ln["mood"], False) + ln[a.lang], reference_wav_path=str(ref),
                             cfg_value=2.0, inference_timesteps=10, normalize=False, retry_badcase=True)
        dur = save(dest / f"{ln['id']}.wav", wav, sr)
        timing[ln["id"]] = {"dur": round(dur, 3), "sr": sr}
        print(f"{ln['id']}: {dur:.2f} s  ({time.time() - t0:.1f} s to render)", flush=True)
        timing_path.write_text(json.dumps(timing, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()

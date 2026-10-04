"""ASR check of the narration with faster-whisper (the Minitanks check_tutorial_voice.py recipe).
Run with the Minitanks 'qwen' venv:  python promo/tts_check.py zh [cand|lines]"""
import json
import sys
from pathlib import Path
from faster_whisper import WhisperModel

ROOT = Path(__file__).resolve().parents[1]
lang = sys.argv[1] if len(sys.argv) > 1 else "zh"
what = sys.argv[2] if len(sys.argv) > 2 else "lines"
tts = ROOT / "promo_work" / "tts"
script = json.loads((ROOT / "promo" / "script.json").read_text(encoding="utf-8"))
model = WhisperModel("small", device="cpu", compute_type="int8", download_root="H:/GDP/mini-tanks/.tools/tutorial-voice/models/whisper")
files = sorted(tts.glob(f"cand_{lang}_*.wav")) if what == "cand" else sorted((tts / lang).glob("*.wav"))
want = {l["id"]: l[lang] for l in script["lines"]}
report = []
for p in files:
    segs, _ = model.transcribe(str(p), language=lang, beam_size=3)
    heard = "".join(s.text.strip() for s in segs)
    exp = want.get(p.stem, want["n01"])
    report.append({"file": p.name, "expected": exp, "heard": heard})
    print(f"{p.name}\n   exp: {exp}\n   got: {heard}", flush=True)
(tts / f"asr_{lang}_{what}.json").write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")

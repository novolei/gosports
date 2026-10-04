"""Numbers about narration clips (no ears needed): duration, loudness, F0 median / range, voiced ratio.
Run with the Minitanks voxcpm venv:  python promo/tts_probe.py promo_work/tts/cand_zh_*.wav"""
import sys
import numpy as np
import soundfile as sf
import torch
import torchaudio

for path in sys.argv[1:]:
    wav, sr = sf.read(path, dtype="float32")
    if wav.ndim > 1:
        wav = wav.mean(axis=1)
    x = torch.from_numpy(wav)
    f0 = torchaudio.functional.detect_pitch_frequency(x, sr, frame_time=0.02, freq_low=70, freq_high=420).numpy()
    rms = np.sqrt(np.convolve(wav ** 2, np.ones(int(0.02 * sr)) / int(0.02 * sr), mode="same"))[:: int(0.02 * sr)][: len(f0)]
    voiced = rms > 0.02
    f = f0[voiced[: len(f0)]] if voiced.any() else f0
    print("%-28s %5.2fs  peak %.2f  rms %.3f  voiced %.0f%%  F0 median %.0f Hz  p10-p90 %.0f-%.0f" % (
        path.split("/")[-1], len(wav) / sr, float(np.max(np.abs(wav))), float(np.sqrt(np.mean(wav ** 2))), 100 * float(voiced.mean()),
        float(np.median(f)), float(np.percentile(f, 10)), float(np.percentile(f, 90))))

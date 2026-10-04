# GoSports promo video — how it is made

Everything for the promo lives here and is reproducible from the repo + the local Minitanks TTS toolchain. Large work files go to `promo_work/`
(git-ignored, has a `.gdignore`).

| step | tool | output |
|---|---|---|
| script (zh + en, with subtitle chunks) | `script.json` | |
| narration (local VoxCPM2, one consistent voice) | `tts_make.py` (`design` → `pick N` → `render --lang zh/en`) with `H:/GDP/mini-tanks/.tools/tutorial-voice/voxcpm/Scripts/python.exe` | `promo_work/tts/<lang>/*.wav` |
| narration QA (faster-whisper ASR) | `tts_check.py <lang> lines` with the Minitanks `qwen` venv | `promo_work/tts/asr_*.json` |
| game footage (Godot Movie Maker, 1440p60, audio included) | `rec.sh`, `rec_batch1.sh`, `rec_batch2.sh` | `promo_work/rec/*.avi (+ .log)` |
| proof-reading footage | `sheet.sh <clip> fps cols rows start width`, `events.py`, `build_video.py shotsheet` | contact sheets |
| soundtrack (the game's own themes re-cut to 120 BPM) | `music.py --lang zh/en` | `promo_work/music_<lang>.wav` |
| the edit (shots, chips, cards, subtitles) | `film_scenes.py`, `film_shots.py`, `cards.py`, `cards2.py`, `nle.py`, `gfx.py` | |
| mix + render | `build_video.py preview|final` (`PROMO_LANG=zh|en`) | `promo_work/out/*.mp4`, `.srt` via `srt.py` |

Dev flags added to the game for recording: `--cleanhud` (no key-prompt row / skip chip), `--music=0 --sfx=0.9` (volumes for this run),
`--serveridx=1`, `--banter=… --banter_team=… --banter_final`, `--resultloss`; the Movie-Maker run also disables the focus-loss auto-pause
(`OS.has_feature("movie")`). A throw-away "veteran" profile for lived-in menus: `godot -s promo/make_profile.gd`, then `--profile=user://promo_profile.json`.

Notes / lessons
* 4K Movie-Maker capture ran 11x slower than real time on the RTX 5090 (readback bound); 1440p60 is ~2.3x real time and punches in cleanly to 1080p.
* The project's `window/size/window_*_override` decides the movie size: `rec.sh` writes a temporary `override.cfg` (git-ignored) per run.
* VoxCPM2 mispronounces the brand / model name in Chinese: use a spaced "Go Sports" and the transliteration "克劳德·索内特五点五" in the TTS text, but the
  correct spelling in the captions (`chunks` in `script.json` hold the on-screen text). In English use "Go Sports" and "Claude Sonnet five point five"; re-roll takes
  (`promo_work/alt_en.py` style) until the ASR hears the right words.
* Icons for the series card / gag title were made with Gemini (`art_src/gemini/gen_series_icons.ps1`, `gen_gag_icon.ps1`), keyed with `tools/key_icon.py`.
* The Python tool collapses doubled backslashes in heredocs: write `"\n"` through the Edit tool, not through `python - <<EOF`.

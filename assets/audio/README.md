# go-sports audio assets

All files are synthesised by `tools/gen_audio.py` (numpy/scipy only, no samples). Re-run `python tools/gen_audio.py` to regenerate; it is deterministic.

## SFX (`sfx/*.wav`, 16-bit PCM, mono, 44100 Hz, peak about -3 dBFS)

| file | duration (s) | samples |
|---|---|---|
| hit_bump.wav | 0.250 | 11025 |
| hit_set.wav | 0.180 | 7938 |
| hit_spike.wav | 0.300 | 13230 |
| hit_serve.wav | 0.280 | 12348 |
| hit_perfect.wav | 0.450 | 19845 |
| bounce.wav | 0.300 | 13230 |
| net_hit.wav | 0.450 | 19845 |
| block.wav | 0.350 | 15435 |
| jump.wav | 0.200 | 8820 |
| land.wav | 0.150 | 6615 |
| dive.wav | 0.450 | 19845 |
| step1.wav | 0.090 | 3969 |
| step2.wav | 0.090 | 3969 |
| step3.wav | 0.090 | 3969 |
| toss.wav | 0.300 | 13230 |
| swing_miss.wav | 0.300 | 13230 |
| whistle_short.wav | 0.350 | 15435 |
| whistle_long.wav | 0.900 | 39690 |
| cheer.wav | 2.500 | 110250 |
| crowd_loop.wav (seamless loop, peak about -12 dBFS, no fades) | 8.000 | 352800 |
| ui_click.wav | 0.120 | 5292 |
| ui_hover.wav | 0.060 | 2646 |
| ui_confirm.wav | 0.350 | 15435 |
| ui_back.wav | 0.200 | 8820 |
| ui_swoosh.wav | 0.500 | 22050 |
| countdown.wav | 0.250 | 11025 |
| go.wav | 0.500 | 22050 |
| perfect.wav | 0.500 | 22050 |
| point_win.wav | 1.400 | 61740 |
| point_lose.wav | 1.200 | 52920 |
| match_point.wav | 1.000 | 44100 |

Notes: every one-shot has a 5 ms fade-in and a short fade-out. Impact sounds start their transient about 3 ms in so the fade-in does not soften the hit. `step1..3` are 3 variations for random picking. `hover/click/step` are normalised like everything else, so set their volume in the engine.

## Music (`music/*.ogg`, libvorbis q4, stereo, 44100 Hz)

| file | BPM | bars | key | loop / total length (s) | samples | loops? |
|---|---|---|---|---|---|---|
| bgm_menu.ogg | 104 | 16 | C major | 36.9231 | 1628308 | yes, seamless (tail of last bar is mixed onto bar 1) |
| bgm_match.ogg | 126 | 16 | D major (I-V-vi-IV) | 30.4762 | 1344000 | yes, seamless (tail of last bar is mixed onto bar 1) |
| jingle_win.ogg | - | - | C major | 5.000 | 220500 | no (one-shot) |
| jingle_lose.ogg | - | - | A minor | 4.000 | 176400 | no (one-shot) |

Bar length: bgm_menu = 4 x 60/104 s = 2.3077 s (16 bars = 36.9231 s, rounded to the nearest sample); bgm_match = 4 x 60/126 s = 1.9048 s (16 bars = 30.4762 s, exactly 1344000 samples). Music is mastered to about -16 LUFS integrated with a -1 dBFS look-ahead limiter ceiling (actual peaks are about -4.5 dBFS); the jingles use the same target.

Loop usage in Godot: set `loop = true` on the imported OggVorbis stream of `bgm_menu` and `bgm_match` (the length is an exact whole number of bars, so `loop_offset = 0` is correct). `sfx/crowd_loop.wav` is a loopable ambience: in the WAV import settings set Loop Mode = Forward (begin 0, end = last sample).

## Regenerating

`python tools/gen_audio.py [sfx|music|all]` - requires numpy, scipy and `ffmpeg` with libvorbis on PATH (music only). Temporary music wavs are written to the system temp dir and deleted afterwards.

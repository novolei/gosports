#!/usr/bin/env python
"""Summarise the hit-timing telemetry the game keeps in the player's profile (lifetime + per timing-window setting).

    python tools/timing_report.py [path/to/profile.json]

Default path: %APPDATA%/Godot/app_userdata/GoSports/profile.json (the Windows desktop save).  Numbers come from the near-team human's
non-serve touches (MatchDirector.stats["timing"] -> Profile.finish_match).  "early"/"late" split the non-perfect touches by whether
the ball was still closing in on the ideal contact point when the button was pressed.  Use it to tune Game.TIMING_WINDOWS.
"""
import json
import os
import sys

NAMES = {"0": "relaxed (x1.4)", "1": "standard (x1.2)", "2": "precise (x1.0)"}


def line(label, d):
    n = sum(int(d.get(k, 0)) for k in ("perfect", "good", "ok"))
    if n == 0:
        return f"  {label:<18} no data"
    p, g, o = (int(d.get(k, 0)) for k in ("perfect", "good", "ok"))
    e, l = int(d.get("early", 0)), int(d.get("late", 0))
    miss = max(e + l, 1)
    return (f"  {label:<18} {n:5d} touches   perfect {100 * p / n:4.1f}%  good {100 * g / n:4.1f}%  ok {100 * o / n:4.1f}%"
            f"   of the non-perfect: early {100 * e / miss:4.1f}% / late {100 * l / miss:4.1f}%")


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "GoSports", "profile.json")
    if not os.path.exists(path):
        raise SystemExit(f"no profile at {path}")
    st = json.load(open(path, encoding="utf-8")).get("stats", {})
    print(f"profile: {path}")
    print(f"matches {st.get('matches', 0)}, wins {st.get('wins', 0)}, power spikes {st.get('power_spikes', 0)}, net smashes {st.get('smashes', 0)}")
    life = {k: st.get("t_" + k, 0) for k in ("perfect", "good", "ok", "early", "late")}
    print(line("lifetime", life))
    for k, d in sorted((st.get("timing_by_window") or {}).items()):
        print(line(NAMES.get(k, "window " + k), d))


if __name__ == "__main__":
    main()

"""The actual edit of the GoSports promo: which footage, when, with which overlays.  Times are seconds on the final timeline;
`S` = narration start of every line (timeline.py), `D` = narration durations."""
from __future__ import annotations

import gfx
import cards
import cards2
import nle
from nle import FadeBlack, Flash, LayerItem, Procedural, Shot

W, H = gfx.W, gfx.H


def assemble(ed, S, SEC, D):
    cold_open(ed, S, SEC)
    logo(ed, S, SEC)
    intro_vo(ed, S, D)
    gameplay(ed, S, D)
    gag(ed, S, D)
    celebrate(ed, S, D)
    modes(ed, S, D)
    story(ed, S, D, SEC)
    series(ed, S, D)
    outro(ed, S, D, SEC)


# ------------------------------------------------------------------ 0:00  cold open + logo
def cold_open(ed, S, SEC):
    from film_shots import COLD_OPEN
    t = 0.0
    for name, src_in, dur, kw in COLD_OPEN:
        ed.shot(name, src_in, dur, t, audio_db=-9.0, **kw)
        if t > 0:
            ed.add_sfx("whoosh", t - 0.08, -16.0)
        t += dur
    # the last hit lands exactly on the logo
    ed.tl.add(Flash(SEC["logo"][0] - 0.02, 0.35, peak=0.95))


def logo(ed, S, SEC):
    a, b = SEC["logo"]
    ed.proc(cards.logo_card, a, b, z=8)
    ed.add_sfx("levelup", a, -9.0)
    ed.add_sfx("crowd_cheer", a, -10.0)


def intro_vo(ed, S, D):
    from film_shots import INTRO_VO
    a = S["n02"] - 0.25
    b = S["n02"] + D["n02"] + 0.35
    t = a
    for name, src_in, dur, kw in INTRO_VO:
        ed.shot(name, src_in, dur, t, audio_db=-14.0, **kw)
        t += dur
    # who built it: a violet "Claude Sonnet 5.5" plate
    ed.chip(("Claude Sonnet 5.5  协作开发", "Built with Claude Sonnet 5.5"), "one person  +  one AI collaborator", None, S["n02"] + 3.6, 3.2, color=(122, 92, 255), pos=(60, 800))
    ed.tl.add(Flash(a, 0.3, peak=0.8))


# ------------------------------------------------------------------ gameplay explanation
def gameplay(ed, S, D):
    from film_shots import PLAY
    PLAY(ed, S, D)


def gag(ed, S, D):
    from film_shots import GAG
    GAG(ed, S, D)


def celebrate(ed, S, D):
    from film_shots import CELEBRATE
    CELEBRATE(ed, S, D)


def modes(ed, S, D):
    from film_shots import MODES
    MODES(ed, S, D)


# ------------------------------------------------------------------ how it was made
def story(ed, S, D, SEC):
    st = S
    # --- n10: fourteen rounds
    ed.proc(cards2.rounds_scene(), st["n10"] - 0.4, st["n11"] - 0.1, z=8)
    ed.add_sfx("ui_confirm", st["n10"] + 0.2, -12.0)

    # --- n11: a plain-words request -> result (picture in picture)
    a, b = st["n11"] - 0.1, st["n12"] - 0.2
    quote = ("If a player makes a mistake, their partner should have a chance to get angry, and sometimes even throw a sardine at the player."
             if cards.LANG == "en" else "如果玩家失误，队友也有一定概率生气，甚至有时候也会向玩家投掷沙丁鱼")
    ed.proc(cards2.chat_scene(quote,
                              ["读懂需求，设计「队友内讧」", "写代码：怒气标记、投掷、挥拳", "运行游戏，录下画面自检"],
                              "第 13 轮", "", "我的原话"), a, b, z=8)
    pip_t = a + 4.6
    ed.shot("g_sardine_ours", 1.6, b - pip_t, pip_t, audio_db=-12.0, rect=(1060, 500, 770, 433), radius=34, fade_in=0.3, z=9)
    ed.tl.add(LayerItem(cards.feature_chip("In the game" if cards.LANG == "en" else "实现效果", "what it looks like", None, gfx.PINK, en_title=cards.LANG == "en"), pip_t, b, pos=(1060, 470), anchor=(0.0, 0.5), z=10,
                        anim_in=nle.slide_in("left", 120, 0.4)))

    # --- n12: write -> run -> look -> fix, then a screenshot sheet the model checks itself
    a = st["n12"] - 0.2
    ed.proc(cards2.loop_scene(), a, a + 4.1, z=8)
    a2 = a + 4.1
    ed.proc(cards2.selfcheck_scene(str(cards.ROOT / "tmp_shots" / "cur" / "sheet_fin_punch2.png"),
                                   [("运行游戏，录一串画面", 0.8), ("自己看图：动作对不对？", 2.0), ("发现问题 → 修 → 再验证", 3.2)]),
            a2, st["n13"] - 0.1, z=8)

    # --- n13: the closing ritual of every round (real output lines)
    tf = cards2.terminal_scene(str(cards.ROOT / "tmp_shots" / "cur" / "phone_enc.png"))
    ed.proc(tf, st["n13"] - 0.1, st["n14"] - 0.15, z=8)
    ed.add_sfx("ui_confirm", st["n13"] + 8.4, -9.0)

    # --- n14: the numbers
    a = st["n14"] - 0.15
    ed.proc(cards2.stats_scene([
        {"value": 21, "label": "小时", "en": "hours, first message to now", "color": gfx.TEAL, "suffix": "", "at": 0.45},
        {"value": 25836, "label": "行代码", "en": "lines of code", "color": gfx.PINK, "suffix": "+", "at": 1.8},
        {"value": 33, "label": "节设计文档", "en": "design-doc sections", "color": gfx.YELLOW, "suffix": "", "at": 4.0},
        {"value": 2600, "label": "次工具调用", "en": "tool calls", "color": gfx.BLUE, "suffix": "+", "at": 5.4}]), a, st["n15"] - 0.15, z=8)
    for i, dt in enumerate((0.5, 1.85, 4.05, 5.45)):
        ed.add_sfx("xp_tick", a + dt, -8.0)

    # --- n15: everything is code
    a = st["n15"] - 0.15
    ed.proc(cards2.codegen_scene([3.7, 4.4, 5.1, 5.8, 6.5]), a, st["n16"] - 0.2, z=8)
    ed.shot("g_punch_ours", 3.0, 6.0, a + 1.0, audio_db=None, rect=(1130, 220, 720, 405), radius=30, fade_in=0.3, z=9)

    # --- n16: table tennis is already being built in parallel
    ed.proc(cards2.lanes_scene(), st["n16"] - 0.2, st["n17"] - 0.3, z=8)
    ed.add_sfx("levelup", st["n16"] + 8.2, -14.0)


# ------------------------------------------------------------------ the series
def series(ed, S, D):
    a = S["n17"] - 0.3
    t = lambda x: x - a
    ed.proc(cards2.series_scene((t(S["n17"] + 0.4), t(S["n18"] + 0.15), t(S["n18"] + 1.45), t(S["n18"] + 2.35))), a, S["n20"] - 0.35, z=8)
    for x in (S["n17"] + 0.4, S["n18"] + 0.15, S["n18"] + 1.45, S["n18"] + 2.35):
        ed.add_sfx("ui_confirm", x, -8.0)


def outro(ed, S, D, SEC):
    a = S["n20"] - 0.4
    b = ed_total(SEC)
    ed.proc(lambda c, t, d: cards.end_card(c, t, d, t_cta=S["n21"] - a + 0.2), a, b, z=8)
    ed.add_sfx("levelup", a + 0.3, -10.0)
    ed.tl.add(FadeBlack(b - 0.8, 0.8, "out"))
    ed.tl.add(FadeBlack(0.0, 0.25, "in"))


def ed_total(SEC):
    return SEC["outro"][1] + 0.4

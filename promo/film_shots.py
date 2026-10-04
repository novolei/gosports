"""Shot lists of the GoSports promo: which footage plays where.  `S`/`D` = narration start / duration per line (timeline.py).
Source times are seconds inside the recordings in promo_work/rec (see promo/events.py + promo/build_video.py shotsheet to proof-read)."""
import gfx
import cards
import nle
from nle import Flash

HI = dict(res=2560)                        # read the 1440p source at full size so punch-ins stay sharp


def Z(z0=1.0, z1=1.0, c=(0.5, 0.5), c2=None, **kw):
    d = dict(zoom=(z0, z1), center=c, center_to=c2 or c, **HI)
    d.update(kw)
    return d


def cut(ed, start, shots, audio_db=-12.0):
    """lay shots one after the other from `start`; returns the end time"""
    t = start
    for name, src_in, dur, kw in shots:
        kw = dict(kw)
        ed.shot(name, src_in, dur, t, audio_db=kw.pop("audio_db", audio_db), **kw)
        t += dur
    return t


# ================================================================== 0:00  cold open (12 beats of 0.5 s, then the logo)
COLD_OPEN = [
    ("m3_sunset", 19.4, 0.5, Z(1.25, 1.35, (0.5, 0.78))),        # spike
    ("g_fish", 5.7, 0.5, Z(1.3, 1.4, (0.55, 0.8))),               # the umpire's sardine, the "!" pops
    ("ai_dawn", 13.8, 0.5, Z(1.15, 1.25, (0.5, 0.45))),           # BLOCK!
    ("g_punch_ours", 3.3, 0.5, Z(1.3, 1.4, (0.45, 0.8))),         # POW!
    ("m1_day", 56.7, 0.5, Z(1.15, 1.25, (0.5, 0.55))),            # KILL BLOCK
    ("g_sardine_ours", 3.9, 0.5, Z(1.3, 1.4, (0.5, 0.8))),        # sardine in the face
    ("m3_sunset", 51.8, 0.5, Z(1.1, 1.2, (0.5, 0.7))),            # fever time
    ("ai_dawn", 3.7, 0.5, Z(1.2, 1.3, (0.5, 0.6))),               # jump serve
    ("g_punch_ours", 4.3, 0.5, Z(1.3, 1.4, (0.45, 0.8))),         # dizzy stars
    ("m1_day", 120.8, 0.5, Z(1.15, 1.25, (0.5, 0.6))),            # power spike
    ("ai_dawn", 28.0, 0.5, Z(1.3, 1.4, (0.5, 0.75))),             # a knock-down
    ("m1_day", 112.6, 0.5, Z(1.1, 1.2, (0.5, 0.65))),
]

INTRO_VO = [
    ("m1_day", 0.3, 4.1, Z(1.0, 1.05, (0.5, 0.5))),               # the team-intro orbit
    ("m3_sunset", 2.2, 3.7, Z(1.1, 1.22, (0.5, 0.72))),           # serve in the sunset venue
]


# ================================================================== the gameplay explanation
def PLAY(ed, S, D):
    # --- n03: serve (aim, toss, hit at the peak)
    t = cut(ed, S["n03"] - 0.2, [
        ("m3_sunset", 2.5, 3.9, Z(1.0, 1.2, (0.5, 0.7), (0.5, 0.78))),
        ("ai_dawn", 3.3, 1.8, Z(1.1, 1.22, (0.5, 0.62))),
        ("g_aim", 9.9, D["n03"] + 0.3 - 5.7, Z(1.0, 1.15, (0.5, 0.7))),
    ])
    ed.chip(("发球", "SERVE"), "toss, then hit at the peak", "act_serve.png", S["n03"] + 0.2, 3.3)
    ed.chip(("落点 + 时机", "AIM + TIMING"), "hold a direction · shrinking timing ring", "act_jump.png", S["n03"] + 3.7, 3.3, color=gfx.BLUE)

    # --- n04: bump, set, spike; perfect timing; fever
    cut(ed, S["n04"] - 0.2, [
        ("m1_day", 90.0, 2.9, Z(1.0, 1.12, (0.5, 0.65))),
        ("m1_day", 112.2, 2.7, Z(1.0, 1.12, (0.5, 0.65))),
        ("m1_day", 119.9, D["n04"] + 0.3 - 5.6, Z(1.05, 1.18, (0.5, 0.6))),
    ])
    ed.chip(("接 · 传 · 扣", "BUMP · SET · SPIKE"), "three touches, one flow", "act_spike.png", S["n04"] + 0.2, 3.0)
    ed.chip(("完美时机 + 热血", "PERFECT + FEVER"), "combos set the court on fire", "emb_flame.png", S["n04"] + 3.4, 4.2, color=gfx.ORANGE)

    # --- n05: block and dive
    cut(ed, S["n05"] - 0.2, [
        ("ai_dawn", 13.2, 2.0, Z(1.0, 1.15, (0.5, 0.5))),
        ("m1_day", 56.1, D["n05"] + 0.3 - 2.0, Z(1.0, 1.12, (0.5, 0.55))),
    ])
    ed.chip(("拦网", "BLOCK"), "jump at the net", "act_block.png", S["n05"] + 0.1, 1.9, color=gfx.PINK)
    ed.chip(("扑救", "DIVE"), "fly to save it", "act_dive.png", S["n05"] + 2.0, 2.2, color=gfx.BLUE)

    # --- n06: replay, hawk-eye, the press
    cut(ed, S["n06"] - 0.2, [
        ("m1_day", 124.6, 2.3, Z(1.0, 1.0)),
        ("g_hawk_out", 3.0, 2.2, Z(1.0, 1.0)),
        ("m2_night", 40.0, D["n06"] + 0.3 - 4.5, Z(1.0, 1.0)),
    ])
    ed.chip(("即时回放", "INSTANT REPLAY"), "slow motion from the side camera", "chevron.png", S["n06"] + 0.1, 2.1)
    ed.chip(("鹰眼判罚", "HAWK-EYE"), "close calls get a review", "act_set.png", S["n06"] + 2.3, 2.1, color=gfx.BLUE)
    ed.chip(("场边记者", "PRESS CREW"), "flashes during replays", "act_bump.png", S["n06"] + 4.4, 1.9, color=gfx.ORANGE)


# ================================================================== the gag chapter
def GAG(ed, S, D):
    # --- g01: a teaser, then the chapter card on the words "gag moments"
    t0 = S["g01"] - 0.1
    cut(ed, t0, [
        ("g_fish", 5.3, 1.1, Z(1.2, 1.3, (0.55, 0.8))),
        ("g_punch_ours", 2.9, 1.0, Z(1.25, 1.35, (0.45, 0.8))),
    ])
    ct = S["g01"] + (2.3 if cards.LANG == "zh" else 2.0)
    ed.proc(cards.gag_title_card, ct, S["g02"] + 0.05, z=60)
    ed.add_sfx("point_win", ct, -8.0)
    ed.add_sfx("whoosh", ct - 0.05, -10.0)

    # --- g02: the umpire warns, then throws: pencils, bananas, ducks, slippers, the sardine
    U = dict(zoom=(1.3, 1.45), center=(0.56, 0.6), center_to=(0.56, 0.58), **HI)
    t = cut(ed, S["g02"] - 0.2, [
        ("ref_whistle", 4.2, 1.3, U),
        ("ref_shake", 4.2, 1.4, U),
        ("ref_throw", 4.0, 1.7, U),
    ])
    t = cut(ed, t, [("g_fish", 4.9, S["g02"] + 4.6 - t, Z(1.0, 1.15, (0.5, 0.75)))])
    t = cut(ed, S["g02"] + 4.6, [
        ("g_prop_pencil", 4.15, 0.95, Z(1.35, 1.5, (0.5, 0.78))),
        ("g_prop_banana", 4.15, 0.95, Z(1.35, 1.5, (0.5, 0.78))),
        ("g_prop_duck", 4.15, 0.95, Z(1.35, 1.5, (0.5, 0.78))),
        ("g_prop_slipper", 4.15, 0.95, Z(1.35, 1.5, (0.5, 0.78))),
        ("g_prop_hammer", 4.15, 0.95, Z(1.35, 1.5, (0.5, 0.78))),
        ("g_fish", 5.3, 1.2, Z(1.3, 1.45, (0.55, 0.8))),
    ])
    ed.chip(("动物裁判", "THE ANIMAL UMPIRE"), "warns first ...", "chevron.png", S["g02"] + 0.2, 4.4, color=gfx.ORANGE)
    ed.chip(("道具", "WHAT HE THROWS"), "pencil · banana · duck · slipper · hammer · sardine", "chevron.png", S["g02"] + 5.0, 5.2, color=gfx.PINK)

    # --- g03: two warnings and the point is lost
    cut(ed, S["g03"] - 0.2, [("g_fish", 6.6, D["g03"] + 0.4, Z(1.0, 1.1, (0.5, 0.7)))])
    ed.chip(("两次警告 = 判负", "TWO WARNINGS = POINT LOST"), "serve timeout", "act_serve.png", S["g03"] + 0.1, D["g03"] - 0.2, color=gfx.PINK)

    # --- g04: an angry partner: sardine, or a punch
    cut(ed, S["g04"] - 0.2, [
        ("g_sardine_ours", 2.4, 2.8, Z(1.1, 1.3, (0.5, 0.72))),
        ("g_punch_ours", 1.9, 2.0, Z(1.15, 1.35, (0.4, 0.8))),
        ("g_punch_slow", 6.8, D["g04"] + 0.4 - 4.8, Z(1.2, 1.4, (0.45, 0.8))),
    ])
    ed.chip(("队友生气了", "ANGRY PARTNER"), "an anger vein ... then a sardine", "chevron.png", S["g04"] + 0.1, 3.4, color=gfx.PINK)
    ed.chip(("甚至一拳", "OR A PUNCH"), "slow-mo replay", "emb_flame.png", S["g04"] + 3.6, 3.4, color=gfx.ORANGE)

    # --- g05: a falling-out after losing the match
    lead = 2.2
    cut(ed, S["g05"] - 0.2, [("g_final_punch", 1.5, lead, Z(1.1, 1.3, (0.4, 0.78))),
                             ("g_final_punch", 10.4, D["g05"] + 0.4 - lead, Z(1.0, 1.0))])
    ed.chip(("输了比赛，内讧", "MATCH LOST: A FALLING-OUT"), "", "chevron.png", S["g05"] + 0.1, D["g05"] - 0.2, color=gfx.BLUE)


def CELEBRATE(ed, S, D):
    rest = D["n08"] + 0.4 - (2.0 + 1.6 + 1.4)
    cut(ed, S["n08"] - 0.2, [
        ("g_highfive", 1.9, 2.0, Z(1.15, 1.35, (0.3, 0.68))),
        ("g_dance_a", 2.6, 1.6, Z(1.25, 1.4, (0.5, 0.8))),
        ("g_dance_b", 2.7, 1.4, Z(1.25, 1.4, (0.5, 0.8))),
        ("g_sardine_opp", 2.7, rest, Z(1.5, 1.8, (0.66, 0.5))),
    ])
    ed.chip(("击掌 · 跳舞", "HIGH-FIVES · DANCES"), "random, for both teams", "emb_trophy.png", S["n08"] + 0.1, 3.4)
    ed.chip(("随时跳过", "SKIP ANY TIME"), "any key / tap", "chevron.png", S["n08"] + 3.8, 3.0, color=gfx.BLUE)


def MODES(ed, S, D):
    total = D["n09"] + 0.8
    d = [0.25 * total, 0.2 * total, 0.33 * total]
    t0 = S["n09"] - 0.2
    cut(ed, t0, [
        ("menu_mode", 1.2, d[0], dict()),
        ("menu_col3", 1.5, d[1], dict()),
        ("menu_main_en" if cards.LANG == "en" else "menu_main", 1.0, d[2], dict()),
        ("res_win", 2.0, total - sum(d), dict()),
    ], audio_db=-16.0)
    pip_t = t0 + d[0] + d[1]
    ed.shot("touch_match", 6.0, d[2], pip_t, audio_db=None, rect=(1190, 540, 680, 306), radius=34, fade_in=0.3, z=40)
    ed.chip(("单人 · 合作 · 对战 · 锦标赛", "SOLO · CO-OP · VERSUS · TOURNAMENT"), "plus training and rally challenge", "act_set.png", S["n09"] + 0.1, d[0] + d[1] - 0.2)
    ed.chip(("键盘 · 手柄 · 手机", "KEYBOARD · GAMEPAD · PHONE"), "Windows and Android, Chinese and English", "act_jump.png", pip_t + 0.1, d[2] + 0.4, color=gfx.BLUE)

import sys, numpy as np, cv2
sys.path.insert(0, ".")
import gfx, cards, cards2
out = "../promo_work/cards_test/"
c = np.zeros((1080, 1920, 3), np.uint8)
def snap(name, fn, ts, dur=10.0):
    for t in ts:
        c[:] = 0
        fn(c, t, dur)
        cv2.imwrite(f"{out}{name}_{t:.1f}.png", c)
snap("chat", cards2.chat_scene("如果玩家失误，队友也有一定概率生气，甚至有时候也会向玩家投掷沙丁鱼", ["读懂需求，设计「队友内讧」", "写代码：怒气标记 · 投掷 · 挥拳", "运行游戏，截图自检 ✓"], "第 13 轮", "→ 实现效果", "我的原话"), [4.5, 8.5])
snap("check", cards2.selfcheck_scene("../tmp_shots/cur/sheet_fin_punch2.png", [("运行游戏、录下一连串画面", 1.0), ("自己看图：动作对不对？", 2.5), ("发现问题 → 修 → 再验证", 4.0)]), [5.0], 8.0)
tf = cards2.terminal_scene("../tmp_shots/cur/phone_enc.png")
snap("term", tf, [6.0, 16.0], 18.0)
snap("stats", cards2.stats_scene([
  {"value": 21, "label": "小时", "en": "hours, first message to now", "color": gfx.TEAL, "suffix": ""},
  {"value": 25836, "label": "行代码", "en": "lines of code", "color": gfx.PINK, "suffix": "+"},
  {"value": 33, "label": "节设计文档", "en": "design-doc sections", "color": gfx.YELLOW, "suffix": ""},
  {"value": 2600, "label": "次工具调用", "en": "tool calls", "color": gfx.BLUE, "suffix": "+"}]), [4.0], 8.0)
snap("rounds", cards2.rounds_scene(), [7.0], 9.0)
snap("loop", cards2.loop_scene(), [5.0], 8.0)
snap("lanes", cards2.lanes_scene(), [4.0], 8.0)
snap("series", cards2.series_scene(), [4.0], 8.0)
print("ok")

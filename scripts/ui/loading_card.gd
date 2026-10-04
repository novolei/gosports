class_name LoadingCard
extends Control
## Dark slate "loading" card with diagonal streaks, a tip title and one line of advice with highlighted words
## (reference: the loading screens of Switch Sports). Shown over the white fade while a match is being built.

const TIPS := [
	["发球", "先按 [p]击球键[/p] 把球抛起，球到 [t]最高点[/t] 时再按一次击球。先按跳跃键还能 [p]跳发球[/p]!"],
	["时机", "球上的圆圈缩到 [t]最小[/t] 的那一刻按键，就是 [p]Nice![/p]：球更快、更准。"],
	["垫传扣", "每队最多触球 [p]3 次[/p]：垫球 → 传球 → 扣球，同一个人不能连续触球。"],
	["拦网", "对方把球传高时，在网前 [p]起跳[/p]，手臂伸过网就能把球 [t]拦回去[/t]。"],
	["热血时刻", "连续的 Nice! 会攒满 [p]热血条[/p]：判定变宽，扣球更有力，球还会拖着火焰!"],
	["强力扣球", "垫、传、扣 [p]三次全是 Nice![/p]，就能打出几乎拦不住的 [t]强力扣球[/t]。"],
	["扑救", "够不到的低球，按 [p]扑救键[/p] 飞身去接；落点圈会告诉你球落在哪里。"],
	["吊球", "扣球时把瞄准点放在 [p]靠近球网[/p] 的位置，球就会变成轻轻的 [t]吊球[/t]。"],
	["大力扣杀", "在 [p]网前[/p] 起跳扣球，时机越准越有机会触发 [t]大力扣杀[/t]：球又快又陡，很难拦!"],
	["快速扣球", "在队友传球之前就 [p]起跳[/p]，传球会变成又低又快的 [t]QUICK[/t] 球。"],
	["别撞人", "跑动时撞到队友会被弹开，撞得狠还会 [p]摔倒[/p]。叫位置、留空间。"],
	["瞄准", "鼠标指向对方场地的 [t]落点[/t]，球就打向那里；手柄用 [p]右摇杆[/p]。"],
	["自动跑位", "开启 [p]自动跑位辅助[/p] 后，球来时角色会自己跑向落点，你只管 [t]击球时机[/t]。"],
]

var _rich: RichTextLabel
var _title: Label
var _t := 0.0
var _streaks: Array = []


func build() -> LoadingCard:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 26:
		_streaks.append(Vector4(rng.randf_range(0.0, 1.0), rng.randf_range(0.0, 1.0), rng.randf_range(160.0, 520.0), rng.randf_range(0.06, 0.15)))
	var tip: Array = TIPS[randi() % TIPS.size()]
	_title = UIKit.label("小技巧 · %s" % tip[0], 50, Color("e8f26a"), 0, Color.WHITE)
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.position = Vector2(-500, -120)
	_title.size = Vector2(1000, 70)
	add_child(_title)
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.85)
	rule.set_anchors_preset(Control.PRESET_CENTER)
	rule.position = Vector2(-560, -40)
	rule.size = Vector2(1120, 3)
	add_child(rule)
	_rich = RichTextLabel.new()
	_rich.bbcode_enabled = true
	_rich.fit_content = false
	_rich.scroll_active = false
	_rich.set_anchors_preset(Control.PRESET_CENTER)
	_rich.position = Vector2(-560, -10)
	_rich.size = Vector2(1120, 140)
	_rich.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rich.add_theme_font_size_override("normal_font_size", 34)
	_rich.add_theme_color_override("default_color", Color(0.95, 0.97, 1.0))
	_rich.text = Loc.t(String(tip[1])).replace("[p]", "[color=#ff5db0]").replace("[/p]", "[/color]").replace("[t]", "[color=#35e0c0]").replace("[/t]", "[/color]")
	add_child(_rich)
	var dots := UIKit.label("正在准备比赛…", 24, Color(1, 1, 1, 0.55))
	dots.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	dots.position = Vector2(-380, -70)
	dots.size = Vector2(340, 40)
	add_child(dots)
	return self


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.17, 0.2, 0.22))
	for st in _streaks:
		var x := fposmod(float(st.x) * s.x - _t * 40.0 * (0.4 + float(st.w) * 8.0), s.x + 600.0) - 300.0
		var y := float(st.y) * s.y
		var a := Vector2(x, y)
		var b := a + Vector2(float(st.z), -float(st.z) * 0.32)
		draw_line(a, b, Color(1, 1, 1, float(st.w)), 8.0, true)

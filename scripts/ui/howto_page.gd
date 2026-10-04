class_name HowToPage
extends Control
## "操作说明" (How to play): a sidebar of topic pills on the left and the details on a frosted panel on the right.
## Controls are shown as keycap rows ([action tag] [key][key]...), rules and tips as colour-chip rows - scannable at a glance,
## no walls of text. Everything is built from small data tables below, translated through tr().

signal back_pressed

const INK := Color(0.1, 0.2, 0.3)
const TAG := Color(0.16, 0.56, 0.6)
const TOPICS := [
	["键盘 + 鼠标", "WASD · 鼠标 · 双人同屏", "keys"],
	["手柄", "摇杆 · 按键 · 瞄准", "pad"],
	["触屏", "浮动摇杆 · 动作按钮", "touch"],
	["规则 & 技巧", "快速扣球 · 拦网 · 吊球", "bulb"],
	["节奏 & 成长", "Nice! · 热血 · 升级解锁", "star"],
]

var _entries: Array[MenuEntry] = []
var _panel: Control
var _body: Control
var _topic := 0


func build() -> HowToPage:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var hd := GW.header(tr("操作说明"), "bulb", 880.0)
	hd.position = Vector2(70, 34)
	add_child(hd)
	var y := 190.0
	for i in TOPICS.size():
		var t: Array = TOPICS[i]
		var en := MenuEntry.new().build(tr(String(t[0])), tr(String(t[1])), String(t[2]), Vector2(580, 104), "pale", "", 2.0, 38)
		en.position = Vector2(100, y)
		var ti := i
		en.chosen.connect(func(): show_topic(ti))
		en.focus_entered.connect(func(): show_topic(ti))
		add_child(en)
		_entries.append(en)
		y += 122.0
	_panel = GW.frost(Vector2(1000, 730), 40.0)
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-1000.0 - 60.0, 150)
	add_child(_panel)
	var back := UIKit.button(tr("返回"), Vector2(280, 76), UIKit.PINK, 36)
	back.position = Vector2(70, 920)
	back.pressed.connect(func(): back_pressed.emit())
	add_child(back)
	show_topic(int(Game.main.dev["howtab"]) if Game.main != null and Game.main.dev.has("howtab") else 0)
	return self


func focus_first() -> void:
	if not _entries.is_empty():
		_entries[_topic].call_deferred("grab_focus")


func show_topic(i: int) -> void:
	_topic = i
	for k in _entries.size():
		_entries[k].mark(k == i)
	if _body != null:
		_body.queue_free()
	_body = Control.new()
	_body.position = Vector2(44, 32)
	_body.size = Vector2(912, 670)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_body)
	match i:
		0: _keyboard()
		1: _gamepad()
		2: _touch()
		3: _rules()
		4: _growth()
	_body.modulate.a = 0.0
	_body.position.y += 10.0
	var tw := _body.create_tween().set_parallel(true)
	tw.tween_property(_body, "modulate:a", 1.0, 0.16)
	tw.tween_property(_body, "position:y", 32.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------ building blocks
func _col(parent: Control, pos: Vector2, w: float, sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = pos
	v.size = Vector2(w, 10)
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(v)
	return v


## coloured heading capsule ("Player 1", ...)
func _head(v: VBoxContainer, text: String, col: Color, w := 300.0) -> void:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(w, 50)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(GW.pill_bg(Vector2(w, 46), 23.0, col))
	var l := UIKit.label(text, 28, Color.WHITE, 6, col.darkened(0.45))
	l.position = Vector2(0, -1)
	l.size = Vector2(w, 46)
	holder.add_child(l)
	v.add_child(holder)


func _keycap(text: String, fill := Color(1, 1, 1, 0.97), ink := INK, size := 26) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.style_box(fill, 13, 3, Color(0.6, 0.75, 0.8), 4, 14))
	p.custom_minimum_size = Vector2(50, 48)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(text, size, ink)
	l.custom_minimum_size = Vector2(0, 40)
	p.add_child(l)
	return p


## round coloured gamepad button (A / B / X / Y)
func _padbtn(letter: String, col: Color) -> Control:
	var d := Panel.new()
	d.custom_minimum_size = Vector2(48, 48)
	d.add_theme_stylebox_override("panel", UIKit.style_box(col, 24, 3, Color.WHITE, 4))
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(letter, 28, Color.WHITE, 5, col.darkened(0.5))
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.add_child(l)
	return d


func _sep(text: String) -> Control:
	var l := UIKit.label(text, 22, Color(0.35, 0.5, 0.58))
	l.custom_minimum_size = Vector2(20, 48)
	return l


## [action tag] [cap] / [cap] ... ; `keys` items: String (keycap), Control (ready made), or "|" for the "or" separator
func _row(v: VBoxContainer, label: String, keys: Array, tag_w := 124.0) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := Control.new()
	tag.custom_minimum_size = Vector2(tag_w, 48)
	tag.add_child(GW.pill_bg(Vector2(tag_w - 8.0, 44), 22.0, TAG))
	tag.get_child(0).position += Vector2(0, 2)
	var tl := UIKit.label(tr(label), 26, Color.WHITE, 0)
	tl.position = Vector2(0, 2)
	tl.size = Vector2(tag_w - 8.0, 44)
	tag.add_child(tl)
	h.add_child(tag)
	for k in keys:
		if k is Control:
			h.add_child(k)
		elif String(k) == "|":
			h.add_child(_sep("/"))
		else:
			h.add_child(_keycap(tr(String(k))))
	v.add_child(h)


## colour chip + wrapped description
func _tip(v: VBoxContainer, chip: String, col: Color, text: String, w := 912.0, chip_w := 190.0) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := Control.new()
	c.custom_minimum_size = Vector2(chip_w, 52)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.add_child(GW.pill_bg(Vector2(chip_w - 6.0, 48), 24.0, col))
	var cl := UIKit.label(tr(chip), 26, Color.WHITE, 6, col.darkened(0.5))
	cl.position = Vector2(0, 0)
	cl.size = Vector2(chip_w - 6.0, 48)
	cl.clip_text = true
	c.add_child(cl)
	h.add_child(c)
	var l := Label.new()
	l.text = tr(text)
	l.add_theme_font_size_override("font_size", 25)
	l.add_theme_color_override("font_color", INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(w - chip_w - 20.0, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	v.add_child(h)


func _note(v: VBoxContainer, text: String, w := 912.0) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.1, 0.4, 0.46, 0.14), 20, 0, Color.WHITE, 0, 22))
	p.custom_minimum_size = Vector2(w, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = tr(text)
	l.add_theme_font_size_override("font_size", 25)
	l.add_theme_color_override("font_color", INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(w - 50.0, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	v.add_child(p)


# ------------------------------------------------------------------ topics
func _keyboard() -> void:
	var left := _col(_body, Vector2(0, 0), 440)
	_head(left, tr("玩家1"), UIKit.BLUE)
	_row(left, "移动", ["W", "A", "S", "D"])
	_row(left, "击球", ["J", "|", "鼠标左键"])
	_row(left, "跳跃", ["K", "|", "空格", "|", "鼠标右键"])
	_row(left, "扑救", ["L", "|", "Shift"])
	_row(left, "瞄准", ["鼠标", "|", "← ↑ ↓ →"])
	_row(left, "暂停键", ["Esc"])
	var right := _col(_body, Vector2(492, 0), 420)
	_head(right, tr("玩家2（同一键盘）"), UIKit.PINK, 400.0)
	_row(right, "移动", ["← ↑ ↓ →"])
	_row(right, "击球", ["小键盘1", "|", ","])
	_row(right, "跳跃", ["小键盘2", "|", "."])
	_row(right, "扑救", ["小键盘3", "|", "/"])
	_row(right, "瞄准", ["小键盘 8 4 5 6"])
	var low := _col(_body, Vector2(0, 462), 912, 14)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 14)
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in [["球低 → 垫球", UIKit.BLUE], ["球在头顶 → 传球", UIKit.TEAL], ["起跳后 → 扣球", UIKit.PINK]]:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(290, 56)
		var col: Color = c[1]
		holder.add_child(GW.pill_bg(Vector2(284, 50), 25.0, col))
		var l := UIKit.label(tr(String(c[0])), 26, Color.WHITE, 6, col.darkened(0.5))
		l.size = Vector2(284, 50)
		l.clip_text = true
		holder.add_child(l)
		ch.add_child(holder)
	low.add_child(_head_label("击球键会看情况变化"))
	low.add_child(ch)
	_note(low, "发球：第一次按下抛球，第二次击球。球很高时直接按击球键，角色会自动起跳去扣球。")
	_note(low, "瞄准：击球的瞬间按住方向键 —— 左 / 右决定落在哪一侧，向前打得深，向后打得短。地面上的圆圈是落点区域：绿色安全，橙色靠近边线，红色会出界。")


func _head_label(text: String) -> Control:
	var l := UIKit.label(tr(text), 28, INK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(600, 36)
	return l


func _gamepad() -> void:
	var v := _col(_body, Vector2(0, 0), 912, 12)
	_head(v, tr("手柄（1 号手柄 = 玩家1，2 号手柄 = 玩家2）"), UIKit.TEAL, 760.0)
	_row(v, "移动", ["左摇杆", "|", "十字键"], 150.0)
	_row(v, "击球", [_padbtn("A", Color("3fbf5f")), "|", "RB", "|", "RT"], 150.0)
	_row(v, "跳跃", [_padbtn("B", Color("e8514f")), "|", "LB"], 150.0)
	_row(v, "扑救", [_padbtn("X", Color("3a8bff")), "|", "LT"], 150.0)
	_row(v, "瞄准", ["右摇杆"], 150.0)
	_row(v, "暂停键", ["Start"], 150.0)
	var low := _col(_body, Vector2(0, 462), 912, 14)
	_note(low, "推右摇杆瞄准：推向哪里，球就打向对方场地的哪里；松开 = 智能落点。也可以击球时按住左摇杆的方向。")
	_note(low, "地面上的发光圈是你的击球范围：球进入圈内并变亮时按击球键就是 PERFECT。")


func _touch() -> void:
	var v := _col(_body, Vector2(0, 0), 912, 12)
	var rows := [
		["移动", "左半屏任意位置按住并拖动（浮动摇杆）", ""],
		["击球", "右下角的大按钮；它会随情境变成垫 / 传 / 扣 / 发", "res://assets/ui/act_bump.png"],
		["跳跃", "起跳与拦网", "res://assets/ui/act_jump.png"],
		["扑救", "够不到的低球", "res://assets/ui/act_dive.png"],
		["落点", "点击对方半场设置落点标记（不点 = 智能落点）", ""],
		["自动跑位", "设置里开启后，不碰摇杆时角色会自己跑向落点", ""],
		["左手模式", "设置里可以把按键镜像到左边", ""],
	]
	for r in rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Control.new()
		ic.custom_minimum_size = Vector2(70, 70)
		if String(r[2]) != "" and ResourceLoader.exists(String(r[2])):
			var disc := Panel.new()
			disc.size = Vector2(66, 66)
			disc.position = Vector2(2, 2)
			disc.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.2, 0.55, 0.6, 0.95), 33, 3, Color.WHITE, 4))
			disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ic.add_child(disc)
			var tx := TextureRect.new()
			tx.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tx.texture = load(String(r[2]))
			tx.size = Vector2(46, 46)
			tx.position = Vector2(12, 12)
			tx.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ic.add_child(tx)
		else:
			ic.add_child(GW.glyph("touch" if r[0] == "移动" else ("target" if r[0] == "落点" else "gear"), 62.0, Color(0.2, 0.55, 0.6, 0.95)))
		h.add_child(ic)
		var tag := Control.new()
		tag.custom_minimum_size = Vector2(170, 52)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag.add_child(GW.pill_bg(Vector2(164, 48), 24.0, TAG))
		var tl := UIKit.label(tr(String(r[0])), 26, Color.WHITE)
		tl.size = Vector2(164, 48)
		tag.add_child(tl)
		h.add_child(tag)
		var l := Label.new()
		l.text = tr(String(r[1]))
		l.add_theme_font_size_override("font_size", 25)
		l.add_theme_color_override("font_color", INK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(620, 0)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(l)
		v.add_child(h)


func _rules() -> void:
	var top := Control.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(top)
	var x := 0.0
	for b in [["2 v 2", "得分方发球", UIKit.BLUE], ["3 次触球", "垫 → 传 → 扣", UIKit.TEAL], ["7 / 11 / 15", "先到且领先 2 分", UIKit.PINK]]:
		var holder := Control.new()
		holder.position = Vector2(x, 0)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(holder)
		var col: Color = b[2]
		holder.add_child(GW.pill_bg(Vector2(290, 86), 30.0, col))
		var bl := UIKit.label(tr(String(b[0])), 40, Color.WHITE, 8, col.darkened(0.5))
		bl.position = Vector2(0, -2)
		bl.size = Vector2(290, 52)
		holder.add_child(bl)
		var sl := UIKit.label(tr(String(b[1])), 22, Color(1, 1, 1, 0.95))
		sl.position = Vector2(0, 46)
		sl.size = Vector2(290, 32)
		holder.add_child(sl)
		x += 311.0
	var v := _col(_body, Vector2(0, 118), 912, 14)
	_tip(v, "快速扣球", Color("e8514f"), "在队友传球之前就起跳：传球会变成低而快的 QUICK 球，直接送到你手上。")
	_tip(v, "拦网", Color("3a8bff"), "对方传出高球时在网前起跳，手臂过网把球拦回去（KILL BLOCK 直接得分）。")
	_tip(v, "扑救", Color("2fa86a"), "够不到的低球用扑救键；地面的落点圈会提示球要落在哪里。")
	_tip(v, "吊球", Color("e08a1e"), "扣球时把瞄准点放在靠近球网的位置，就变成轻轻吊过网。")
	_tip(v, "大力扣杀", Color("ff6a1f"), "在网前起跳、打出 Nice! 的扣球，有机会变成大力扣杀：时机越准、离网越近，越容易触发。")
	_tip(v, "跳发球", Color("8a5be0"), "抛球后先按跳跃，在空中击球：球速更快，但更难控制。")
	_tip(v, "小心碰撞", Color("d9418c"), "跑动中撞到别人会被弹开，撞得很狠还会摔倒、眼冒金星一会儿。")


func _growth() -> void:
	var v := _col(_body, Vector2(0, 0), 912, 12)
	_tip(v, "Nice!", Color("e8514f"), "球进入击球范围时会出现缩小的光圈：圈缩到最小时按击球键，球更快更准。")
	_tip(v, "热血时刻", Color("e08a1e"), "连续的 Nice! 攒满热血条：判定更宽、扣球更强、球会拖着火焰。")
	_tip(v, "强力扣球", Color("d9418c"), "垫、传、扣三次全是 Nice!，球色变粉红，几乎拦不住。")
	_tip(v, "角色特性", Color("2fa86a"), "每个角色都有独门特性：有的跑得快、有的拦网强，挑最适合你的。")
	_tip(v, "升级解锁", Color("3a8bff"), "比赛和练习都能获得经验，解锁球拖尾、比赛用球、球场主题，在「生涯」里装备。")
	_tip(v, "每日任务", Color("8a5be0"), "每天 3 个随机任务，连续登录提升经验加成，成就可收集 22 个。")
	_tip(v, "锦标赛", Color("c9a21a"), "三轮连战（小组赛 → 半决赛 → 决赛），夺冠有大量经验；练习场的回合挑战可拿铜 / 银 / 金牌。")

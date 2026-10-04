class_name CareerPage
extends Control
## Career hub (a menu page): profile / daily missions / records, the cosmetics collection (equip trail, ball,
## court theme) and the achievement list. Everything reads from Game.profile.

signal back_pressed

const KIND_TITLES := {"trail": "球拖尾", "ball": "比赛用球", "court": "球场主题"}
const GOLD := Color("ffc928")

var _tab := 0
var _body: Control
var _desc: Label
var _tabs: Array[Button] = []


# ------------------------------------------------------------------ small drawing helpers
class _Swatch:
	extends Control
	var kind := "trail"
	var item := {}
	var locked := false

	func _trail_col(t: float) -> Color:
		match String(item["id"]):
			"rainbow": return Color.from_hsv(fmod(t * 0.8, 1.0), 0.6, 1.0)
			"fire": return Color(1.0, 0.86, 0.25).lerp(Color(1.0, 0.25, 0.1), t)
			"ice": return Color(0.95, 1.0, 1.0).lerp(Color(0.4, 0.78, 1.0), t)
			"sakura": return Color(1.0, 0.68, 0.85).lerp(Color.WHITE, t)
			"speed": return Color(0.42, 0.98, 0.78).lerp(Color(1.0, 0.5, 0.7), t)
		return item["swatch"]

	func _draw() -> void:
		var k := 0.4 if locked else 1.0
		match kind:
			"trail":
				var n := 16
				var prev_top := Vector2.ZERO
				var prev_bot := Vector2.ZERO
				for i in n + 1:
					var t := float(i) / float(n)
					var x := 8.0 + t * (size.x - 40.0)
					var y := size.y * 0.5 + sin(t * 5.5) * size.y * 0.16
					var w := 2.0 + t * 15.0
					var top := Vector2(x, y - w)
					var bot := Vector2(x, y + w)
					if i > 0:
						var col := _trail_col(t)
						col.a = (0.35 + 0.65 * t) * k
						draw_colored_polygon(PackedVector2Array([prev_top, top, bot, prev_bot]), col)
					prev_top = top
					prev_bot = bot
				var head := Vector2(size.x - 28.0, size.y * 0.5 + sin(5.5) * size.y * 0.16)
				draw_circle(head + Vector2(0, 2), 19.0, Color(0, 0, 0, 0.12 * k))
				draw_circle(head, 18.0, Color(1, 1, 1, k))
				draw_arc(head + Vector2(-20, 0), 20.0, -0.7, 0.7, 10, Color(0.1, 0.3, 0.7, 0.8 * k), 2.5, true)
			"ball":
				var c := size * 0.5
				var r: float = minf(size.x, size.y) * 0.5 - 6.0
				var tint: Color = item["swatch"]
				tint.a = k
				draw_circle(c + Vector2(0, 4), r, Color(0, 0, 0, 0.14 * k))
				draw_circle(c, r, Color(1, 1, 1, k))
				draw_circle(c, r - 3.0, tint)
				var seam := Color(1, 1, 1, 0.8 * k)
				draw_arc(c + Vector2(-r * 1.15, 0), r * 1.15, -0.62, 0.62, 12, seam, 3.0, true)
				draw_arc(c + Vector2(r * 1.15, 0), r * 1.15, PI - 0.62, PI + 0.62, 12, seam, 3.0, true)
				draw_arc(c + Vector2(0, -r * 1.15), r * 1.15, PI * 0.5 - 0.62, PI * 0.5 + 0.62, 12, seam, 3.0, true)
				draw_circle(c + Vector2(-r * 0.35, -r * 0.4), r * 0.2, Color(1, 1, 1, 0.5 * k))
			"court":
				var th: Dictionary = Arena.THEMES.get(String(item["id"]), Arena.THEMES["day"])
				var pale := Color(0.82, 0.85, 0.92)
				var fade := 0.5 if locked else 0.0
				var sky_top: Color = (th["sky_top"] as Color).lerp(pale, fade)
				var sky_hor: Color = (th["sky_hor"] as Color).lerp(pale, fade)
				var h := size.y
				var top_h := h * 0.62
				for i in 8:
					var t := float(i) / 7.0
					draw_rect(Rect2(0, top_h * float(i) / 8.0, size.x, top_h / 8.0 + 1.0), sky_top.lerp(sky_hor, t))
				var floor_col := Color(0.93, 0.62, 0.55) * (Color(0.45, 0.45, 0.6) if item["id"] == "night" else Color.WHITE)
				draw_rect(Rect2(0, top_h, size.x, h - top_h), Color(floor_col.r, floor_col.g, floor_col.b, 1.0).lerp(pale, fade))
				draw_line(Vector2(0, top_h), Vector2(size.x, top_h), Color(1, 1, 1, 0.5 * k), 2.0)
				match String(item["id"]):
					"night":
						draw_circle(Vector2(size.x * 0.78, h * 0.2), 11.0, Color(1.0, 0.98, 0.85))
						for p in [Vector2(0.2, 0.15), Vector2(0.4, 0.3), Vector2(0.55, 0.12), Vector2(0.1, 0.4)]:
							draw_circle(Vector2(size.x * p.x, h * p.y), 2.0, Color(1, 1, 1, 0.9))
					"sunset":
						draw_circle(Vector2(size.x * 0.72, top_h - 4.0), 18.0, Color(1.0, 0.82, 0.4, k))
					"dawn":
						draw_circle(Vector2(size.x * 0.3, top_h - 6.0), 14.0, Color(1.0, 0.95, 0.85, k))
					_:
						draw_circle(Vector2(size.x * 0.76, h * 0.22), 13.0, Color(1.0, 0.95, 0.55, k))


class _Dot:
	extends Control
	var on := false

	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color.WHITE)
		draw_circle(c, r - 3.0, Color("4fd16b") if on else Color(0.82, 0.86, 0.93))
		if on:
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.4, 0), c + Vector2(-r * 0.1, r * 0.35), c + Vector2(r * 0.45, -r * 0.3)]), Color.WHITE, 4.0, true)


# ------------------------------------------------------------------ layout helpers
func _card(pos: Vector2, sz: Vector2, parent: Control = null, col := Color(1, 1, 1, 0.93), border := Color.WHITE, bw := 0) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = sz
	p.add_theme_stylebox_override("panel", UIKit.style_box(col, 36, bw, border, 12))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else _body).add_child(p)
	return p


func _lbl(parent: Control, text: String, pos: Vector2, sz: Vector2, fsize := 28, col := UIKit.INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UIKit.label(text, fsize, col, 0, Color.WHITE, align)
	l.position = pos
	l.size = sz
	parent.add_child(l)
	return l


func _bar(parent: Control, pos: Vector2, sz: Vector2, ratio: float, col: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.position = pos
	pb.size = sz
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.value = clampf(ratio, 0.0, 1.0)
	pb.show_percentage = false
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.add_theme_stylebox_override("background", UIKit.style_box(Color(0.85, 0.88, 0.95), int(sz.y / 2.0)))
	pb.add_theme_stylebox_override("fill", UIKit.style_box(col, int(sz.y / 2.0)))
	parent.add_child(pb)
	return pb


func _fmt_time(sec: float) -> String:
	var m := int(sec / 60.0)
	if m < 60:
		return "%d 分钟" % m
	return "%d 小时 %d 分" % [m / 60, m % 60]


# ------------------------------------------------------------------ build
func build() -> CareerPage:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var title := UIKit.label("生涯", 64, Color.WHITE, 14, Color(0.05, 0.2, 0.45, 0.95), HORIZONTAL_ALIGNMENT_LEFT)
	title.position = Vector2(70, 26)
	title.size = Vector2(360, 90)
	add_child(title)
	var group := ButtonGroup.new()
	var names := ["概览", "收藏", "成就"]
	for i in names.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = names[i]
		b.size = Vector2(196, 64)
		b.position = Vector2(470.0 + 210.0 * float(i), 38)
		b.add_theme_font_size_override("font_size", 30)
		for n in ["font_color", "font_hover_color", "font_focus_color"]:
			b.add_theme_color_override(n, UIKit.INK)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		b.add_theme_stylebox_override("normal", UIKit.style_box(Color(1, 1, 1, 0.9), 32, 0, Color.WHITE, 6))
		b.add_theme_stylebox_override("hover", UIKit.style_box(Color(0.93, 0.97, 1.0), 32, 0, Color.WHITE, 8))
		b.add_theme_stylebox_override("pressed", UIKit.style_box(UIKit.BLUE, 32, 0, Color.WHITE, 4))
		b.add_theme_stylebox_override("hover_pressed", UIKit.style_box(UIKit.BLUE.lightened(0.1), 32, 0, Color.WHITE, 6))
		b.add_theme_stylebox_override("focus", UIKit.style_box(Color(1, 1, 1, 0.0), 32, 4, UIKit.YELLOW, 0))
		var idx := i
		b.pressed.connect(func():
			Sfx.play("ui_click", -4.0)
			_tab = idx
			refresh())
		add_child(b)
		_tabs.append(b)
	_body = Control.new()
	_body.position = Vector2(70, 138)
	_body.size = Vector2(1780, 800)
	add_child(_body)
	var back := UIKit.button("返回", Vector2(220, 64), UIKit.PINK, 30)
	back.position = Vector2(70, 962)
	back.pressed.connect(func(): back_pressed.emit())
	add_child(back)
	_desc = UIKit.label("", 28, Color.WHITE, 8, Color(0.05, 0.15, 0.35, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	_desc.position = Vector2(320, 962)
	_desc.size = Vector2(1520, 64)
	add_child(_desc)
	return self


func tab() -> int:
	return _tab


func show_tab(i: int) -> void:
	_tab = i
	refresh()


func refresh() -> void:
	for c in _body.get_children():
		c.queue_free()
	_tabs[_tab].set_pressed_no_signal(true)
	_desc.text = ""
	if Game.profile == null:
		return
	match _tab:
		0: _build_overview()
		1: _build_collection()
		2: _build_achievements()


# ------------------------------------------------------------------ overview
func _build_overview() -> void:
	var p: Profile = Game.profile
	var info := Profile.level_info(p.xp)
	# --- profile + records
	var card := _card(Vector2(0, 0), Vector2(560, 800))
	var e := Roster.by_id(Game.p1_char)
	var av := UIKit.avatar(Game.p1_char, 150, UIKit.BLUE, 6)
	av.position = Vector2(34, 30)
	card.add_child(av)
	_lbl(card, String(e["name"]), Vector2(210, 30), Vector2(320, 56), 44)
	_lbl(card, String(info["title"]), Vector2(210, 86), Vector2(320, 44), 30, Color("e0782a"))
	_lbl(card, "Lv.%d" % int(info["level"]), Vector2(210, 126), Vector2(320, 60), 50, UIKit.BLUE)
	_bar(card, Vector2(34, 208), Vector2(492, 26), float(info["ratio"]), UIKit.GREEN)
	var xp_text := "经验 %d / %d" % [int(info["into"]), int(info["need"])] if int(info["level"]) < Profile.MAX_LEVEL else "已满级!"
	_lbl(card, xp_text, Vector2(34, 238), Vector2(492, 32), 22, Color(0.35, 0.4, 0.55), HORIZONTAL_ALIGNMENT_RIGHT)
	var st: Dictionary = p.stats
	var matches := int(st.get("matches", 0))
	var wins := int(st.get("wins", 0))
	var rows := [
		["比赛", "%d 场" % matches], ["胜场", "%d 场" % wins],
		["胜率", ("%d%%" % int(100.0 * float(mini(wins, matches)) / float(matches))) if matches > 0 else "-"], ["得分", str(int(st.get("points", 0)))],
		["ACE", str(int(st.get("aces", 0)))], ["拦网得分", str(int(st.get("blocks", 0)))],
		["Nice! 击球", str(int(st.get("perfects", 0)))], ["强力扣球", str(int(st.get("power_spikes", 0)))],
		["最长回合", "%d 次" % int(st.get("longest_rally", 0))], ["撞晕次数", str(int(st.get("knockdowns", 0)))],
		["热血时刻", str(int(st.get("fever", 0)))], ["游玩时间", _fmt_time(float(st.get("playtime", 0.0)))],
	]
	for i in rows.size():
		var cx := 34.0 + float(i % 2) * 262.0
		var cy := 292.0 + float(i / 2) * 82.0
		_lbl(card, rows[i][0], Vector2(cx, cy), Vector2(250, 28), 22, Color(0.4, 0.45, 0.6))
		_lbl(card, rows[i][1], Vector2(cx, cy + 26.0), Vector2(250, 44), 34)
	# --- daily missions
	var mc := _card(Vector2(590, 0), Vector2(1190, 424))
	_lbl(mc, "今日任务", Vector2(36, 18), Vector2(300, 56), 42)
	var done := p.missions_done()
	_lbl(mc, "%d / %d 完成" % [done, p.daily["list"].size()], Vector2(860, 24), Vector2(294, 44), 30, UIKit.GREEN_DARK, HORIZONTAL_ALIGNMENT_RIGHT)
	for i in p.daily["list"].size():
		var m: Dictionary = p.daily["list"][i]
		var y := 96.0 + float(i) * 82.0
		var dot := _Dot.new()
		dot.position = Vector2(36, y + 12)
		dot.size = Vector2(44, 44)
		dot.on = bool(m["done"])
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mc.add_child(dot)
		var tl := _lbl(mc, String(m["text"]), Vector2(100, y + 6), Vector2(640, 56), 32, Color(0.5, 0.55, 0.68) if m["done"] else UIKit.INK)
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var prog := mini(int(m["progress"]), int(m["goal"]))
		_bar(mc, Vector2(760, y + 22), Vector2(230, 22), float(prog) / float(m["goal"]), UIKit.GREEN if m["done"] else UIKit.BLUE)
		_lbl(mc, "%d/%d" % [prog, int(m["goal"])], Vector2(1000, y + 12), Vector2(90, 40), 26, Color(0.35, 0.4, 0.55))
		_lbl(mc, "+%d XP" % int(m["xp"]), Vector2(1070, y + 12), Vector2(100, 40), 26, Color("e0782a"), HORIZONTAL_ALIGNMENT_RIGHT)
	var streak := int(p.daily["streak"])
	_lbl(mc, "连续登录 %d 天  ·  全部经验 ×%.2f  (连续 5 天达到上限 ×1.25)" % [streak, p.streak_bonus()], Vector2(36, 354), Vector2(1120, 44), 26, Color("c4501a"))
	# --- next unlock + records
	var nc := _card(Vector2(590, 448), Vector2(1190, 352))
	_lbl(nc, "下一个解锁", Vector2(36, 18), Vector2(400, 52), 38)
	var nxt := _next_unlock(p.level())
	if nxt.is_empty():
		_lbl(nc, "所有装扮都已解锁!", Vector2(36, 120), Vector2(520, 56), 32, Color(0.35, 0.4, 0.55))
	else:
		var sw := _Swatch.new()
		sw.kind = String(nxt["kind"])
		sw.item = nxt
		sw.position = Vector2(36, 96)
		sw.size = Vector2(200, 130)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nc.add_child(sw)
		_lbl(nc, "%s · %s" % [KIND_TITLES[nxt["kind"]], nxt["name"]], Vector2(256, 100), Vector2(380, 44), 32)
		_lbl(nc, String(nxt["desc"]), Vector2(256, 146), Vector2(380, 36), 24, Color(0.4, 0.45, 0.6))
		var need := maxi(Profile.xp_for_level(int(nxt["level"])) - p.xp, 0)
		_lbl(nc, "Lv.%d 解锁  ·  还差 %d 经验" % [int(nxt["level"]), need], Vector2(256, 186), Vector2(420, 40), 26, Color("e0782a"))
	var sep := ColorRect.new()
	sep.color = Color(0.8, 0.84, 0.92)
	sep.position = Vector2(690, 30)
	sep.size = Vector2(3, 290)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nc.add_child(sep)
	_lbl(nc, "我的纪录", Vector2(730, 18), Vector2(300, 52), 38)
	var rbest := int(p.flags.get("rally_best", 0))
	var medal := Profile.medal_for(rbest)
	var tb := int(p.flags.get("tournament_best", 0))
	var rec := [
		["回合挑战", ("%d 次触球 (%s)" % [rbest, medal["name"]]) if not medal.is_empty() else ("%d 次触球" % rbest)],
		["锦标赛", ["尚未参加", "通过小组赛", "进入决赛", "冠军!"][clampi(tb, 0, 3)]],
		["新手教学", "已毕业" if p.flags.get("tutorial_done", false) else "未完成"],
		["成就", "%d / %d" % [p.achievements.size(), Profile.ACHIEVEMENTS.size()]],
	]
	for i in rec.size():
		_lbl(nc, rec[i][0], Vector2(730, 90.0 + float(i) * 56.0), Vector2(200, 48), 26, Color(0.4, 0.45, 0.6))
		_lbl(nc, rec[i][1], Vector2(930, 90.0 + float(i) * 56.0), Vector2(230, 48), 28)
	var go := UIKit.button("装扮收藏", Vector2(300, 64), UIKit.BLUE, 30)
	go.position = Vector2(36, 262)
	go.pressed.connect(func(): show_tab(1))
	nc.add_child(go)


func _next_unlock(level: int) -> Dictionary:
	var best := {}
	for kind in ["trail", "ball", "court"]:
		for it in Profile.catalog(kind):
			if int(it["level"]) > level and (best.is_empty() or int(it["level"]) < int(best["level"])):
				best = (it as Dictionary).duplicate()
				best["kind"] = kind
	return best


# ------------------------------------------------------------------ collection
func _build_collection() -> void:
	var p: Profile = Game.profile
	var y := 0.0
	for kind in ["trail", "ball", "court"]:
		var t := UIKit.label(KIND_TITLES[kind], 38, Color.WHITE, 10, Color(0.05, 0.2, 0.45, 0.95), HORIZONTAL_ALIGNMENT_LEFT)
		t.position = Vector2(6, y)
		t.size = Vector2(400, 52)
		_body.add_child(t)
		var cat := Profile.catalog(kind)
		for i in cat.size():
			var b := _item_card(kind, cat[i], p)
			b.position = Vector2(float(i) * 226.0, y + 58.0)
			_body.add_child(b)
		y += 262.0
	_desc.text = "点击已解锁的装扮即可装备;升级解锁更多。拖尾只在你方击球时显示。"


func _item_card(kind: String, it: Dictionary, p: Profile) -> Button:
	var unlocked := p.is_unlocked(kind, String(it["id"]))
	var on: bool = String(p.equipped.get(kind, "")) == String(it["id"]) and unlocked
	var b := Button.new()
	b.size = Vector2(212, 196)
	b.focus_mode = Control.FOCUS_ALL
	var base := Color(1, 1, 1, 0.93) if unlocked else Color(0.82, 0.85, 0.92, 0.9)
	b.add_theme_stylebox_override("normal", UIKit.style_box(base, 30, 6 if on else 0, Color("4fd16b"), 8))
	b.add_theme_stylebox_override("hover", UIKit.style_box(Color(1.0, 0.98, 0.88) if unlocked else base, 30, 5, UIKit.YELLOW, 10))
	b.add_theme_stylebox_override("pressed", UIKit.style_box(Color(0.9, 0.96, 0.9), 30, 6, Color("4fd16b"), 4))
	b.add_theme_stylebox_override("focus", UIKit.style_box(Color(1.0, 0.98, 0.88) if unlocked else base, 30, 5, UIKit.YELLOW, 10))
	var holder: Control = b
	if kind == "court":
		var clip := Panel.new()
		clip.position = Vector2(18, 14)
		clip.size = Vector2(176, 100)
		clip.add_theme_stylebox_override("panel", UIKit.style_box(Color.WHITE, 18))
		clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(clip)
		holder = clip
	var sw := _Swatch.new()
	sw.kind = kind
	sw.item = it
	sw.locked = not unlocked
	sw.position = Vector2(0, 0) if kind == "court" else Vector2(18, 14)
	sw.size = Vector2(176, 100)
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(sw)
	var nm := UIKit.label(String(it["name"]), 28, UIKit.INK if unlocked else Color(0.45, 0.5, 0.62))
	nm.position = Vector2(0, 118)
	nm.size = Vector2(212, 38)
	b.add_child(nm)
	var sub_text := "使用中" if on else ("点击装备" if unlocked else "Lv.%d 解锁" % int(it["level"]))
	var sub := UIKit.label(sub_text, 22, Color("25963a") if on else (Color(0.45, 0.5, 0.62) if unlocked else Color("c4501a")))
	sub.position = Vector2(0, 154)
	sub.size = Vector2(212, 32)
	b.add_child(sub)
	var info_text := "%s — %s" % [it["name"], it["desc"]]
	var lock_text := "%s — 达到 Lv.%d 解锁（还差 %d 经验）" % [it["name"], int(it["level"]), maxi(Profile.xp_for_level(int(it["level"])) - p.xp, 0)]
	b.mouse_entered.connect(func(): _desc.text = info_text if unlocked else lock_text)
	b.focus_entered.connect(func(): _desc.text = info_text if unlocked else lock_text)
	b.pressed.connect(func():
		if unlocked:
			if p.equip(kind, String(it["id"])):
				Sfx.play("ui_confirm", -3.0)
				var keep := _desc.text
				refresh()
				_desc.text = keep
		else:
			Sfx.play("ui_hover", -4.0)
			_desc.text = lock_text)
	return b


# ------------------------------------------------------------------ achievements
func _build_achievements() -> void:
	var p: Profile = Game.profile
	var sc := ScrollContainer.new()
	sc.size = Vector2(1780, 800)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	sc.add_child(grid)
	var list: Array = Profile.ACHIEVEMENTS.duplicate()
	var done_n := 0
	for a in list:
		var got := p.achievements.has(a["id"])
		if got:
			done_n += 1
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(432, 140)
		grid.add_child(cell)
		var card := _card(Vector2.ZERO, Vector2(432, 140), cell, Color(1, 0.98, 0.88, 0.95) if got else Color(1, 1, 1, 0.9), GOLD, 5 if got else 0)
		_lbl(card, String(a["name"]), Vector2(22, 8), Vector2(300, 44), 30, UIKit.INK)
		_lbl(card, "+%d XP" % int(a["xp"]), Vector2(318, 8), Vector2(100, 44), 24, Color("e0782a"), HORIZONTAL_ALIGNMENT_RIGHT)
		var dl := _lbl(card, String(a["desc"]), Vector2(22, 52), Vector2(390, 52), 22, Color(0.38, 0.43, 0.58))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		var cur := mini(p.counter(String(a["key"])), int(a["goal"]))
		_bar(card, Vector2(22, 106), Vector2(290, 18), float(cur) / float(a["goal"]), GOLD if got else UIKit.BLUE)
		if got:
			var dot := _Dot.new()
			dot.on = true
			dot.position = Vector2(360, 92)
			dot.size = Vector2(44, 44)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(dot)
		else:
			_lbl(card, "%d/%d" % [cur, int(a["goal"])], Vector2(318, 96), Vector2(96, 40), 24, Color(0.35, 0.4, 0.55), HORIZONTAL_ALIGNMENT_RIGHT)
	_desc.text = "已解锁 %d / %d" % [done_n, list.size()]

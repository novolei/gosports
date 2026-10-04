extends Node
## Title screen hub: main menu, mode/options, character select, line-up, settings and how-to-play.

var stage: Stage
var ui: CanvasLayer
var pages: Dictionary = {}
var page := ""
var _fade_rect: ColorRect

# select flow
var _pick_step := 0
var _pick_order: Array = []       # list of {"who": "p1"/"p2", "label": String}
var _picks := {}
var _preview_rig: CharacterRig = null
var _preview_idx := -1
var _grid_buttons: Array[Button] = []
var _sel_name: Label
var _sel_blurb: Label
var _sel_perk: Label
var _sel_bars: Array[ProgressBar] = []
var _sel_header: Label
var _lineup_box: HBoxContainer
var _lineup_title: Label
var _lineup_go: Button
var _mode_cards: HBoxContainer
var _roster: Array[Dictionary] = []
var _lineup := {"a": [], "b": []}
var _how_tab := 0
var _how_label: RichTextLabel


func setup(data: Dictionary) -> void:
	_roster = Roster.all()
	if Game.main != null and Game.main.dev.has("mode"):
		Game.mode = String(Game.main.dev["mode"])
	stage = Stage.new()
	add_child(stage)
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	_build_pages()
	Sfx.music("bgm_menu")
	Sfx.crowd(false)
	var start: String = data.get("page", "main")
	if Game.main != null and Game.main.dev.has("page"):
		start = String(Game.main.dev["page"])
	if start == "lineup":
		_picks = {"p1": Game.p1_char, "p2": Game.p2_char}
		_make_lineup()
	_show_page(start, true)
	_maybe_welcome()
	_maybe_daily_greeting()
	if start == "lineup" and Game.main != null and Game.main.dev.has("autostart"):
		await get_tree().process_frame
		_start_match()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:      # Android back button
		_go_back()


func _go_back() -> void:
	match page:
		"mode", "settings", "howto", "career", "practice": _show_page("main")
		"select": _select_back()
		"lineup": _show_page("select")


# ------------------------------------------------------------------ pages
func _build_pages() -> void:
	pages["main"] = _build_main()
	pages["mode"] = _build_mode()
	pages["select"] = _build_select()
	pages["lineup"] = _build_lineup()
	pages["settings"] = _build_settings()
	pages["howto"] = _build_howto()
	pages["practice"] = _build_practice()
	_career = CareerPage.new().build()
	_career.back_pressed.connect(func(): _show_page("main"))
	pages["career"] = _career
	for k in pages.keys():
		var c: Control = pages[k]
		c.visible = false
		ui.add_child(c)
	_build_footer()


## button prompts at the bottom right of every page, like the reference menus (Select / Back / OK)
func _build_footer() -> void:
	if Game.is_touch:
		return
	var pads: bool = Input.get_connected_joypads().size() > 0
	var items := [["左摇杆", "选择"], ["B", "返回"], ["A", "确定"]] if pads else [["方向键 / 鼠标", "选择"], ["Esc", "返回"], ["Enter / 点击", "确定"]]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	row.position = Vector2(-820, -64)
	row.size = Vector2(780, 44)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(row)
	for it in items:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap := PanelContainer.new()
		cap.add_theme_stylebox_override("panel", UIKit.style_box(Color(1, 1, 1, 0.9), 12, 0, Color.WHITE, 4, 12))
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap.add_child(UIKit.label(String(it[0]), 20, UIKit.INK))
		cell.add_child(cap)
		cell.add_child(UIKit.label(String(it[1]), 22, Color.WHITE, 6, Color(0.05, 0.12, 0.3, 0.9)))
		row.add_child(cell)


func _show_page(p: String, instant := false) -> void:
	page = p
	for k in pages.keys():
		(pages[k] as Control).visible = (k == p)
	var c: Control = pages[p]
	if not instant:
		UIKit.pop_in(c, 0.96, 0.22)
		Sfx.play("ui_swoosh", -10.0)
	_on_page(p)


func _on_page(p: String) -> void:
	stage.clear_rigs()
	_preview_rig = null
	_preview_idx = -1
	match p:
		"main":
			stage.look(Vector3(-1.5, 1.7, 9.5), Vector3(0.5, 1.62, 2.0))
			stage.add_rig(Roster.by_id(Game.p1_char), Vector3(2.4, 0, 4.8), PI + 0.35, "cheer")
			stage.add_rig(Roster.by_id("bear"), Vector3(3.9, 0, 4.2), PI + 0.15, "cheer")
			stage.add_rig(Roster.by_id("ninja_red"), Vector3(-2.2, 0, -1.8), 0.0, "ready")
			stage.add_rig(Roster.by_id("snow"), Vector3(-3.4, 0, -2.6), 0.3, "ready")
			(pages["main"].get_node("Buttons").get_child(0) as Control).grab_focus()
		"mode":
			if not ["solo", "coop", "versus"].has(Game.mode):
				Game.mode = "solo"
			_refresh_mode_cards(_mode_cards)
			stage.look(Vector3(0.0, 4.5, 12.5), Vector3(0, 0.8, 0))
			stage.add_rig(Roster.by_id(Game.p1_char), Vector3(-2.0, 0, 3.8), 0.4, "ready")
		"practice":
			stage.look(Vector3(0.0, 4.5, 12.5), Vector3(0, 0.8, 0))
			stage.add_rig(Roster.by_id(Game.p1_char), Vector3(-5.2, 0, 3.6), 0.5, "ready")
			stage.add_rig(Roster.by_id("bear"), Vector3(5.2, 0, 3.6), -0.5, "bump")
		"career":
			stage.look(Vector3(0.0, 4.0, 13.0), Vector3(0, 0.8, 0))
			if Game.profile != null:
				Game.profile.flags["seen_news"] = _news_count()
				if _news_dot != null:
					_news_dot.visible = false
				if Game.profile_enabled and not (Game.main != null and Game.main.dev.has("nosave")):
					Game.profile.save()
			_career.show_tab(int(Game.main.dev["tab"]) if Game.main != null and Game.main.dev.has("tab") else _career.tab())
		"select":
			_start_select()
		"lineup":
			_build_lineup_view()
		"settings":
			stage.look(Vector3(0.0, 4.0, 13.0), Vector3(0, 0.8, 0))
		"howto":
			stage.look(Vector3(0.0, 5.0, 12.0), Vector3(0, 0.8, -1))


func _bg_dim() -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0.1, 0.2, 0.4, 0.0)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


# ---- MAIN
var _news_dot: Control
var _welcome_shown := false
var _career: CareerPage


func _build_main() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# logo
	var logo := Control.new()
	logo.position = Vector2(70, 40)
	root.add_child(logo)
	var banner := Panel.new()
	banner.position = Vector2(0, 0)
	banner.size = Vector2(640, 150)
	var sb := UIKit.style_box(Color("5bd65b"), 75, 0, Color.WHITE, 14)
	banner.add_theme_stylebox_override("panel", sb)
	logo.add_child(banner)
	var l1 := UIKit.label("排球", 108, Color.WHITE, 16, Color("1f7a32"))
	l1.position = Vector2(40, 0)
	l1.size = Vector2(300, 150)
	logo.add_child(l1)
	var l2 := UIKit.label("GoSports", 58, Color("fff3a0"), 12, Color("1f7a32"))
	l2.position = Vector2(300, 22)
	l2.size = Vector2(320, 110)
	logo.add_child(l2)
	var sub := UIKit.label("Volleyball · 2v2 · 键鼠 / 手柄 / 触屏", 26, Color.WHITE, 8, Color(0.05, 0.15, 0.35, 0.9))
	sub.position = Vector2(10, 160)
	sub.size = Vector2(620, 40)
	logo.add_child(sub)
	# buttons
	var vb := VBoxContainer.new()
	vb.name = "Buttons"
	vb.position = Vector2(90, 268)
	vb.add_theme_constant_override("separation", 14)
	root.add_child(vb)
	var b1 := UIKit.button("开始比赛", Vector2(430, 84), UIKit.GREEN, 40)
	b1.pressed.connect(func(): _show_page("mode"))
	vb.add_child(b1)
	var bt := UIKit.button("锦标赛", Vector2(430, 72), Color("ff9a2e"), 34)
	bt.pressed.connect(func():
		Game.mode = "tournament"
		_show_page("select"))
	vb.add_child(bt)
	var bp := UIKit.button("练习场", Vector2(430, 72), UIKit.BLUE, 34)
	bp.pressed.connect(func(): _show_page("practice"))
	vb.add_child(bp)
	var bc := UIKit.button("生涯  ·  装扮  ·  成就", Vector2(430, 72), Color("8e5bff"), 32)
	bc.pressed.connect(func(): _show_page("career"))
	vb.add_child(bc)
	_news_dot = Control.new()
	_news_dot.position = Vector2(396, -8)
	_news_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bc.add_child(_news_dot)
	var dot := Panel.new()
	dot.size = Vector2(40, 40)
	dot.add_theme_stylebox_override("panel", UIKit.style_box(Color("ff3b4f"), 20, 4, Color.WHITE, 4))
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_news_dot.add_child(dot)
	var dl := UIKit.label("!", 28, Color.WHITE)
	dl.size = Vector2(40, 38)
	_news_dot.add_child(dl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	var b2 := UIKit.button("操作说明", Vector2(208, 64), Color("22b8a8"), 28)
	b2.pressed.connect(func(): _show_page("howto"))
	row.add_child(b2)
	var b3 := UIKit.button("设置", Vector2(208, 64), UIKit.YELLOW.darkened(0.1), 28)
	b3.pressed.connect(func(): _show_page("settings"))
	row.add_child(b3)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		var b4 := UIKit.button("退出", Vector2(430, 58), UIKit.PINK, 30)
		b4.pressed.connect(func(): get_tree().quit())
		vb.add_child(b4)
	if not OS.has_feature("mobile"):
		var foot := UIKit.label("F11 全屏", 22, Color.WHITE, 6, Color(0.05, 0.1, 0.3, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
		foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		foot.position = Vector2(96, -56)
		foot.size = Vector2(300, 36)
		root.add_child(foot)
	if Game.profile != null:
		_build_profile_cards(root)
	return root


func _news_count() -> int:
	var p := Game.profile
	return Profile.unlocks_between(0, p.level()).size() + p.achievements.size()


func _build_profile_cards(root: Control) -> void:
	var p := Game.profile
	var info := Profile.level_info(p.xp)
	if not p.flags.has("seen_news"):
		p.flags["seen_news"] = _news_count()              # a brand-new profile has nothing "new" yet
	_news_dot.visible = _news_count() > int(p.flags["seen_news"])
	# --- profile card
	var pc := Button.new()
	pc.position = Vector2(1370, 36)
	pc.size = Vector2(490, 190)
	pc.focus_mode = Control.FOCUS_ALL
	for st in ["normal", "focus"]:
		pc.add_theme_stylebox_override(st, UIKit.style_box(Color(1, 1, 1, 0.92), 36, 0 if st == "normal" else 5, UIKit.YELLOW, 12))
	pc.add_theme_stylebox_override("hover", UIKit.style_box(Color(1.0, 0.99, 0.92), 36, 4, UIKit.YELLOW, 14))
	pc.add_theme_stylebox_override("pressed", UIKit.style_box(Color(0.95, 0.97, 1.0), 36, 0, Color.WHITE, 6))
	pc.pressed.connect(func(): _show_page("career"))
	root.add_child(pc)
	var e := Roster.by_id(Game.p1_char)
	var av := UIKit.avatar(Game.p1_char, 124, UIKit.BLUE, 5)
	av.position = Vector2(22, 20)
	pc.add_child(av)
	var nm := UIKit.label(String(e["name"]), 36, UIKit.INK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	nm.position = Vector2(166, 14)
	nm.size = Vector2(300, 46)
	pc.add_child(nm)
	var tt := UIKit.label(String(info["title"]), 26, Color("e0782a"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	tt.position = Vector2(166, 58)
	tt.size = Vector2(300, 34)
	pc.add_child(tt)
	var lv := UIKit.label("Lv.%d" % int(info["level"]), 44, UIKit.BLUE, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	lv.position = Vector2(166, 92)
	lv.size = Vector2(150, 52)
	pc.add_child(lv)
	var xt := UIKit.label(("%d / %d XP" % [int(info["into"]), int(info["need"])]) if int(info["level"]) < Profile.MAX_LEVEL else "MAX", 22, Color(0.35, 0.4, 0.55), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	xt.position = Vector2(300, 104)
	xt.size = Vector2(170, 32)
	pc.add_child(xt)
	var pb := ProgressBar.new()
	pb.position = Vector2(22, 150)
	pb.size = Vector2(446, 22)
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.value = float(info["ratio"])
	pb.show_percentage = false
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.add_theme_stylebox_override("background", UIKit.style_box(Color(0.85, 0.88, 0.95), 11))
	pb.add_theme_stylebox_override("fill", UIKit.style_box(UIKit.GREEN, 11))
	pc.add_child(pb)
	# --- daily missions card
	var mc := Button.new()
	mc.position = Vector2(1370, 242)
	mc.size = Vector2(490, 250)
	mc.focus_mode = Control.FOCUS_ALL
	for st in ["normal", "focus"]:
		mc.add_theme_stylebox_override(st, UIKit.style_box(Color(1, 1, 1, 0.92), 36, 0 if st == "normal" else 5, UIKit.YELLOW, 12))
	mc.add_theme_stylebox_override("hover", UIKit.style_box(Color(1.0, 0.99, 0.92), 36, 4, UIKit.YELLOW, 14))
	mc.add_theme_stylebox_override("pressed", UIKit.style_box(Color(0.95, 0.97, 1.0), 36, 0, Color.WHITE, 6))
	mc.pressed.connect(func(): _show_page("career"))
	root.add_child(mc)
	var mh := UIKit.label("今日任务", 30, UIKit.INK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	mh.position = Vector2(26, 10)
	mh.size = Vector2(200, 44)
	mc.add_child(mh)
	var mn := UIKit.label("%d/%d  ·  连续 %d 天" % [p.missions_done(), p.daily["list"].size(), int(p.daily["streak"])], 22, UIKit.GREEN_DARK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	mn.position = Vector2(220, 14)
	mn.size = Vector2(250, 36)
	mc.add_child(mn)
	for i in p.daily["list"].size():
		var m: Dictionary = p.daily["list"][i]
		var y := 58.0 + float(i) * 60.0
		var ck := _MiniDot.new()
		ck.position = Vector2(24, y + 8)
		ck.size = Vector2(32, 32)
		ck.on = bool(m["done"])
		ck.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mc.add_child(ck)
		var ml := UIKit.label(String(m["text"]), 23, Color(0.5, 0.55, 0.68) if m["done"] else UIKit.INK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		ml.position = Vector2(68, y - 4)
		ml.size = Vector2(330, 34)
		mc.add_child(ml)
		var xl := UIKit.label("+%d" % int(m["xp"]), 22, Color("e0782a"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		xl.position = Vector2(396, y - 4)
		xl.size = Vector2(70, 34)
		mc.add_child(xl)
		var mb := ProgressBar.new()
		mb.position = Vector2(68, y + 31)
		mb.size = Vector2(398, 12)
		mb.min_value = 0.0
		mb.max_value = 1.0
		mb.value = clampf(float(m["progress"]) / float(m["goal"]), 0.0, 1.0)
		mb.show_percentage = false
		mb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mb.add_theme_stylebox_override("background", UIKit.style_box(Color(0.85, 0.88, 0.95), 6))
		mb.add_theme_stylebox_override("fill", UIKit.style_box(UIKit.GREEN if m["done"] else UIKit.BLUE, 6))
		mc.add_child(mb)


class _MiniDot:
	extends Control
	var on := false

	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color.WHITE)
		draw_circle(c, r - 2.5, Color("4fd16b") if on else Color(0.82, 0.86, 0.93))
		if on:
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.4, 0), c + Vector2(-r * 0.1, r * 0.35), c + Vector2(r * 0.45, -r * 0.3)]), Color.WHITE, 3.0, true)


# ---- PRACTICE
func _build_practice() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var title := UIKit.label("练习场", 64, Color.WHITE, 14, Color(0.05, 0.2, 0.45, 0.95))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-300, 34)
	title.size = Vector2(600, 90)
	root.add_child(title)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_top = 90
	root.add_child(c)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 40)
	c.add_child(vb)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 40)
	vb.add_child(cards)
	var p := Game.profile
	var tut_done: bool = p != null and p.flags.get("tutorial_done", false)
	var rbest: int = int(p.flags.get("rally_best", 0)) if p != null else 0
	var medal := Profile.medal_for(rbest)
	var defs := [
		{"id": "training", "name": "新手教学", "col": UIKit.GREEN, "icons": ["act_bump", "act_set", "act_spike"],
			"desc": "教练带你一步步学会\n垫球、传球和扣球\n完成可得 100 经验",
			"status": "已毕业" if tut_done else "推荐新手先来这里"},
		{"id": "rally", "name": "回合挑战", "col": UIKit.BLUE, "icons": [],
			"desc": "和发球机连续对打\n接球失误 3 次就结束\n铜 10 · 银 25 · 金 50",
			"status": ("最佳 %d 次 (%s)" % [rbest, medal["name"]]) if not medal.is_empty() else ("最佳 %d 次" % rbest)},
	]
	for d in defs:
		var b := Button.new()
		b.custom_minimum_size = Vector2(540, 470)
		var col: Color = d["col"]
		b.add_theme_stylebox_override("normal", UIKit.style_box(Color(1, 1, 1, 0.93), 44, 0, Color.WHITE, 14))
		b.add_theme_stylebox_override("hover", UIKit.style_box(Color(0.97, 1.0, 0.97), 44, 6, col, 16))
		b.add_theme_stylebox_override("pressed", UIKit.style_box(col.lightened(0.5), 44, 6, Color.WHITE, 8))
		b.add_theme_stylebox_override("focus", UIKit.style_box(Color(0.97, 1.0, 0.97), 44, 6, UIKit.YELLOW, 16))
		var head := Panel.new()
		head.position = Vector2(0, 0)
		head.size = Vector2(540, 120)
		head.add_theme_stylebox_override("panel", UIKit.style_box(col, 44))
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(head)
		var hl := UIKit.label(String(d["name"]), 54, Color.WHITE, 10, col.darkened(0.4))
		hl.position = Vector2(0, 0)
		hl.size = Vector2(540, 120)
		b.add_child(hl)
		var icons: Array = d["icons"]
		if icons.is_empty():
			for i in Profile.MEDALS.size():
				var m: Dictionary = Profile.MEDALS[i]
				var got := rbest >= int(m["goal"])
				var md := Panel.new()
				md.position = Vector2(150.0 + 100.0 * float(i), 144)
				md.size = Vector2(80, 80)
				md.add_theme_stylebox_override("panel", UIKit.style_box(m["color"] if got else Color(0.82, 0.85, 0.92), 40, 5, Color.WHITE, 6))
				md.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(md)
		else:
			for i in icons.size():
				var disc := Panel.new()
				disc.position = Vector2(112.0 + 120.0 * float(i), 138)
				disc.size = Vector2(96, 96)
				disc.add_theme_stylebox_override("panel", UIKit.style_box(col, 48, 5, Color.WHITE, 6))
				disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(disc)
				var tr := TextureRect.new()
				tr.texture = load("res://assets/ui/%s.png" % icons[i])
				tr.position = Vector2(118.0 + 120.0 * float(i), 144)
				tr.size = Vector2(84, 84)
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(tr)
		var dsc := UIKit.label(String(d["desc"]), 28, Color(0.25, 0.3, 0.45))
		dsc.position = Vector2(0, 248)
		dsc.size = Vector2(540, 130)
		b.add_child(dsc)
		var stl := UIKit.label(String(d["status"]), 30, Color("e0782a") if not tut_done or d["id"] == "rally" else Color("25963a"))
		stl.position = Vector2(0, 392)
		stl.size = Vector2(540, 56)
		b.add_child(stl)
		var mid: String = d["id"]
		b.pressed.connect(func():
			Game.mode = mid
			Sfx.play("ui_confirm", -3.0)
			_show_page("select"))
		cards.add_child(b)
	var back := UIKit.button("返回", Vector2(240, 72), UIKit.PINK, 32)
	back.pressed.connect(func(): _show_page("main"))
	vb.add_child(back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return root


# ---- daily greeting (once per launch, only when the day rolled over)
func _maybe_daily_greeting() -> void:
	var p := Game.profile
	if p == null or not p.new_day or _welcome_shown:
		return
	p.new_day = false
	var vp := Vector2(1920, 1080)
	var card := Panel.new()
	card.size = Vector2(760, 96)
	card.position = Vector2((vp.x - card.size.x) * 0.5, vp.y + 20.0)
	card.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.08, 0.2, 0.3, 0.94), 48, 3, Color(1, 1, 1, 0.9), 10))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(card)
	var l1 := UIKit.label("欢迎回来!  连续登录 %d 天" % int(p.daily["streak"]), 32, Color("fff3a0"), 6, Color(0.03, 0.12, 0.2, 0.9))
	l1.position = Vector2(0, 8)
	l1.size = Vector2(760, 44)
	card.add_child(l1)
	var l2 := UIKit.label("今日 3 个新任务已刷新   全部经验 ×%.2f" % p.streak_bonus(), 24, Color.WHITE, 4, Color(0.03, 0.12, 0.2, 0.9))
	l2.position = Vector2(0, 50)
	l2.size = Vector2(760, 36)
	card.add_child(l2)
	Sfx.play("ui_confirm", -6.0)
	var tw := card.create_tween()
	tw.tween_property(card, "position:y", vp.y - 150.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.6)
	tw.tween_property(card, "position:y", vp.y + 20.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(card.queue_free)


# ---- first-run welcome
func _maybe_welcome() -> void:
	var dev: Dictionary = Game.main.dev if Game.main != null else {}
	var forced := dev.has("welcome")
	if Game.profile == null or (Game.profile.flags.get("welcomed", false) and not forced):
		return
	if not forced and (dev.has("nosave") or dev.has("autoplay") or dev.has("autostart") or dev.has("page")):
		return
	_welcome_shown = true
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.12, 0.3, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var card := Panel.new()
	card.size = Vector2(900, 470)
	card.position = Vector2(510, 305)
	card.add_theme_stylebox_override("panel", UIKit.style_box(Color(1, 1, 1, 0.97), 50, 0, Color.WHITE, 18))
	overlay.add_child(card)
	var t := UIKit.label("欢迎来到排球!", 62, UIKit.INK)
	t.position = Vector2(0, 26)
	t.size = Vector2(900, 90)
	card.add_child(t)
	var d := UIKit.label("第一次玩?  先花 2 分钟跟着教练学会垫球、传球和扣球吧。\n完成教学有额外经验奖励,还能解锁更多球拖尾和球场!", 28, Color(0.25, 0.3, 0.45))
	d.position = Vector2(40, 130)
	d.size = Vector2(820, 120)
	card.add_child(d)
	var go := UIKit.button("开始新手教学", Vector2(380, 84), UIKit.GREEN, 38)
	go.position = Vector2(60, 310)
	card.add_child(go)
	var skip := UIKit.button("直接开打", Vector2(380, 84), UIKit.BLUE, 38)
	skip.position = Vector2(460, 310)
	card.add_child(skip)
	var hint := UIKit.label("(随时可以在「练习场」重新进入教学)", 22, Color(0.45, 0.5, 0.62))
	hint.position = Vector2(0, 416)
	hint.size = Vector2(900, 36)
	card.add_child(hint)
	UIKit.pop_in(card, 0.8, 0.3)
	go.grab_focus()
	if not dev.has("welcome"):
		Game.profile.flags["welcomed"] = true
		Game.profile.save()
	go.pressed.connect(func():
		overlay.queue_free()
		Game.mode = "training"
		_show_page("select"))
	skip.pressed.connect(func(): overlay.queue_free())


# ---- MODE / OPTIONS
func _segmented(options: Array, current_idx: int, on_change: Callable, width := 150) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var group := ButtonGroup.new()
	for i in options.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = str(options[i])
		b.custom_minimum_size = Vector2(width, 62)
		b.add_theme_font_size_override("font_size", 28)
		b.add_theme_color_override("font_color", UIKit.INK)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", UIKit.INK)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		b.add_theme_stylebox_override("normal", UIKit.style_box(Color(1, 1, 1, 0.9), 31, 0, Color.WHITE, 6))
		b.add_theme_stylebox_override("hover", UIKit.style_box(Color(0.93, 0.97, 1.0), 31, 0, Color.WHITE, 8))
		b.add_theme_stylebox_override("pressed", UIKit.style_box(UIKit.BLUE, 31, 0, Color.WHITE, 4))
		b.add_theme_stylebox_override("hover_pressed", UIKit.style_box(UIKit.BLUE.lightened(0.1), 31, 0, Color.WHITE, 6))
		b.add_theme_stylebox_override("focus", UIKit.style_box(Color(1, 1, 1, 0.0), 31, 4, UIKit.YELLOW, 0))
		if i == current_idx:
			b.button_pressed = true
		var idx := i
		b.pressed.connect(func(): Sfx.play("ui_click", -4.0); on_change.call(idx))
		h.add_child(b)
	return h


func _row(title: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	var l := UIKit.label(title, 30, UIKit.INK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(230, 0)
	h.add_child(l)
	h.add_child(control)
	return h


func _build_mode() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var title := UIKit.label("选择模式", 64, Color.WHITE, 14, Color(0.05, 0.2, 0.45, 0.95))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-300, 34)
	title.size = Vector2(600, 90)
	root.add_child(title)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_top = 90
	root.add_child(c)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 26)
	c.add_child(vb)
	# mode cards
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 26)
	vb.add_child(cards)
	var modes := [
		["solo", "单人对战", "你 + 电脑队友\nVS 电脑二人组", UIKit.GREEN],
		["coop", "双人合作", "两位玩家同一队\n一起对战电脑", UIKit.BLUE],
		["versus", "双人对决", "两位玩家各带电脑\n同屏对抗", UIKit.PINK],
	]
	for m in modes:
		var b := Button.new()
		b.custom_minimum_size = Vector2(380, 230)
		b.toggle_mode = true
		b.button_group = _mode_group()
		b.button_pressed = (Game.mode == m[0])
		var col: Color = m[3]
		b.add_theme_stylebox_override("normal", UIKit.style_box(Color(1, 1, 1, 0.92), 40, 0, Color.WHITE, 12))
		b.add_theme_stylebox_override("hover", UIKit.style_box(Color(0.96, 0.99, 1.0), 40, 5, col, 14))
		b.add_theme_stylebox_override("pressed", UIKit.style_box(col, 40, 6, Color.WHITE, 8))
		b.add_theme_stylebox_override("hover_pressed", UIKit.style_box(col.lightened(0.1), 40, 6, Color.WHITE, 10))
		b.add_theme_stylebox_override("focus", UIKit.style_box(Color(1, 1, 1, 0), 40, 6, UIKit.YELLOW, 0))
		var inner := VBoxContainer.new()
		inner.name = "V"
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(inner)
		var t := UIKit.label(m[1], 44, UIKit.INK)
		t.name = "T"
		inner.add_child(t)
		var d := UIKit.label(m[2], 26, Color(0.25, 0.3, 0.45))
		d.name = "D"
		inner.add_child(d)
		var mid: String = m[0]
		b.pressed.connect(func():
			Game.mode = mid
			Sfx.play("ui_click", -3.0)
			_refresh_mode_cards(cards))
		cards.add_child(b)
	cards.set_meta("modes", modes)
	_mode_cards = cards
	_refresh_mode_cards(cards)
	# options
	var opt := UIKit.panel(Color(1, 1, 1, 0.9), 40, 12)
	vb.add_child(opt)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 14)
	opt.add_child(ov)
	ov.add_child(_row("电脑难度", _segmented(Game.DIFFICULTY_NAMES, Game.settings["difficulty"], func(i): Game.settings["difficulty"] = i; Game.save_settings())))
	ov.add_child(_row("比赛分数", _segmented(["7 分", "11 分", "15 分"], [7, 11, 15].find(Game.settings["points"]), func(i): Game.settings["points"] = [7, 11, 15][i]; Game.save_settings(), 130)))
	var assist := CheckButton.new()
	assist.text = " 自动跑位辅助（球来时自动跑向落点，手动移动可接管）"
	assist.button_pressed = Game.settings["assist"]
	assist.add_theme_font_size_override("font_size", 26)
	assist.add_theme_color_override("font_color", UIKit.INK)
	assist.add_theme_color_override("font_hover_color", UIKit.INK)
	assist.add_theme_color_override("font_pressed_color", UIKit.INK)
	assist.toggled.connect(func(v): Game.settings["assist"] = v; Game.save_settings())
	ov.add_child(assist)
	# nav
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 24)
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(nav)
	var back := UIKit.button("返回", Vector2(240, 72), UIKit.PINK, 32)
	back.pressed.connect(func(): _show_page("main"))
	nav.add_child(back)
	var next := UIKit.button("选择角色", Vector2(360, 80), UIKit.GREEN, 38)
	next.pressed.connect(func(): _show_page("select"))
	nav.add_child(next)
	return root


var _mode_grp: ButtonGroup


func _mode_group() -> ButtonGroup:
	if _mode_grp == null:
		_mode_grp = ButtonGroup.new()
	return _mode_grp


func _refresh_mode_cards(cards: HBoxContainer) -> void:
	var modes: Array = cards.get_meta("modes")
	for i in modes.size():
		var b := cards.get_child(i) as Button
		var sel: bool = Game.mode == modes[i][0]
		b.set_pressed_no_signal(sel)
		(b.get_node("V/T") as Label).add_theme_color_override("font_color", Color.WHITE if sel else UIKit.INK)
		(b.get_node("V/D") as Label).add_theme_color_override("font_color", Color(1, 1, 1, 0.92) if sel else Color(0.25, 0.3, 0.45))


# ---- CHARACTER SELECT
func _build_select() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sel_header = UIKit.label("玩家1  选择角色", 56, Color.WHITE, 14, Color(0.05, 0.2, 0.45, 0.95), HORIZONTAL_ALIGNMENT_LEFT)
	_sel_header.position = Vector2(60, 28)
	_sel_header.size = Vector2(900, 80)
	root.add_child(_sel_header)
	# grid panel
	var pn := UIKit.panel(Color(1, 1, 1, 0.9), 40, 12)
	pn.position = Vector2(46, 120)
	root.add_child(pn)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(920, 700)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pn.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	_grid_buttons.clear()
	for i in _roster.size():
		var e := _roster[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(138, 160)
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_stylebox_override("normal", UIKit.style_box(Color(0.93, 0.96, 1.0), 26, 0, Color.WHITE, 4))
		b.add_theme_stylebox_override("hover", UIKit.style_box(Color(1.0, 0.98, 0.85), 26, 4, UIKit.YELLOW, 6))
		b.add_theme_stylebox_override("pressed", UIKit.style_box(UIKit.YELLOW, 26, 4, Color.WHITE, 2))
		b.add_theme_stylebox_override("focus", UIKit.style_box(Color(1.0, 0.98, 0.85), 26, 5, UIKit.YELLOW, 10))
		var av := UIKit.avatar(e["id"], 96, UIKit.BLUE if e["kind"] == "cube" else Color("8e3dff"), 4)
		av.position = Vector2(21, 10)
		b.add_child(av)
		var nm := UIKit.label(e["name"], 24, UIKit.INK)
		nm.position = Vector2(0, 112)
		nm.size = Vector2(138, 40)
		b.add_child(nm)
		var idx := i
		b.mouse_entered.connect(func(): _preview(idx))
		b.focus_entered.connect(func(): _preview(idx); Sfx.play("ui_hover", -9.0))
		b.pressed.connect(func(): _confirm_pick(idx))
		grid.add_child(b)
		_grid_buttons.append(b)
	# info panel
	var info := UIKit.panel(Color(1, 1, 1, 0.88), 40, 12)
	info.position = Vector2(1000, 760)
	info.custom_minimum_size = Vector2(840, 250)
	root.add_child(info)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 8)
	info.add_child(iv)
	_sel_name = UIKit.label("", 52, UIKit.INK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	iv.add_child(_sel_name)
	_sel_blurb = UIKit.label("", 28, Color(0.3, 0.35, 0.5), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	iv.add_child(_sel_blurb)
	_sel_perk = UIKit.label("", 26, Color(0.9, 0.45, 0.1), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	iv.add_child(_sel_perk)
	_sel_bars.clear()
	for t in [["速度", UIKit.BLUE], ["弹跳", UIKit.GREEN], ["力量", UIKit.PINK]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		var tl := UIKit.label(t[0], 26, UIKit.INK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		tl.custom_minimum_size = Vector2(80, 0)
		h.add_child(tl)
		var pb := ProgressBar.new()
		pb.min_value = 0.8
		pb.max_value = 1.2
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(540, 22)
		pb.add_theme_stylebox_override("background", UIKit.style_box(Color(0.85, 0.88, 0.95), 11))
		pb.add_theme_stylebox_override("fill", UIKit.style_box(t[1], 11))
		h.add_child(pb)
		iv.add_child(h)
		_sel_bars.append(pb)
	# back button
	var back := UIKit.button("返回", Vector2(220, 64), UIKit.PINK, 30)
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.position = Vector2(60, -100)
	back.pressed.connect(_select_back)
	root.add_child(back)
	var rnd := UIKit.button("随机", Vector2(220, 64), UIKit.BLUE, 30)
	rnd.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	rnd.position = Vector2(300, -100)
	rnd.pressed.connect(func(): _confirm_pick(randi() % _roster.size()))
	root.add_child(rnd)
	return root


func _start_select() -> void:
	_picks = {}
	_pick_order = [{"who": "p1", "label": "玩家1  选择角色"}]
	match Game.mode:
		"coop": _pick_order.append({"who": "p2", "label": "玩家2  选择角色（队友）"})
		"versus": _pick_order.append({"who": "p2", "label": "玩家2  选择角色（对手）"})
	_pick_step = 0
	_update_select_header()
	var start := Roster.index_of(Game.p1_char)
	_grid_buttons[start].grab_focus()
	_preview(start)
	stage.look(Vector3(0.0, 1.9, 9.5), Vector3(1.5, 1.05, 1.4))


func _update_select_header() -> void:
	_sel_header.text = _pick_order[_pick_step]["label"]


func _select_back() -> void:
	if _pick_step > 0:
		_pick_step -= 1
		_update_select_header()
	elif Game.mode == "tournament":
		_show_page("main")
	elif Game.is_practice():
		_show_page("practice")
	else:
		_show_page("mode")


func _preview(idx: int) -> void:
	if idx == _preview_idx:
		return
	_preview_idx = idx
	var e := Roster.by_id(_roster[idx]["id"])
	if _preview_rig and is_instance_valid(_preview_rig):
		_preview_rig.queue_free()
		stage.rigs.erase(_preview_rig)
	_preview_rig = stage.add_rig(e, Vector3(3.2, 0, 1.4), PI + 0.5, ["cheer", "ready", "bump", "set"][randi() % 4])
	_preview_rig.scale = Vector3.ONE * float(e["scale"]) * 1.25
	_sel_name.text = e["name"]
	_sel_blurb.text = e["blurb"]
	var pk := Roster.perk_info(String(e.get("perk", "")))
	_sel_perk.text = "特性「%s」 %s" % [pk["name"], pk["desc"]] if pk["name"] != "" else ""
	var st: Dictionary = e["stats"]
	_sel_bars[0].value = st["speed"]
	_sel_bars[1].value = st["jump"]
	_sel_bars[2].value = st["power"]


func _confirm_pick(idx: int) -> void:
	var id: String = _roster[idx]["id"]
	var who: String = _pick_order[_pick_step]["who"]
	_picks[who] = id
	Sfx.play("ui_confirm", -2.0)
	if who == "p1":
		Game.p1_char = id
	else:
		Game.p2_char = id
	_pick_step += 1
	if _pick_step >= _pick_order.size():
		_make_lineup()
		if Game.is_practice():
			_start_match()                # practice has no line-up: the other side is a ball machine
		else:
			_show_page("lineup")
	else:
		_update_select_header()


func _random_ids(count: int, exclude: Array) -> Array:
	var pool: Array = []
	for e in _roster:
		if not exclude.has(e["id"]):
			pool.append(e["id"])
	pool.shuffle()
	return pool.slice(0, count)


func _make_lineup() -> void:
	var used: Array = []
	var a: Array = []
	var b: Array = []
	match Game.mode:
		"solo":
			a = [_picks["p1"]]
			used.append(_picks["p1"])
			var r := _random_ids(3, used)
			a.append(r[0]); b = [r[1], r[2]]
		"coop":
			a = [_picks["p1"], _picks["p2"]]
			used = a.duplicate()
			b = _random_ids(2, used)
		"versus":
			a = [_picks["p1"]]
			b = [_picks["p2"]]
			used = [_picks["p1"], _picks["p2"]]
			var r2 := _random_ids(2, used)
			a.append(r2[0]); b.append(r2[1])
		"tournament":
			used = Game.tournament_ids() + [_picks["p1"]]
			a = [_picks["p1"], _random_ids(1, used)[0]]
			Game.team_a = a.duplicate()
			b = Game.tournament_opponents(0)
		_:                                 # rally / training: any partner and opponents (they only feed balls)
			a = [_picks["p1"]]
			used.append(_picks["p1"])
			var r3 := _random_ids(3, used)
			a.append(r3[0]); b = [r3[1], r3[2]]
	_lineup["a"] = a
	_lineup["b"] = b


# ---- LINEUP
func _build_lineup() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var title := UIKit.label("队伍阵容", 64, Color.WHITE, 14, Color(0.05, 0.2, 0.45, 0.95))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-300, 34)
	title.size = Vector2(600, 90)
	root.add_child(title)
	_lineup_title = title
	_lineup_box = HBoxContainer.new()
	_lineup_box.set_anchors_preset(Control.PRESET_CENTER)
	_lineup_box.position = Vector2(-760, -260)
	_lineup_box.add_theme_constant_override("separation", 80)
	root.add_child(_lineup_box)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 24)
	nav.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	nav.position = Vector2(-520, -170)
	root.add_child(nav)
	var back := UIKit.button("返回", Vector2(220, 72), UIKit.PINK, 30)
	back.pressed.connect(func(): _show_page("select"))
	nav.add_child(back)
	var shuffle := UIKit.button("随机换队", Vector2(260, 72), UIKit.BLUE, 30)
	shuffle.pressed.connect(func(): _shuffle_ai())
	nav.add_child(shuffle)
	var go := UIKit.button("开始比赛!", Vector2(420, 88), UIKit.GREEN, 44)
	go.name = "Go"
	_lineup_go = go
	go.pressed.connect(_start_match)
	nav.add_child(go)
	return root


func _shuffle_ai() -> void:
	var fixed: Array = []
	match Game.mode:
		"solo": fixed = [_picks["p1"]]
		"coop": fixed = [_picks["p1"], _picks["p2"]]
		"versus": fixed = [_picks["p1"], _picks["p2"]]
		"tournament": fixed = [_picks["p1"]] + Game.tournament_ids()
	var r := _random_ids(4, fixed)
	var a: Array = _lineup["a"]
	var b: Array = _lineup["b"]
	match Game.mode:
		"solo": a[1] = r[0]; b[0] = r[1]; b[1] = r[2]
		"coop": b[0] = r[0]; b[1] = r[1]
		"versus": a[1] = r[0]; b[1] = r[1]
		"tournament":
			a[1] = r[0]
			Game.team_a = a.duplicate()
			_lineup["b"] = Game.tournament_opponents(0)
	Sfx.play("ui_click")
	_build_lineup_view()


func _cycle_ai(team: String, slot: int, step := 1) -> void:
	var cur_id: String = _lineup[team][slot]
	var idx := Roster.index_of(cur_id)
	var taken: Array = _lineup["a"] + _lineup["b"]
	if Game.mode == "tournament":
		taken += Game.tournament_ids()
	for k in _roster.size():
		idx = (idx + step + _roster.size()) % _roster.size()
		var cand: String = _roster[idx]["id"]
		if not taken.has(cand):
			_lineup[team][slot] = cand
			break
	Sfx.play("ui_click", -4.0)
	_build_lineup_view()


func _is_human_slot(team: String, slot: int) -> bool:
	match Game.mode:
		"solo": return team == "a" and slot == 0
		"coop": return team == "a"
		"versus": return slot == 0
		"tournament": return team == "a" and slot == 0
	return false


func _build_lineup_view() -> void:
	for c in _lineup_box.get_children():
		c.queue_free()
	stage.clear_rigs()
	stage.look(Vector3(0.0, 3.8, 12.5), Vector3(0, 1.0, 0.0))
	var tour: bool = Game.mode == "tournament"
	_lineup_title.text = ("锦标赛 · %s" % Game.TOURNAMENT_ROUNDS[0]["name"]) if tour else "队伍阵容"
	_lineup_go.text = "开始锦标赛!" if tour else "开始比赛!"
	for t in ["a", "b"]:
		var col := UIKit.BLUE if t == "a" else UIKit.PINK
		var card := UIKit.panel(Color(1, 1, 1, 0.88), 40, 12)
		_lineup_box.add_child(card)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 12)
		card.add_child(vb)
		var head := Panel.new()
		head.custom_minimum_size = Vector2(620, 64)
		head.add_theme_stylebox_override("panel", UIKit.style_box(col, 32))
		vb.add_child(head)
		var hl := UIKit.label("A 队" if t == "a" else "B 队", 38, Color.WHITE, 8, UIKit.team_dark(0 if t == "a" else 1))
		hl.set_anchors_preset(Control.PRESET_FULL_RECT)
		head.add_child(hl)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 22)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(row)
		for s in 2:
			var id: String = _lineup[t][s]
			var e := Roster.by_id(id)
			var col2 := VBoxContainer.new()
			col2.add_theme_constant_override("separation", 4)
			row.add_child(col2)
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(190, 200)
			btn.add_theme_stylebox_override("normal", UIKit.style_box(Color(0.93, 0.96, 1.0), 30))
			btn.add_theme_stylebox_override("hover", UIKit.style_box(Color(1.0, 0.98, 0.85), 30, 5, UIKit.YELLOW))
			btn.add_theme_stylebox_override("pressed", UIKit.style_box(UIKit.YELLOW, 30))
			btn.add_theme_stylebox_override("focus", UIKit.style_box(Color(1.0, 0.98, 0.85), 30, 5, UIKit.YELLOW))
			var av := UIKit.avatar(id, 150, col, 5)
			av.position = Vector2(20, 12)
			btn.add_child(av)
			var nm := UIKit.label(e["name"], 30, UIKit.INK)
			nm.position = Vector2(0, 160)
			nm.size = Vector2(190, 40)
			btn.add_child(nm)
			var human := _is_human_slot(t, s)
			if human:
				var tag := UIKit.label("玩家", 22, Color.WHITE, 6, UIKit.INK)
				tag.position = Vector2(110, 8)
				tag.size = Vector2(76, 30)
				btn.add_child(tag)
				btn.disabled = false
			elif tour and t == "b":
				var tag3 := UIKit.label("对手", 22, Color.WHITE, 6, UIKit.INK)
				tag3.position = Vector2(110, 8)
				tag3.size = Vector2(76, 30)
				btn.add_child(tag3)
			else:
				var tag2 := UIKit.label("电脑 ⇄", 20, Color.WHITE, 6, UIKit.INK)
				tag2.position = Vector2(94, 8)
				tag2.size = Vector2(92, 30)
				btn.add_child(tag2)
				var tt: String = t
				var ss: int = s
				btn.pressed.connect(func(): _cycle_ai(tt, ss))
			col2.add_child(btn)
			# 3D line-up on court
			var team_i := 0 if t == "a" else 1
			var sgn := 1.0 if team_i == 0 else -1.0
			var px := (-1.9 if s == 0 else 1.9)
			var py := 4.4 if s == 0 else 3.0
			stage.add_rig(e, Vector3(px, 0, py * sgn), 0.0 if team_i == 0 else PI, "ready")


func _start_match() -> void:
	Game.team_a = _lineup["a"].duplicate()
	Game.team_b = _lineup["b"].duplicate()
	Sfx.play("ui_confirm")
	if Game.mode == "tournament":
		Game.tournament_start()
	else:
		Game.start_match()


# ---- SETTINGS
func _build_settings() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(c)
	var pn := UIKit.panel(Color(1, 1, 1, 0.93), 44, 14)
	c.add_child(pn)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	pn.add_child(vb)
	vb.add_child(UIKit.label("设置", 56, UIKit.INK))
	vb.add_child(_row("音乐音量", _slider("music")))
	vb.add_child(_row("音效音量", _slider("sfx")))
	vb.add_child(_row("画面质量", _segmented(["低 (手机)", "中", "高"], Game.settings["quality"], func(i): Game.settings["quality"] = i; Game.save_settings(), 170)))
	vb.add_child(_row("触屏控制", _segmented(["自动", "开启", "关闭"], ["auto", "on", "off"].find(Game.settings["touch"]), func(i):
		Game.settings["touch"] = ["auto", "on", "off"][i]
		Game._detect_touch()
		Game.save_settings(), 170)))
	vb.add_child(_toggle(" 左手模式（触屏按键镜像）", "left_handed"))
	vb.add_child(_toggle(" 镜头震动", "shake"))
	vb.add_child(_toggle(" 触觉震动（手机 / 手柄）", "haptics"))
	vb.add_child(_toggle(" 击球时机提示圈（球上的缩小圆环）", "timing_guide"))
	vb.add_child(_toggle(" 全屏", "fullscreen"))
	var back := UIKit.button("返回", Vector2(300, 70), UIKit.GREEN, 34)
	back.pressed.connect(func(): Game.save_settings(); _show_page("main"))
	vb.add_child(back)
	return root


func _slider(key: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = Game.settings[key]
	s.custom_minimum_size = Vector2(460, 44)
	s.value_changed.connect(func(v):
		Game.settings[key] = v
		Game.apply_settings()
		Sfx.play("ui_hover", -6.0))
	return s


func _toggle(text: String, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = Game.settings[key]
	c.add_theme_font_size_override("font_size", 28)
	for n in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		c.add_theme_color_override(n, UIKit.INK)
	c.toggled.connect(func(v):
		Game.settings[key] = v
		Game.apply_settings()
		Game.save_settings())
	return c


# ---- HOW TO PLAY
func _build_howto() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var title := UIKit.label("操作说明 & 小技巧", 60, Color.WHITE, 14, Color(0.05, 0.2, 0.45, 0.95))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-500, 28)
	title.size = Vector2(1000, 90)
	root.add_child(title)
	var tabs := _segmented(["键盘 + 鼠标", "手柄", "触屏", "规则 & 技巧", "节奏 & 成长"], _how_tab, func(i): _how_tab = i; _refresh_howto(), 230)
	tabs.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tabs.position = Vector2(-620, 130)
	root.add_child(tabs)
	var pn := UIKit.panel(Color(1, 1, 1, 0.93), 40, 14)
	pn.set_anchors_preset(Control.PRESET_CENTER)
	pn.position = Vector2(-760, -300)
	pn.custom_minimum_size = Vector2(1520, 640)
	root.add_child(pn)
	_how_label = RichTextLabel.new()
	_how_label.bbcode_enabled = true
	_how_label.fit_content = false
	_how_label.custom_minimum_size = Vector2(1460, 600)
	_how_label.add_theme_font_size_override("normal_font_size", 29)
	_how_label.add_theme_font_size_override("bold_font_size", 29)
	_how_label.add_theme_color_override("default_color", UIKit.INK)
	pn.add_child(_how_label)
	var back := UIKit.button("返回", Vector2(300, 70), UIKit.GREEN, 34)
	back.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	back.position = Vector2(-150, -110)
	back.pressed.connect(func(): _show_page("main"))
	root.add_child(back)
	_refresh_howto()
	return root


const HOW_TEXT := [
"""[b][color=#1668c9]玩家1[/color][/b]
  移动  [b]W A S D[/b]　　击球（垫球/传球/扣球/发球）  [b]J[/b] 或 [b]鼠标左键[/b]
  跳跃（起跳/拦网）  [b]K[/b] / [b]空格[/b] / [b]鼠标右键[/b]　　扑救  [b]L[/b] / [b]Shift[/b]
  瞄准  [b]鼠标指针[/b] 指向对方场地的落点；单人模式也可用 [b]方向键[/b] 瞄准　　暂停  [b]Esc[/b]

[b][color=#c42473]玩家2（同一键盘）[/color][/b]
  移动  [b]方向键[/b]　　击球  [b]小键盘1[/b] 或 [b],[/b]　　跳跃  [b]小键盘2[/b] 或 [b].[/b]　　扑救  [b]小键盘3[/b] 或 [b]/[/b]
  瞄准  [b]小键盘 8 4 5 6[/b]

[b]击球键是「情境按键」[/b]：球低 → 垫球；球在头顶 → 传球；起跳后 → 扣球；发球时第一次按下抛球，第二次击球。
球很高时直接按击球键，角色会自动起跳去扣球。
""",
"""[b]手柄（P1 = 1 号手柄，P2 = 2 号手柄）[/b]
  移动  [b]左摇杆 / 十字键[/b]　　击球  [b]A[/b] 或 [b]RB / RT[/b]　　跳跃  [b]B[/b] 或 [b]LB[/b]　　扑救  [b]X[/b] 或 [b]LT[/b]
  瞄准  [b]右摇杆[/b]（推向哪里，球就打向对方场地的哪里；松开 = 智能落点）
  暂停  [b]Start[/b]

[b]小提示[/b]
  · 地面上的发光圈是你的「击球范围」，球进入圈内并变亮时按击球键就是 PERFECT。
  · 第一次触球若想直接把球打过网，用右摇杆向前瞄准即可。
""",
"""[b]触屏操作[/b]
  · 屏幕左侧任意位置按住拖动：[b]浮动摇杆[/b] 移动角色
  · 右下角 [b]击球[/b] 大按钮 / [b]跳[/b] / [b]扑[/b]
  · 点击对方半场：设置 [b]落点标记[/b]（击球后自动清除，不点则为智能落点）
  · 设置里可开启 [b]左手模式[/b]（按键镜像）
  · 开启「自动跑位辅助」后，不碰摇杆时角色会自动跑向球的落点，你只需要掌握击球时机！
""",
"""[b]基本规则[/b]
  · 2 对 2，每队最多触球 [b]3 次[/b]（垫 → 传 → 扣），同一人不能连续触球两次。
  · 球落在对方场内得分；出界算最后触球一方失分。先到 [b]7 / 11 / 15[/b] 分且领先 2 分获胜。
  · 得分方发球；换发球权时由队友轮流发球。

[b]小技巧[/b]
  · [b]快速扣球[/b]：在队友完成传球之前就起跳——传球会变成低而快的「QUICK」球，直接送到你手上。
  · [b]拦网[/b]：对方传出高球时，在网前起跳，手臂过网可把球拦回去（KILL BLOCK 直接得分）。
  · [b]扑救[/b]：够不到的低球用扑救键；落点圈会提示球的落点。
  · [b]吊球[/b]：扣球时把瞄准点放在靠近球网的位置，就变成轻轻吊过网。
  · [b]跳发球[/b]：抛球后先按跳跃，在空中击球，球速更快但更难控制。
""",
"""[b]击球节奏 (Nice!)[/b]
  · 球进入击球范围时，球上会出现一个缩小的光圈：圈缩到最小时按下击球键 = [b]Nice![/b]，球更快更准。
  · 连续的 Nice! 会攒满[b]热血条[/b]，进入 [b]热血时刻[/b]：判定更宽、扣球更强、球会拖着火焰！
  · 垫球、传球、扣球三次全是 Nice! = 一记[b]强力扣球[/b]（球色变粉红，几乎拦不住）。

[b]角色特性[/b]  每个角色有一个独门特性（选角色时可见）：有的跑得更快、有的拦网更强，挑一个最适合你的。

[b]别撞人![/b]  跑动中撞到别人会被弹开，撞得很狠还会摔倒、眼冒金星一会儿。AI 同样会撞晕。

[b]成长系统[/b]
  · 每场比赛、每次练习都会获得经验、升级，解锁新的球拖尾 / 比赛用球 / 球场主题，在「生涯」里装备。
  · 每天 3 个随机任务，连续登录提升经验加成；成就收集满 20 个。
  · 「锦标赛」连打三轮（小组赛 → 半决赛 → 决赛），夺冠有大量经验奖励。
  · 「练习场」里的回合挑战可以拿铜 / 银 / 金牌。
"""]


func _refresh_howto() -> void:
	# the rounded UI font has no real bold: emphasise with colour instead
	_how_label.text = (HOW_TEXT[_how_tab] as String).replace("[b]", "[color=#e0307f]").replace("[/b]", "[/color]")

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
var _mode_cards: Control
var _roster: Array[Dictionary] = []
var _lineup := {"a": [], "b": []}
var _how_tab := 0
var _how_label: RichTextLabel
var _rebinding := ""
var _key_rows := {}
var _key_note: Label


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
	if _rebinding != "" and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		var code: int = int((event as InputEventKey).physical_keycode)
		if code == KEY_ESCAPE:
			_cancel_rebind()
		else:
			var swapped := Game.set_key(_rebinding, code)
			_rebinding = ""
			_refresh_key_rows()
			if swapped != "":
				_key_note.text = "该按键原本属于「%s」，两者已互换" % _action_label(swapped)
		return
	if event.is_action_pressed("ui_cancel"):
		_go_back()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:      # Android back button
		_go_back()


func _go_back() -> void:
	if _rebinding != "":
		_cancel_rebind()
		return
	match page:
		"keys", "credits": _show_page("settings")
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
	pages["keys"] = _build_keys()
	pages["credits"] = _build_credits()
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
		cell.add_child(UIKit.label(String(it[1]), 24, Color.WHITE, 9, Color(0.05, 0.12, 0.3, 0.95)))
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
	if Loc.is_en():
		# English: "GoSports" is the logo, "Volleyball" the strap line (the Chinese logo has two words side by side)
		var le := UIKit.label("GoSports", 92, Color.WHITE, 16, Color("1f7a32"))
		le.position = Vector2(20, 4)
		le.size = Vector2(600, 100)
		logo.add_child(le)
		var ls := UIKit.label("VOLLEYBALL", 42, Color("fff3a0"), 10, Color("1f7a32"))
		ls.position = Vector2(20, 92)
		ls.size = Vector2(600, 50)
		logo.add_child(ls)
	else:
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


## a clickable slanted board (profile / mission cards): the Button itself is invisible, a GW.board is drawn under its children
func _board_button(pos: Vector2, size: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = size
	b.focus_mode = Control.FOCUS_ALL
	b.pivot_offset = size * 0.5
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, empty)
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.set_border_width_all(5)
	ring.border_color = UIKit.CHEVRON
	ring.set_corner_radius_all(30)
	b.add_theme_stylebox_override("focus", ring)
	b.add_child(GW.board(size, Color(0.06, 0.2, 0.32, 0.9), Color(1, 1, 1, 0.9), 0.03))
	b.mouse_entered.connect(func(): UIKit._bump(b, 1.03))
	b.mouse_exited.connect(func(): UIKit._bump(b, 1.0))
	b.pressed.connect(func(): Sfx.play("ui_click", -3.0); cb.call())
	return b


func _build_profile_cards(root: Control) -> void:
	var p := Game.profile
	var info := Profile.level_info(p.xp)
	if not p.flags.has("seen_news"):
		p.flags["seen_news"] = _news_count()              # a brand-new profile has nothing "new" yet
	_news_dot.visible = _news_count() > int(p.flags["seen_news"])
	# --- profile card
	var pc := _board_button(Vector2(1370, 36), Vector2(490, 190), func(): _show_page("career"))
	root.add_child(pc)
	var e := Roster.by_id(Game.p1_char)
	var av := UIKit.avatar(Game.p1_char, 124, UIKit.BLUE, 5)
	av.position = Vector2(22, 20)
	pc.add_child(av)
	var nm := UIKit.label(String(e["name"]), 36, Color.WHITE, 8, Color(0.02, 0.1, 0.2, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	nm.position = Vector2(166, 14)
	nm.size = Vector2(300, 46)
	pc.add_child(nm)
	var tt := UIKit.label(String(info["title"]), 26, Color("ffe14a"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	tt.position = Vector2(166, 58)
	tt.size = Vector2(300, 34)
	pc.add_child(tt)
	var lv := UIKit.label("Lv.%d" % int(info["level"]), 44, Color("7fd0ff"), 8, Color(0.02, 0.1, 0.2, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	lv.position = Vector2(166, 92)
	lv.size = Vector2(150, 52)
	pc.add_child(lv)
	var xt := UIKit.label(("%d / %d XP" % [int(info["into"]), int(info["need"])]) if int(info["level"]) < Profile.MAX_LEVEL else "MAX", 22, Color(0.7, 0.85, 0.95), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
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
	pb.add_theme_stylebox_override("background", UIKit.style_box(Color(0.02, 0.1, 0.18, 0.6), 11, 2, Color(1, 1, 1, 0.5)))
	pb.add_theme_stylebox_override("fill", UIKit.style_box(UIKit.GREEN, 11))
	pc.add_child(pb)
	# --- daily missions card
	var mc := _board_button(Vector2(1370, 242), Vector2(490, 250), func(): _show_page("career"))
	root.add_child(mc)
	var mh := UIKit.label("今日任务", 30, Color("8fe9d2"), 6, Color(0.02, 0.1, 0.2, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	mh.position = Vector2(26, 10)
	mh.size = Vector2(200, 44)
	mc.add_child(mh)
	var mn := UIKit.label("%d/%d  ·  连续 %d 天" % [p.missions_done(), p.daily["list"].size(), int(p.daily["streak"])], 22, Color("7dffb0"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
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
		var ml := UIKit.label(String(m["text"]), 23, Color(0.6, 0.74, 0.84) if m["done"] else Color.WHITE, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		ml.position = Vector2(68, y - 4)
		ml.size = Vector2(330, 34)
		mc.add_child(ml)
		var xl := UIKit.label("+%d" % int(m["xp"]), 22, Color("ffe14a"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
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
		mb.add_theme_stylebox_override("background", UIKit.style_box(Color(0.02, 0.1, 0.18, 0.6), 6))
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
	_page_title(root, "练习场", 420.0)
	var p := Game.profile
	var tut_done: bool = p != null and p.flags.get("tutorial_done", false)
	var rbest: int = int(p.flags.get("rally_best", 0)) if p != null else 0
	var medal := Profile.medal_for(rbest)
	var defs := [
		{"id": "training", "name": "新手教学", "col": UIKit.TEAL, "icons": ["act_bump", "act_set", "act_spike"],
			"desc": "教练带你一步步学会\n垫球、传球和扣球\n完成可得 100 经验",
			"status": "已毕业" if tut_done else "推荐新手先来这里"},
		{"id": "rally", "name": "回合挑战", "col": Color("3aa8ff"), "icons": [],
			"desc": "和发球机连续对打\n接球失误 3 次就结束\n铜 10 · 银 25 · 金 50",
			"status": ("最佳 %d 次 (%s)" % [rbest, medal["name"]]) if not medal.is_empty() else ("最佳 %d 次" % rbest)},
	]
	var x := 250.0
	for d in defs:
		var col: Color = d["col"]
		var mid: String = d["id"]
		var b := _board_button(Vector2(x, 210), Vector2(640, 600), func():
			Game.mode = mid
			Sfx.play("ui_confirm", -3.0)
			_show_page("select"))
		root.add_child(b)
		var rb := GW.ribbon(String(d["name"]), 520.0, 104.0, col, 56)
		rb.position = Vector2(60, -26)
		b.add_child(rb)
		var icons: Array = d["icons"]
		if icons.is_empty():
			for i in Profile.MEDALS.size():
				var m: Dictionary = Profile.MEDALS[i]
				var got := rbest >= int(m["goal"])
				var md := Panel.new()
				md.position = Vector2(172.0 + 112.0 * float(i), 150)
				md.size = Vector2(92, 92)
				md.add_theme_stylebox_override("panel", UIKit.style_box(m["color"] if got else Color(0.32, 0.42, 0.5), 46, 5, Color.WHITE, 6))
				md.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(md)
				var mn := UIKit.label(str(int(m["goal"])), 30, Color.WHITE, 8, Color(0.05, 0.12, 0.2, 0.8))
				mn.position = md.position + Vector2(0, 94)
				mn.size = Vector2(92, 36)
				b.add_child(mn)
		else:
			for i in icons.size():
				var disc := Panel.new()
				disc.position = Vector2(150.0 + 130.0 * float(i), 148)
				disc.size = Vector2(104, 104)
				disc.add_theme_stylebox_override("panel", UIKit.style_box(col, 52, 5, Color.WHITE, 6))
				disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(disc)
				var tr := TextureRect.new()
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.texture = load("res://assets/ui/%s.png" % icons[i])
				tr.position = disc.position + Vector2(8, 8)
				tr.size = Vector2(88, 88)
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(tr)
		var dsc := UIKit.label(String(d["desc"]), 31, Color.WHITE)
		dsc.position = Vector2(20, 290)
		dsc.size = Vector2(600, 150)
		b.add_child(dsc)
		var stl := UIKit.label(String(d["status"]), 32, Color("ffe14a") if (not tut_done or d["id"] == "rally") else Color("7dffb0"), 8, Color(0.02, 0.1, 0.2, 0.9))
		stl.position = Vector2(20, 470)
		stl.size = Vector2(600, 60)
		b.add_child(stl)
		x += 700.0
	var back := UIKit.button("返回", Vector2(280, 76), UIKit.PINK, 36)
	back.position = Vector2(70, 900)
	back.pressed.connect(func(): _show_page("main"))
	root.add_child(back)
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
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var blur := ShaderMaterial.new()
	blur.shader = load("res://shaders/ui_blur.gdshader")
	dim.material = blur
	overlay.add_child(dim)
	var card := Control.new()
	card.position = Vector2(440, 250)
	card.size = Vector2(1040, 600)
	overlay.add_child(card)
	card.add_child(GW.board(Vector2(1040, 520), Color(0.93, 0.97, 0.98, 0.97)))
	card.get_child(0).position = Vector2(0, 70)
	var rb := GW.ribbon("欢迎来到排球!", 700.0, 110.0, UIKit.TEAL, 64)
	rb.position = Vector2(170, 0)
	card.add_child(rb)
	var ball := GW.ball_badge(130.0)
	ball.position = Vector2(48, 20)
	card.add_child(ball)
	var d := UIKit.label("第一次玩?  先花 2 分钟跟着教练学会垫球、传球和扣球吧。
完成教学有额外经验奖励,还能解锁更多球拖尾和球场!", 31, UIKit.INK)
	d.position = Vector2(80, 190)
	d.size = Vector2(880, 150)
	card.add_child(d)
	var go := UIKit.button("开始新手教学", Vector2(420, 88), UIKit.GREEN, 40)
	go.position = Vector2(80, 380)
	card.add_child(go)
	var skip := UIKit.button("直接开打", Vector2(420, 88), UIKit.BLUE, 40)
	skip.position = Vector2(540, 380)
	card.add_child(skip)
	var hint := UIKit.label("(随时可以在「练习场」重新进入教学)", 24, Color(0.4, 0.46, 0.58))
	hint.position = Vector2(0, 500)
	hint.size = Vector2(1040, 40)
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
func _segmented(options: Array, current_idx: int, on_change: Callable, width := 150, height := 62, font := 28) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var group := ButtonGroup.new()
	for i in options.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = str(options[i])
		b.custom_minimum_size = Vector2(width, height)
		b.add_theme_font_size_override("font_size", font)
		b.add_theme_color_override("font_color", UIKit.PALE_TXT)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", UIKit.TEAL_DARK)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_focus_color", UIKit.TEAL_DARK)
		b.add_theme_stylebox_override("normal", UIKit.style_box(Color(0.93, 0.97, 0.98), height / 2, 2, Color(1, 1, 1, 0.9), 4))
		b.add_theme_stylebox_override("hover", UIKit.style_box(Color(0.88, 0.95, 0.96), 31, 2, Color.WHITE, 6))
		b.add_theme_stylebox_override("pressed", UIKit.style_box(UIKit.TEAL, 31, 2, Color.WHITE, 4))
		b.add_theme_stylebox_override("hover_pressed", UIKit.style_box(UIKit.TEAL.lightened(0.06), 31, 2, Color.WHITE, 6))
		b.add_theme_stylebox_override("focus", UIKit.style_box(Color(1, 1, 1, 0.0), 31, 4, UIKit.CHEVRON, 0))
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


## frosted-glass side panel used by the mode / match settings page (reference: Choose Players + Match Settings)
func _glass(pos: Vector2, size: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.9, 0.95, 0.97, 0.84), 40, 3, Color(1, 1, 1, 0.9), 14))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## round "player slot": the character's portrait for a human, a grey person glyph for the computer
class _Slot:
	extends Control
	var cpu := true
	var tint := UIKit.BLUE

	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 4.0
		draw_circle(c + Vector2(0, 3), r, Color(0, 0, 0, 0.12))
		draw_circle(c, r, Color(0.96, 0.98, 0.99))
		draw_arc(c, r, 0.0, TAU, 48, tint, 5.0, true)
		var g := Color(0.5, 0.56, 0.62)
		draw_circle(c + Vector2(0, -r * 0.22), r * 0.26, Color(0, 0, 0, 0))
		draw_arc(c + Vector2(0, -r * 0.24), r * 0.24, 0.0, TAU, 24, g, 4.5, true)
		draw_arc(c + Vector2(0, r * 0.62), r * 0.46, PI + 0.35, TAU - 0.35, 20, g, 4.5, true)


func _slot_box(label: String, human_id: String, tint: Color) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(110, 110)
	v.add_child(holder)
	if human_id != "":
		var av := UIKit.avatar(human_id, 104, tint, 5)
		av.position = Vector2(3, 3)
		holder.add_child(av)
	else:
		var s := _Slot.new()
		s.size = Vector2(110, 110)
		s.tint = tint
		holder.add_child(s)
	v.add_child(UIKit.label(label, 26, Color.WHITE, 8, Color(0.05, 0.14, 0.3, 0.95)))
	return v


var _vs_row: HBoxContainer
var _mode_desc: Label


func _build_mode() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page_title(root, "选择模式", 560.0)
	# ---- left: the three modes as big pills straight on the scene (no container)
	var cards := VBoxContainer.new()
	cards.position = Vector2(100, 200)
	cards.add_theme_constant_override("separation", 18)
	root.add_child(cards)
	var modes := [
		["solo", "单人对战", "你 + 电脑队友  VS  电脑二人组"],
		["coop", "双人合作", "两位玩家同一队，一起对战电脑"],
		["versus", "双人对决", "两位玩家各带一名电脑，同屏对抗"],
	]
	for m in modes:
		var b := UIKit.button(String(m[1]), Vector2(560, 92), UIKit.BLUE, 42)
		b.toggle_mode = true
		b.button_group = _mode_group()
		b.button_pressed = (Game.mode == m[0])
		for st in ["pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, UIKit.style_box(UIKit.TEAL, 46, 4, Color.WHITE, 10))
		for n in ["font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(n, Color.WHITE)
		var mid: String = m[0]
		b.pressed.connect(func():
			Game.mode = mid
			Sfx.play("ui_click", -3.0)
			_refresh_mode_cards(cards))
		cards.add_child(b)
	cards.set_meta("modes", modes)
	_mode_cards = cards
	_mode_desc = UIKit.label("", 30, Color.WHITE, 8, Color(0.05, 0.14, 0.3, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	_mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_desc.position = Vector2(110, 520)
	_mode_desc.size = Vector2(540, 120)
	root.add_child(_mode_desc)
	# ---- right: who plays (slots), then the match options as pill rows
	var vs_title := UIKit.label("比赛设置", 44, Color.WHITE, 12, Color(0.05, 0.14, 0.3, 0.95), HORIZONTAL_ALIGNMENT_LEFT)
	vs_title.position = Vector2(860, 196)
	vs_title.size = Vector2(500, 60)
	root.add_child(vs_title)
	_vs_row = HBoxContainer.new()
	_vs_row.position = Vector2(900, 270)
	_vs_row.size = Vector2(840, 150)
	_vs_row.add_theme_constant_override("separation", 22)
	root.add_child(_vs_row)
	var rows := VBoxContainer.new()
	rows.position = Vector2(860, 480)
	rows.add_theme_constant_override("separation", 14)
	root.add_child(rows)
	rows.add_child(GW.row_pill("电脑难度", _segmented(Game.DIFFICULTY_NAMES, int(Game.settings["difficulty"]), func(i): Game.settings["difficulty"] = i; Game.save_settings(), 118, 54, 26), 900.0, 74.0, 240.0))
	rows.add_child(GW.row_pill("比赛分数", _segmented(["7 分", "11 分", "15 分"], [7, 11, 15].find(Game.settings["points"]), func(i): Game.settings["points"] = [7, 11, 15][i]; Game.save_settings(), 140, 54, 26), 900.0, 74.0, 240.0))
	rows.add_child(GW.row_pill("自动跑位辅助", _toggle_plain("assist"), 900.0, 74.0, 500.0))
	rows.add_child(GW.row_pill("精彩回放", _toggle_plain("replays"), 900.0, 74.0, 500.0))
	var nav := HBoxContainer.new()
	nav.position = Vector2(70, 900)
	nav.add_theme_constant_override("separation", 22)
	root.add_child(nav)
	var back := UIKit.button("返回", Vector2(280, 76), UIKit.PINK, 36)
	back.pressed.connect(func(): _show_page("main"))
	nav.add_child(back)
	var next := UIKit.button("选择角色", Vector2(420, 76), UIKit.GREEN, 38)
	next.pressed.connect(func(): _show_page("select"))
	nav.add_child(next)
	_refresh_mode_cards(cards)
	return root


## "label   <  [a | b | c]  >" row: the orange arrows step through the options (like the reference's CPU Strength row)
func _row_arrows(title: String, options: Array, current_idx: int, on_change: Callable, width := 150) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := UIKit.label(title, 32, UIKit.INK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(250, 0)
	h.add_child(l)
	var seg := _segmented(options, maxi(current_idx, 0), on_change, width)
	var step := func(dir: int):
		var idx := 0
		for i in seg.get_child_count():
			if (seg.get_child(i) as Button).button_pressed:
				idx = i
		idx = clampi(idx + dir, 0, seg.get_child_count() - 1)
		(seg.get_child(idx) as Button).button_pressed = true
		Sfx.play("ui_click", -4.0)
		on_change.call(idx)
	for dir in [-1, 1]:
		var ab := Button.new()
		ab.flat = true
		ab.focus_mode = Control.FOCUS_NONE
		ab.text = "◀" if dir < 0 else "▶"
		ab.custom_minimum_size = Vector2(54, 62)
		ab.add_theme_font_size_override("font_size", 30)
		for n in ["font_color", "font_hover_color", "font_pressed_color"]:
			ab.add_theme_color_override(n, UIKit.CHEVRON)
		var d: int = dir
		ab.pressed.connect(func(): step.call(d))
		if dir < 0:
			h.add_child(ab)
			h.add_child(seg)
		else:
			h.add_child(ab)
	return h


func _toggle_plain(key: String) -> Button:
	return UIKit.toggle_pill(bool(Game.settings[key]), func(v):
		Game.settings[key] = v
		Game.save_settings())


var _mode_grp: ButtonGroup


func _mode_group() -> ButtonGroup:
	if _mode_grp == null:
		_mode_grp = ButtonGroup.new()
	return _mode_grp


func _refresh_mode_cards(cards: Control) -> void:
	var modes: Array = cards.get_meta("modes")
	for i in modes.size():
		var b := cards.get_child(i) as Button
		b.set_pressed_no_signal(Game.mode == modes[i][0])
		if Game.mode == modes[i][0] and _mode_desc != null:
			_mode_desc.text = String(modes[i][2])
	if _vs_row == null:
		return
	for c in _vs_row.get_children():
		c.queue_free()
	var p1 := Game.p1_char
	var p2 := Game.p2_char
	var left_team: Array
	var right_team: Array
	match Game.mode:
		"coop":
			left_team = [["玩家1", p1], ["玩家2", p2]]
			right_team = [["电脑", ""], ["电脑", ""]]
		"versus":
			left_team = [["玩家1", p1], ["电脑", ""]]
			right_team = [["玩家2", p2], ["电脑", ""]]
		_:
			left_team = [["你", p1], ["电脑", ""]]
			right_team = [["电脑", ""], ["电脑", ""]]
	for s in left_team:
		_vs_row.add_child(_slot_box(String(s[0]), String(s[1]), UIKit.BLUE))
	var vs := UIKit.label("VS", 66, Color("2fe0c4"), 12, Color.WHITE)
	vs.custom_minimum_size = Vector2(150, 110)
	_vs_row.add_child(vs)
	for s in right_team:
		_vs_row.add_child(_slot_box(String(s[0]), String(s[1]), UIKit.PINK))


# ---- CHARACTER SELECT
func _build_select() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var rb := GW.ribbon("玩家1  选择角色", 800.0, 98.0, UIKit.TEAL, 52)
	rb.position = Vector2(60, 28)
	root.add_child(rb)
	_sel_header = rb.get_child(0) as Label
	# character grid on a dark slanted board
	var board := GW.board(Vector2(1000, 760), Color(0.06, 0.2, 0.32, 0.86), Color(1, 1, 1, 0.9), 0.02)
	board.position = Vector2(46, 140)
	root.add_child(board)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 30)
	scroll.size = Vector2(930, 700)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	board.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	_grid_buttons.clear()
	for i in _roster.size():
		var e := _roster[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 166)
		b.focus_mode = Control.FOCUS_ALL
		b.pivot_offset = Vector2(75, 83)
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "pressed"]:
			b.add_theme_stylebox_override(st, empty)
		var ring := UIKit.style_box(Color(1.0, 0.9, 0.35, 0.18), 30, 5, UIKit.YELLOW)
		for st in ["hover", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(st, ring)
		var av := UIKit.avatar(e["id"], 106, UIKit.BLUE if e["kind"] == "cube" else Color("8e3dff"), 5)
		av.position = Vector2(22, 8)
		b.add_child(av)
		var nm := UIKit.label(e["name"], 25, Color.WHITE, 6, Color(0.02, 0.1, 0.2, 0.9))
		nm.position = Vector2(0, 118)
		nm.size = Vector2(150, 40)
		b.add_child(nm)
		var idx := i
		b.mouse_entered.connect(func(): _preview(idx); UIKit._bump(b, 1.06))
		b.mouse_exited.connect(func(): UIKit._bump(b, 1.0))
		b.focus_entered.connect(func(): _preview(idx); Sfx.play("ui_hover", -9.0); UIKit._bump(b, 1.06))
		b.focus_exited.connect(func(): UIKit._bump(b, 1.0))
		b.pressed.connect(func(): _confirm_pick(idx))
		grid.add_child(b)
		_grid_buttons.append(b)
	# info board
	var info := GW.board(Vector2(860, 270), Color(0.06, 0.2, 0.32, 0.9), Color(1, 1, 1, 0.9), 0.04)
	info.position = Vector2(1020, 690)
	root.add_child(info)
	var iv := VBoxContainer.new()
	iv.position = Vector2(54, 16)
	iv.size = Vector2(780, 240)
	iv.add_theme_constant_override("separation", 6)
	info.add_child(iv)
	_sel_name = UIKit.label("", 50, Color.WHITE, 10, Color(0.02, 0.1, 0.2, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	iv.add_child(_sel_name)
	_sel_blurb = UIKit.label("", 28, Color(0.72, 0.86, 0.95), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	iv.add_child(_sel_blurb)
	_sel_perk = UIKit.label("", 26, Color("ffe14a"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	iv.add_child(_sel_perk)
	_sel_bars.clear()
	for t in [["速度", UIKit.BLUE], ["弹跳", UIKit.GREEN], ["力量", UIKit.PINK]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		var tl := UIKit.label(t[0], 26, Color.WHITE, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		tl.custom_minimum_size = Vector2(90, 0)
		h.add_child(tl)
		var pb := ProgressBar.new()
		pb.min_value = 0.8
		pb.max_value = 1.2
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(560, 22)
		pb.add_theme_stylebox_override("background", UIKit.style_box(Color(0.02, 0.1, 0.18, 0.6), 11, 2, Color(1, 1, 1, 0.5)))
		pb.add_theme_stylebox_override("fill", UIKit.style_box(t[1], 11))
		h.add_child(pb)
		iv.add_child(h)
		_sel_bars.append(pb)
	# buttons
	var back := UIKit.button("返回", Vector2(280, 76), UIKit.PINK, 36)
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.position = Vector2(60, -110)
	back.pressed.connect(_select_back)
	root.add_child(back)
	var rnd := UIKit.button("随机", Vector2(280, 76), UIKit.BLUE, 36)
	rnd.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	rnd.position = Vector2(370, -110)
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
	var rb := GW.ribbon("队伍阵容", 760.0, 98.0, UIKit.TEAL, 54)
	rb.position = Vector2(70, 40)
	root.add_child(rb)
	_lineup_title = rb.get_child(0) as Label
	_lineup_box = HBoxContainer.new()
	_lineup_box.set_anchors_preset(Control.PRESET_CENTER)
	_lineup_box.position = Vector2(-760, -280)
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
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(700, 430)
		_lineup_box.add_child(holder)
		var card := GW.board(Vector2(700, 410), col.darkened(0.5) * Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.9), 0.025)
		card.position = Vector2(0, 20)
		holder.add_child(card)
		var head := GW.ribbon("A 队" if t == "a" else "B 队", 300.0, 88.0, col, 46)
		head.position = Vector2(200, -4)
		holder.add_child(head)
		for s in 2:
			var id: String = _lineup[t][s]
			var e := Roster.by_id(id)
			var btn := Button.new()
			btn.position = Vector2(120.0 + 250.0 * float(s), 120)
			btn.size = Vector2(210, 260)
			btn.focus_mode = Control.FOCUS_ALL
			btn.pivot_offset = btn.size * 0.5
			var empty := StyleBoxEmpty.new()
			for st in ["normal", "pressed"]:
				btn.add_theme_stylebox_override(st, empty)
			var ring := UIKit.style_box(Color(1.0, 0.9, 0.35, 0.16), 34, 5, UIKit.YELLOW)
			for st in ["hover", "focus", "hover_pressed"]:
				btn.add_theme_stylebox_override(st, ring)
			var av := UIKit.avatar(id, 164, col, 6)
			av.position = Vector2(23, 14)
			btn.add_child(av)
			var nm := UIKit.label(e["name"], 32, Color.WHITE, 8, Color(0.02, 0.1, 0.2, 0.9))
			nm.position = Vector2(0, 186)
			nm.size = Vector2(210, 44)
			btn.add_child(nm)
			var human := _is_human_slot(t, s)
			var tag_text := ""
			var tag_col := Color(0.2, 0.3, 0.42)
			if human:
				tag_text = "玩家"
				tag_col = UIKit.TEAL
			elif tour and t == "b":
				tag_text = "对手"
			else:
				tag_text = "电脑 ⇄"
				var tt: String = t
				var ss: int = s
				btn.pressed.connect(func(): _cycle_ai(tt, ss))
			var chip := Panel.new()
			chip.position = Vector2(54, 228)
			chip.size = Vector2(102, 32)
			chip.add_theme_stylebox_override("panel", UIKit.style_box(tag_col, 16, 2, Color.WHITE))
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(chip)
			var cl := UIKit.label(tag_text, 20, Color.WHITE)
			cl.size = chip.size
			chip.add_child(cl)
			btn.mouse_entered.connect(func(): UIKit._bump(btn, 1.04))
			btn.mouse_exited.connect(func(): UIKit._bump(btn, 1.0))
			holder.add_child(btn)
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
func _row_ctl(title: String, control: Control, w := 900.0) -> Control:
	return GW.row_pill(title, control, w, 74.0, 300.0)


func _page_title(root: Control, text: String, width := 560.0) -> void:
	var rb := GW.ribbon(text, width, 98.0, UIKit.TEAL, 56)
	rb.position = Vector2(70, 40)
	root.add_child(rb)


func _build_settings() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page_title(root, "设置")
	var left := VBoxContainer.new()
	left.position = Vector2(70, 190)
	left.add_theme_constant_override("separation", 14)
	root.add_child(left)
	var right := VBoxContainer.new()
	right.position = Vector2(1000, 190)
	right.add_theme_constant_override("separation", 14)
	root.add_child(right)
	left.add_child(_row_ctl("音乐音量", GW.slider(float(Game.settings["music"]), func(v): Game.settings["music"] = v; Game.apply_settings(); Sfx.play("ui_hover", -6.0), 520.0), 880.0))
	left.add_child(_row_ctl("音效音量", GW.slider(float(Game.settings["sfx"]), func(v): Game.settings["sfx"] = v; Game.apply_settings(); Sfx.play("ui_hover", -6.0), 520.0), 880.0))
	left.add_child(_row_ctl("Language / 语言", _segmented(Loc.LANG_NAMES, maxi(Loc.LANGS.find(String(Game.settings["language"])), 0), func(i):
		Game.settings["language"] = Loc.LANGS[i]
		Game.save_settings()
		Loc.apply(String(Loc.LANGS[i]))
		Game.goto("menu", {"page": "settings"}), 160, 54, 24), 880.0))
	left.add_child(_row_ctl("画面质量", _segmented(["低 (手机)", "中", "高"], Game.settings["quality"], func(i): Game.settings["quality"] = i; Game.save_settings(), 150, 54, 24), 880.0))
	left.add_child(_row_ctl("触屏控制", _segmented(["自动", "开启", "关闭"], ["auto", "on", "off"].find(Game.settings["touch"]), func(i):
		Game.settings["touch"] = ["auto", "on", "off"][i]
		Game._detect_touch()
		Game.save_settings(), 150, 54, 24), 880.0))
	left.add_child(_row_ctl("落点提示", _segmented(["关闭", "简洁", "标准"], int(Game.settings["landing_hint"]), func(i): Game.settings["landing_hint"] = i; Game.settings["landing_hint_set"] = true; Game.save_settings(), 150, 54, 24), 880.0))
	for t in [["击球时机提示圈", "timing_guide"], ["镜头震动", "shake"], ["触觉震动（手机 / 手柄）", "haptics"], ["左手模式（触屏按键镜像）", "left_handed"], ["全屏", "fullscreen"]]:
		var key: String = t[1]
		right.add_child(GW.row_pill(String(t[0]), UIKit.toggle_pill(bool(Game.settings[key]), func(v):
			Game.settings[key] = v
			Game.apply_settings()
			Game.save_settings()), 780.0, 74.0, 600.0))
	var nav := HBoxContainer.new()
	nav.position = Vector2(70, 900)
	nav.add_theme_constant_override("separation", 22)
	root.add_child(nav)
	var back := UIKit.button("返回", Vector2(280, 76), UIKit.GREEN, 36)
	back.pressed.connect(func(): Game.save_settings(); _show_page("main"))
	nav.add_child(back)
	var keys_btn := UIKit.button("按键设置", Vector2(300, 76), UIKit.BLUE, 34)
	keys_btn.pressed.connect(func(): _show_page("keys"))
	nav.add_child(keys_btn)
	var credits_btn := UIKit.button("制作与素材", Vector2(320, 76), UIKit.BLUE, 34)
	credits_btn.pressed.connect(func(): _show_page("credits"))
	nav.add_child(credits_btn)
	return root


# ---- CREDITS
const CREDITS := [
	["引擎", "Godot Engine 4.7 (MIT)"],
	["角色 / 忍者", "Cubebrush「Simple Character Pack」及忍者模型（开发者提供的素材包）"],
	["球场 / 体育场", "「低面体育场套件」(4182) 及开发者提供的球模型"],
	["音效 / 音乐", "全部为程序合成（tools/gen_audio.py）"],
	["图标", "程序绘制，部分动作图标由 Gemini 生成后抠图"],
	["界面字体", "字魂趣圆黑（试用版，商用前需替换为已授权字体）"],
	["灵感", "界面节奏与操作提示的参考来自「任天堂 Switch Sports」排球的公开演示；所有素材均为原创实现，不使用任何官方资源"],
]


func _build_credits() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page_title(root, "制作与素材", 640.0)
	var bd := GW.board(Vector2(1640, 640), Color(0.07, 0.17, 0.3, 0.86), Color(1, 1, 1, 0.85))
	bd.position = Vector2(140, 200)
	root.add_child(bd)
	var y := 44.0
	for e in CREDITS:
		var k := UIKit.label(String(e[0]), 30, Color("8fe9d2"), 6, Color(0.02, 0.1, 0.2, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
		k.position = Vector2(150, y)
		k.size = Vector2(300, 44)
		bd.add_child(k)
		var v := UIKit.label(String(e[1]), 26, Color.WHITE, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		v.position = Vector2(430, y + 2.0)
		v.size = Vector2(1100, 70)
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		bd.add_child(v)
		y += 80.0 if String(e[1]).length() > 56 else 66.0
	var back := UIKit.button("返回", Vector2(280, 76), UIKit.GREEN, 36)
	back.position = Vector2(70, 900)
	back.pressed.connect(func(): _show_page("settings"))
	root.add_child(back)
	return root


# ---- KEY BINDINGS (P1 keyboard)
func _action_label(act: String) -> String:
	for r in Game.REBINDABLE:
		if "p1_" + String(r[0]) == act:
			return String(r[1])
	return act


func _build_keys() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page_title(root, "按键设置 (玩家1 键盘)", 860.0)
	var sub := UIKit.label("点一下按键，再按想要的新按键；Esc 取消。鼠标：左键击球，右键跳跃（固定）", 28, Color.WHITE, 8, Color(0.05, 0.14, 0.3, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	sub.position = Vector2(80, 158)
	sub.size = Vector2(1500, 44)
	root.add_child(sub)
	var col := VBoxContainer.new()
	col.position = Vector2(70, 230)
	col.add_theme_constant_override("separation", 12)
	root.add_child(col)
	_key_rows.clear()
	for r in Game.REBINDABLE:
		var act := "p1_" + String(r[0])
		var b := UIKit.button("", Vector2(260, 56), UIKit.BLUE, 32)
		var cap := UIKit.style_box(Color.WHITE, 14, 4, UIKit.TEAL, 6)
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(st, cap)
		for n in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(n, UIKit.INK)
		b.add_theme_constant_override("outline_size", 0)
		b.pressed.connect(func(): _begin_rebind(act))
		col.add_child(GW.row_pill(String(r[1]), b, 880.0, 72.0, 420.0))
		_key_rows[act] = b
	_key_note = UIKit.label("", 28, Color("ffe14a"), 8, Color(0.4, 0.2, 0.0, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	_key_note.position = Vector2(80, 830)
	_key_note.size = Vector2(1500, 44)
	root.add_child(_key_note)
	var nav := HBoxContainer.new()
	nav.position = Vector2(70, 900)
	nav.add_theme_constant_override("separation", 22)
	root.add_child(nav)
	var back := UIKit.button("返回", Vector2(280, 76), UIKit.GREEN, 36)
	back.pressed.connect(func(): _cancel_rebind(); _show_page("settings"))
	nav.add_child(back)
	var reset := UIKit.button("恢复默认", Vector2(320, 76), UIKit.BLUE, 34)
	reset.pressed.connect(func():
		Game.reset_keys()
		_key_note.text = "已恢复默认按键"
		_refresh_key_rows())
	nav.add_child(reset)
	_refresh_key_rows()
	return root


func _refresh_key_rows() -> void:
	for act in _key_rows.keys():
		var b: Button = _key_rows[act]
		b.text = "按下新按键…" if act == _rebinding else Game.key_name(act)


func _begin_rebind(act: String) -> void:
	_rebinding = act
	_key_note.text = ""
	_refresh_key_rows()


func _cancel_rebind() -> void:
	if _rebinding != "":
		_rebinding = ""
		_refresh_key_rows()


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


func _toggle(text: String, key: String) -> HBoxContainer:
	return UIKit.toggle_row(text.strip_edges(), bool(Game.settings[key]), func(v):
		Game.settings[key] = v
		Game.apply_settings()
		Game.save_settings(), 640, 28)


# ---- HOW TO PLAY
func _build_howto() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var title := UIKit.label("操作说明 & 小技巧", 60, Color.WHITE, 14, Color(0.05, 0.2, 0.45, 0.95))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-500, 28)
	title.size = Vector2(1000, 90)
	root.add_child(title)
	var tw := 290 if Loc.is_en() else 230
	var tabs := _segmented(["键盘 + 鼠标", "手柄", "触屏", "规则 & 技巧", "节奏 & 成长"], _how_tab, func(i): _how_tab = i; _refresh_howto(), tw)
	tabs.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tabs.position = Vector2(-(float(tw) * 5.0 + 40.0) * 0.5, 130)
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
	_how_label.text = Loc.howto(_how_tab, HOW_TEXT[_how_tab] as String).replace("[b]", "[color=#e0307f]").replace("[/b]", "[/color]")

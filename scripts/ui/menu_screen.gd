extends Node
## Title screen hub: main menu, mode/options, my character (loadout), settings and how-to-play.

var stage: Stage
var ui: CanvasLayer
var pages: Dictionary = {}
var page := ""
var _fade_rect: ColorRect

# loadout page (my character)
var _preview_rig: CharacterRig = null
var _preview_idx := -1
var _lo_slot := "p1"
var _lo_return := "main"
var _lo_tiles: Array[Button] = []
var _lo_chips := {}               # slot -> Button
var _lo_rand: Control
var _lo_rand_pill: Button
var _lo_note: Label
var _lo_note_tw: Tween
var _sel_name: Label
var _sel_blurb: Label
var _sel_perk: Label
var _sel_state: Label
var _sel_bars: Array[ProgressBar] = []
var _mode_cards: Control
var _roster: Array[Dictionary] = []
var _lineup := {"a": [], "b": []}
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
	if start == "select":
		start = "loadout"                     # (old name, still used by dev flags and the results screen)
	if start == "lineup":                     # dev: --page=lineup [--autostart] builds the teams from the loadout and starts
		_make_lineup()
		start = "main"
	_show_page(start, true)
	_maybe_welcome()
	_maybe_daily_greeting()
	if Game.main != null and Game.main.dev.has("lotest"):
		_lo_selftest()
	if Game.main != null and Game.main.dev.has("autostart") and Game.main.dev.get("page", "") == "lineup":
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
		"loadout": _show_page(_lo_return)


# ------------------------------------------------------------------ pages
func _build_pages() -> void:
	pages["main"] = _build_main()
	pages["mode"] = _build_mode()
	pages["loadout"] = _build_loadout()
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
			stage.add_rig(Roster.by_id(Game.partner_char if Game.partner_char != "" else Game.p2_char), Vector3(3.9, 0, 4.2), PI + 0.15, "cheer")
			stage.add_rig(Roster.by_id("ninja_red"), Vector3(-2.2, 0, -1.8), 0.0, "ready")
			stage.add_rig(Roster.by_id("snow"), Vector3(-3.4, 0, -2.6), 0.3, "ready")
			(pages["main"].get_node("Buttons").get_child(0) as Control).grab_focus()
		"mode":
			if not ["solo", "coop", "versus"].has(Game.mode):
				Game.mode = "solo"
			_refresh_mode_cards(_mode_cards)
			var st: Node = pages["mode"].find_child("Start", true, false)
			if st != null:
				(st as Control).call_deferred("grab_focus")
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
		"loadout":
			_lo_enter()
		"settings":
			stage.look(Vector3(0.0, 4.0, 13.0), Vector3(0, 0.8, 0))
		"howto":
			stage.look(Vector3(0.0, 5.0, 12.0), Vector3(0, 0.8, -1))
			(pages["howto"] as HowToPage).focus_first()


func _bg_dim() -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0.1, 0.2, 0.4, 0.0)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


# ---- MAIN
var _news_dot: Control
var _lo_dot: Control
var _welcome_shown := false
var _career: CareerPage


## three swoosh lines with dots under the logo (like the reference title screen)
class _Swoosh:
	extends Control

	func _draw() -> void:
		var cols := [Color("37d3d6"), Color("e65bdc"), Color("3b7cff")]
		for i in 3:
			var y := 10.0 + float(i) * 14.0
			var x1 := size.x * (0.78 - 0.14 * float(i))
			var pts := PackedVector2Array()
			for k in 25:
				var t := float(k) / 24.0
				pts.append(Vector2(lerpf(0.0, x1, t), y - sin(t * PI) * 5.0 - t * 6.0))
			draw_polyline(pts, cols[i], 5.0, true)
			draw_circle(pts[pts.size() - 1], 6.0, cols[i])


func _build_main() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# pale veil on the left so the menu reads like the reference's airy title screen, whatever is behind it
	var veil := TextureRect.new()
	var gt := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.93, 0.97, 0.99, 0.80))
	grad.set_color(1, Color(0.93, 0.97, 0.99, 0.0))
	gt.gradient = grad
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 8
	veil.texture = gt
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.anchor_right = 0.56
	veil.anchor_bottom = 1.0
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(veil)
	# logo
	var logo := Control.new()
	logo.position = Vector2(90, 14)
	root.add_child(logo)
	var l1 := UIKit.label("Go", 120, Color("20b9a8"), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	l1.position = Vector2(0, 0)
	l1.size = Vector2(190, 140)
	l1.rotation = deg_to_rad(-4.0)
	logo.add_child(l1)
	var l2 := UIKit.label("Sports", 120, Color("1b86d9"), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	l2.position = Vector2(176, 0)
	l2.size = Vector2(470, 140)
	l2.rotation = deg_to_rad(-4.0)
	logo.add_child(l2)
	var strap := UIKit.label("VOLLEYBALL" if Loc.is_en() else "排球  ·  VOLLEYBALL", 34, Color("1d6a70"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	strap.position = Vector2(24, 150)
	strap.size = Vector2(560, 44)
	logo.add_child(strap)
	var sw := _Swoosh.new()
	sw.position = Vector2(-64, 190)
	sw.size = Vector2(760, 50)
	logo.add_child(sw)
	# the entries: tilted pills, selected = teal + stripes
	var vb := Control.new()
	vb.name = "Buttons"
	root.add_child(vb)
	var entries := [
		["开始比赛", "单人 · 双人合作 · 双人对决", "ball", "1-2", func(): _show_page("mode")],
		["锦标赛", "三轮淘汰赛，夺冠拿大量经验", "cup", "1", func():
			Game.mode = "tournament"
			_start_game()],
		["练习场", "新手教学 · 回合挑战", "target", "1", func(): _show_page("practice")],
		["我的角色", "角色 · 队友 · 随时更换", "person", "", func(): _open_loadout("p1", "main")],
		["生涯", "等级 · 装扮 · 成就 · 每日任务", "star", "", func(): _show_page("career")],
	]
	var y := 250.0
	var first := true
	for e in entries:
		var en := MenuEntry.new().build(String(e[0]), String(e[1]), String(e[2]), Vector2(700 if first else 660, 124 if first else 104), "dark", String(e[3]), 3.5, 46 if first else 40)
		en.position = Vector2(112.0 - (0.0 if first else 0.0), y)
		var cb: Callable = e[4]
		en.chosen.connect(cb)
		vb.add_child(en)
		if String(e[0]) == "生涯":
			en.add_badge()
			_news_dot = en._badge
		elif String(e[0]) == "我的角色" and Game.profile != null and not Game.profile.flags.get("loadout_seen", false):
			en.add_badge()                         # a red dot until the player has opened the loadout once
			_lo_dot = en._badge
		y += 136.0 if first else 118.0
		first = false
	# small entries
	var small_y := y + 14.0
	var smalls := [["操作说明", "bulb", func(): _show_page("howto")], ["设置", "gear", func(): _show_page("settings")]]
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		smalls.append(["退出", "door", func(): get_tree().quit()])
	var sx := 112.0
	for e in smalls:
		var sm := MenuEntry.new().build(String(e[0]), "", String(e[1]), Vector2(212, 78), "pale", "", 3.5, 30)
		sm.position = Vector2(sx, small_y)
		sm.chosen.connect(e[2])
		vb.add_child(sm)
		sx += 232.0
	if not OS.has_feature("mobile"):
		var foot := UIKit.label("F11 全屏", 22, Color(0.2, 0.4, 0.46), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
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
	# --- profile pill (top right, anchored so wide phone screens keep it at the edge)
	var pc := Button.new()
	pc.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pc.size = Vector2(560, 132)
	pc.position = Vector2(-560.0 - 50.0, 40.0)
	pc.focus_mode = Control.FOCUS_ALL
	pc.pivot_offset = pc.size * 0.5
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		pc.add_theme_stylebox_override(st, empty)
	var pbg := GW.pill_bg(pc.size, 66.0, MenuEntry.SLATE, 0.0)
	pbg.show_behind_parent = true
	pc.add_child(pbg)
	pc.pressed.connect(func(): Sfx.play("ui_click", -3.0); _show_page("career"))
	pc.mouse_entered.connect(func(): UIKit._bump(pc, 1.03))
	pc.mouse_exited.connect(func(): UIKit._bump(pc, 1.0))
	pc.focus_entered.connect(func(): UIKit._bump(pc, 1.03))
	pc.focus_exited.connect(func(): UIKit._bump(pc, 1.0))
	root.add_child(pc)
	var e := Roster.by_id(Game.p1_char)
	var av := UIKit.avatar(Game.p1_char, 108, UIKit.BLUE, 5)
	av.position = Vector2(14, 12)
	pc.add_child(av)
	var nm := UIKit.label(String(e["name"]), 34, Color.WHITE, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	nm.position = Vector2(140, 12)
	nm.size = Vector2(260, 42)
	pc.add_child(nm)
	var tt := UIKit.label(String(info["title"]), 22, Color("ffe14a"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	tt.position = Vector2(140, 52)
	tt.size = Vector2(260, 30)
	pc.add_child(tt)
	var lvp := Panel.new()
	lvp.position = Vector2(412, 20)
	lvp.size = Vector2(130, 46)
	lvp.add_theme_stylebox_override("panel", UIKit.style_box(UIKit.TEAL, 23, 3, Color.WHITE))
	lvp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(lvp)
	var lv := UIKit.label("Lv.%d" % int(info["level"]), 28, Color.WHITE, 6, Color(0.02, 0.35, 0.36, 0.7))
	lv.size = lvp.size
	lvp.add_child(lv)
	var xt := UIKit.label(("%d / %d XP" % [int(info["into"]), int(info["need"])]) if int(info["level"]) < Profile.MAX_LEVEL else "MAX", 20, Color(0.78, 0.9, 0.94), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	xt.position = Vector2(380, 66)
	xt.size = Vector2(160, 28)
	pc.add_child(xt)
	var pb := ProgressBar.new()
	pb.position = Vector2(140, 94)
	pb.size = Vector2(400, 20)
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.value = float(info["ratio"])
	pb.show_percentage = false
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.add_theme_stylebox_override("background", UIKit.style_box(Color(0.02, 0.1, 0.18, 0.55), 10, 2, Color(1, 1, 1, 0.55)))
	pb.add_theme_stylebox_override("fill", UIKit.style_box(Color("ffb02e"), 10))
	pc.add_child(pb)
	# --- daily missions: frosted glass panel under it
	var mc := Button.new()
	mc.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mc.size = Vector2(560, 268)
	mc.position = Vector2(-560.0 - 50.0, 196.0)
	mc.focus_mode = Control.FOCUS_ALL
	mc.pivot_offset = mc.size * 0.5
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		mc.add_theme_stylebox_override(st, empty)
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.set_border_width_all(5)
	ring.border_color = UIKit.CHEVRON
	ring.set_corner_radius_all(36)
	mc.add_theme_stylebox_override("focus", ring)
	root.add_child(mc)
	mc.add_child(GW.frost(mc.size, 36.0))
	mc.pressed.connect(func(): Sfx.play("ui_click", -3.0); _show_page("career"))
	mc.mouse_entered.connect(func(): UIKit._bump(mc, 1.02))
	mc.mouse_exited.connect(func(): UIKit._bump(mc, 1.0))
	var mh := UIKit.label("今日任务", 30, UIKit.PALE_TXT, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	mh.position = Vector2(30, 14)
	mh.size = Vector2(200, 44)
	mc.add_child(mh)
	var mn := UIKit.label("%d/%d  ·  连续 %d 天" % [p.missions_done(), p.daily["list"].size(), int(p.daily["streak"])], 22, UIKit.TEAL_DARK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	mn.position = Vector2(250, 18)
	mn.size = Vector2(280, 36)
	mc.add_child(mn)
	var rule := ColorRect.new()
	rule.color = Color(UIKit.TEAL.r, UIKit.TEAL.g, UIKit.TEAL.b, 0.8)
	rule.position = Vector2(30, 60)
	rule.size = Vector2(500, 3)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(rule)
	for i in p.daily["list"].size():
		var m: Dictionary = p.daily["list"][i]
		var yy := 76.0 + float(i) * 62.0
		var ck := _MiniDot.new()
		ck.position = Vector2(28, yy + 6)
		ck.size = Vector2(32, 32)
		ck.on = bool(m["done"])
		ck.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mc.add_child(ck)
		var ml := UIKit.label(String(m["text"]), 23, Color(0.45, 0.58, 0.64) if m["done"] else UIKit.INK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		ml.position = Vector2(74, yy - 6)
		ml.size = Vector2(350, 34)
		mc.add_child(ml)
		var xl := UIKit.label("+%d" % int(m["xp"]), 22, Color("e0782a"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		xl.position = Vector2(440, yy - 6)
		xl.size = Vector2(92, 34)
		mc.add_child(xl)
		var mb := ProgressBar.new()
		mb.position = Vector2(74, yy + 30)
		mb.size = Vector2(458, 12)
		mb.min_value = 0.0
		mb.max_value = 1.0
		mb.value = clampf(float(m["progress"]) / float(m["goal"]), 0.0, 1.0)
		mb.show_percentage = false
		mb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mb.add_theme_stylebox_override("background", UIKit.style_box(Color(0.7, 0.8, 0.84, 0.7), 6))
		mb.add_theme_stylebox_override("fill", UIKit.style_box(UIKit.TEAL, 6))
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
	_page_title(root, "练习场", 420.0, "target")
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
			_start_game())
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
	if p == null or not p.new_day or _welcome_shown or page != "main":
		return
	p.new_day = false
	var vp := ui.get_viewport().get_visible_rect().size
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
		_start_game())
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


## one avatar of the VS row; with a `slot` ("p1" / "p2" / "partner") it is a button that opens the loadout page
func _slot_box(label: String, human_id: String, tint: Color, slot := "") -> Control:
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
	if slot != "":
		var b := Button.new()
		b.size = Vector2(110, 110)
		b.focus_mode = Control.FOCUS_ALL
		b.pivot_offset = b.size * 0.5
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "pressed"]:
			b.add_theme_stylebox_override(st, empty)
		var ring := UIKit.style_box(Color(1, 1, 1, 0.0), 55, 5, UIKit.TEAL_DARK)
		for st in ["hover", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(st, ring)
		b.pressed.connect(func():
			Sfx.play("ui_click", -3.0)
			_open_loadout(slot, "mode"))
		b.mouse_entered.connect(func(): UIKit._bump(b, 1.06))
		b.mouse_exited.connect(func(): UIKit._bump(b, 1.0))
		b.focus_entered.connect(func(): UIKit._bump(b, 1.06))
		b.focus_exited.connect(func(): UIKit._bump(b, 1.0))
		holder.add_child(b)
		var badge := Panel.new()
		badge.position = Vector2(76, 74)
		badge.size = Vector2(34, 34)
		badge.add_theme_stylebox_override("panel", UIKit.style_box(UIKit.TEAL, 17, 3, Color.WHITE, 4))
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bl := UIKit.label("⇄", 20, Color.WHITE)
		bl.set_anchors_preset(Control.PRESET_FULL_RECT)
		badge.add_child(bl)
		holder.add_child(badge)
	v.add_child(UIKit.label(label, 26, UIKit.INK))
	return v


var _vs_row: HBoxContainer
var _mode_desc: Label


func _build_mode() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var hd := GW.header("选择模式", "ball", 880.0)
	hd.position = Vector2(70, 34)
	root.add_child(hd)
	# ---- left: the three modes (chosen = teal)
	var cards := Control.new()
	root.add_child(cards)
	var modes := [
		["solo", "单人对战", "你 + 电脑队友  VS  电脑二人组", "person"],
		["coop", "双人合作", "两位玩家同一队，一起对战电脑", "person"],
		["versus", "双人对决", "两位玩家各带一名电脑，同屏对抗", "person"],
	]
	var y := 190.0
	for m in modes:
		var en := MenuEntry.new().build(String(m[1]), String(m[2]), String(m[3]), Vector2(700, 118), "pale", "", 2.0, 40)
		en.position = Vector2(110, y)
		var mid: String = m[0]
		en.chosen.connect(func():
			Game.mode = mid
			_refresh_mode_cards(cards))
		en.focus_entered.connect(func():
			Game.mode = mid
			_refresh_mode_cards(cards))
		cards.add_child(en)
		y += 140.0
	cards.set_meta("modes", modes)
	_mode_cards = cards
	_mode_desc = null
	_venue_row = Control.new()
	root.add_child(_venue_row)
	_fill_venue_row()
	# ---- right: match settings on frosted glass
	var hd2 := GW.header("比赛设置", "ball", 920.0, 48)
	hd2.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hd2.position = Vector2(-920.0 - 60.0, 34)
	root.add_child(hd2)
	var panel := GW.frost(Vector2(920, 650), 40.0)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-920.0 - 60.0, 160)
	root.add_child(panel)
	_vs_row = HBoxContainer.new()
	_vs_row.position = Vector2(110, 26)
	_vs_row.size = Vector2(700, 150)
	_vs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_vs_row.add_theme_constant_override("separation", 22)
	panel.add_child(_vs_row)
	var rows := VBoxContainer.new()
	rows.position = Vector2(0, 214)
	rows.size = Vector2(920, 420)
	rows.add_theme_constant_override("separation", 16)
	panel.add_child(rows)
	var wrap := func(c: Control) -> Control:
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(c)
		return h
	rows.add_child(wrap.call(GW.option_row("电脑难度", Game.DIFFICULTY_NAMES, int(Game.settings["difficulty"]), func(i): Game.settings["difficulty"] = i; Game.save_settings(), 860.0, 150.0)))
	rows.add_child(wrap.call(GW.option_row("比赛分数", ["7 分", "11 分", "15 分"], maxi([7, 11, 15].find(Game.settings["points"]), 0), func(i): Game.settings["points"] = [7, 11, 15][i]; Game.save_settings(), 860.0, 150.0)))
	rows.add_child(wrap.call(GW.option_row("自动跑位辅助", ["关", "开"], 1 if Game.settings["assist"] else 0, func(i): Game.settings["assist"] = i == 1; Game.save_settings(), 860.0, 150.0)))
	rows.add_child(wrap.call(GW.option_row("精彩回放", ["关", "开"], 1 if Game.settings["replays"] else 0, func(i): Game.settings["replays"] = i == 1; Game.save_settings(), 860.0, 150.0)))
	# ---- the one big action of this page: START (bottom right, where the eye ends up), pulsing, focused by default
	var next := UIKit.button("开始游戏", Vector2(560, 110), UIKit.GREEN, 54)
	next.name = "Start"
	next.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	next.position = Vector2(-560.0 - 70.0, -110.0 - 150.0)
	next.pressed.connect(_start_game)
	root.add_child(next)
	var hint := UIKit.label("点上方头像可以更换角色", 26, Color.WHITE, 8, Color(0.05, 0.2, 0.34, 0.9))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.position = Vector2(-560.0 - 70.0, -150.0 + 8.0)
	hint.size = Vector2(560, 40)
	root.add_child(hint)
	var pulse := next.create_tween().set_loops()
	pulse.tween_property(next, "scale", Vector2(1.035, 1.035), 0.7).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(next, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)
	var back := UIKit.button("返回", Vector2(280, 76), UIKit.PINK, 36)
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.position = Vector2(70, -76.0 - 80.0)
	back.pressed.connect(func(): _show_page("main"))
	root.add_child(back)
	_refresh_mode_cards(cards)
	return root


var _venue_row: Control


## the venue (court scene) picker under the mode list: four sticker cards; locked venues show the level that opens them
func _fill_venue_row() -> void:
	for c in _venue_row.get_children():
		c.queue_free()
	if Game.profile == null or not Game.profile_enabled:
		return
	var p: Profile = Game.profile
	var title := UIKit.label(tr("球场"), 34, Color.WHITE, 10, Color(0.05, 0.2, 0.34, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	title.position = Vector2(112, 626)
	title.size = Vector2(300, 46)
	_venue_row.add_child(title)
	var cur_name := UIKit.label("", 28, Color(1, 1, 1, 0.95), 8, Color(0.05, 0.2, 0.34, 0.9), HORIZONTAL_ALIGNMENT_RIGHT)
	cur_name.position = Vector2(410, 630)
	cur_name.size = Vector2(400, 40)
	_venue_row.add_child(cur_name)
	var cat := Profile.catalog("court")
	for i in cat.size():
		var it: Dictionary = cat[i]
		var unlocked := p.is_unlocked("court", String(it["id"]))
		var on: bool = String(p.equipped.get("court", "day")) == String(it["id"]) and unlocked
		if on:
			cur_name.text = tr(String(it["name"]))
		var b := Button.new()
		b.size = Vector2(160, 150)
		b.position = Vector2(104.0 + float(i) * 176.0, 678)
		b.pivot_offset = b.size * 0.5
		b.focus_mode = Control.FOCUS_ALL
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(st, empty)
		var rim := Panel.new()
		rim.position = Vector2(6, 4)
		rim.size = Vector2(148, 100)
		rim.add_theme_stylebox_override("panel", UIKit.style_box(Color("4fd16b") if on else Color.WHITE, 40, 0, Color.WHITE, 8))
		rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(rim)
		var clip := Panel.new()
		clip.position = Vector2(11, 9)
		clip.size = Vector2(138, 90)
		clip.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.82, 0.9, 0.94), 36))
		clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(clip)
		var sw := CareerPage._Swatch.new()
		sw.kind = "court"
		sw.item = it
		sw.locked = not unlocked
		sw.size = Vector2(138, 90)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(sw)
		if not unlocked:
			var lk := UIKit.label("Lv.%d" % int(it["level"]), 26, Color.WHITE, 8, Color(0.3, 0.12, 0.0, 0.9))
			lk.position = Vector2(0, 30)
			lk.size = Vector2(160, 40)
			b.add_child(lk)
		var nm := UIKit.label(tr(String(it["name"])), 24, Color.WHITE if unlocked else Color(0.62, 0.78, 0.88), 7, Color(0.03, 0.14, 0.26, 0.95))
		nm.position = Vector2(-10, 108)
		nm.size = Vector2(180, 36)
		nm.clip_text = true
		b.add_child(nm)
		b.mouse_entered.connect(func(): UIKit._bump(b, 1.06))
		b.focus_entered.connect(func(): UIKit._bump(b, 1.06))
		b.mouse_exited.connect(func(): UIKit._bump(b, 1.0))
		b.focus_exited.connect(func(): UIKit._bump(b, 1.0))
		b.pressed.connect(func():
			if unlocked:
				if p.equip("court", String(it["id"])):
					Sfx.play("ui_confirm", -3.0)
					_fill_venue_row()
			else:
				Sfx.play("ui_hover", -4.0)
				cur_name.text = tr("达到 Lv.%d 解锁") % int(it["level"]))
		_venue_row.add_child(b)


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
		var b := cards.get_child(i) as MenuEntry
		b.mark(Game.mode == modes[i][0])
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
			left_team = [["玩家1", p1, "p1"], ["玩家2", p2, "p2"]]
			right_team = [["电脑", "", ""], ["电脑", "", ""]]
		"versus":
			left_team = [["玩家1", p1, "p1"], ["电脑", Game.partner_char, "partner"]]
			right_team = [["玩家2", p2, "p2"], ["电脑", "", ""]]
		_:
			left_team = [["你", p1, "p1"], ["电脑", Game.partner_char, "partner"]]
			right_team = [["电脑", "", ""], ["电脑", "", ""]]
	for s in left_team:
		_vs_row.add_child(_slot_box(String(s[0]), String(s[1]), UIKit.BLUE, String(s[2])))
	var vs := UIKit.label("VS", 56, Color(0.45, 0.55, 0.6), 0, Color.WHITE)
	vs.custom_minimum_size = Vector2(150, 110)
	_vs_row.add_child(vs)
	for s in right_team:
		_vs_row.add_child(_slot_box(String(s[0]), String(s[1]), UIKit.PINK, String(s[2])))


# ---- LOADOUT (my character): who you play as. Saved with the profile, changeable at any time, and NOT part of starting a match:
# "Start" always goes straight to the match with whatever is equipped here (the VS intro then introduces both teams).
const LO_SLOTS := ["p1", "p2", "partner"]


func _lo_title(slot: String) -> String:
	match slot:
		"p2": return tr("玩家2")
		"partner": return tr("电脑队友")
	return tr("玩家1")


func _lo_char(slot: String) -> String:
	match slot:
		"p2": return Game.p2_char
		"partner": return Game.partner_char
	return Game.p1_char


func _lo_set(slot: String, id: String) -> void:
	match slot:
		"p2": Game.p2_char = id
		"partner": Game.partner_char = id
		_: Game.p1_char = id


func _lo_tint(slot: String) -> Color:
	return UIKit.PINK if slot == "p2" else (UIKit.TEAL if slot == "partner" else UIKit.BLUE)


func _build_loadout() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var hd := GW.header(tr("我的角色"), "person", 880.0)
	hd.position = Vector2(70, 34)
	root.add_child(hd)
	var panel := GW.frost(Vector2(1000, 800), 40.0)
	panel.position = Vector2(60, 146)
	root.add_child(panel)
	# the three slots you can dress: you, the second local player, your CPU partner
	_lo_chips.clear()
	for i in LO_SLOTS.size():
		var slot: String = LO_SLOTS[i]
		var b := Button.new()
		b.size = Vector2(300, 100)
		b.position = Vector2(32.0 + float(i) * 318.0, 24)
		b.focus_mode = Control.FOCUS_ALL
		b.pivot_offset = b.size * 0.5
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(st, empty)
		var bg := GW.pill_bg(b.size, 50.0, MenuEntry.PALE, 0.0)
		bg.show_behind_parent = true
		b.add_child(bg)
		b.set_meta("bg", bg)
		var holder := Control.new()
		holder.position = Vector2(12, 10)
		holder.size = Vector2(80, 80)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(holder)
		b.set_meta("holder", holder)
		var t1 := UIKit.label("", 22, UIKit.INK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		t1.position = Vector2(104, 12)
		t1.size = Vector2(186, 30)
		t1.clip_text = true
		b.add_child(t1)
		var t2 := UIKit.label("", 32, UIKit.INK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		t2.position = Vector2(104, 40)
		t2.size = Vector2(186, 46)
		t2.clip_text = true
		b.add_child(t2)
		b.set_meta("t1", t1)
		b.set_meta("t2", t2)
		var sl := slot
		b.pressed.connect(func(): _lo_choose_slot(sl))
		b.mouse_entered.connect(func(): UIKit._bump(b, 1.03))
		b.mouse_exited.connect(func(): UIKit._bump(b, 1.0))
		panel.add_child(b)
		_lo_chips[slot] = b
	# the character grid
	var grid := GridContainer.new()
	grid.columns = 6
	grid.position = Vector2(28, 150)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	panel.add_child(grid)
	_lo_tiles.clear()
	for i in _roster.size():
		var e := _roster[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 150)
		b.focus_mode = Control.FOCUS_ALL
		b.pivot_offset = Vector2(75, 75)
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "pressed"]:
			b.add_theme_stylebox_override(st, empty)
		var ring := UIKit.style_box(Color(0.1, 0.7, 0.66, 0.12), 30, 4, UIKit.TEAL)
		for st in ["hover", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(st, ring)
		var av := UIKit.avatar(e["id"], 92, UIKit.BLUE if e["kind"] == "cube" else Color("8e3dff"), 4)
		av.position = Vector2(29, 8)
		b.add_child(av)
		var nm := UIKit.label(tr(String(e["name"])), 24, UIKit.INK, 0, Color.WHITE)
		nm.position = Vector2(0, 106)
		nm.size = Vector2(150, 34)
		b.add_child(nm)
		var deco := Control.new()
		deco.name = "Deco"
		deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(deco)
		var idx := i
		b.mouse_entered.connect(func(): _preview(idx); UIKit._bump(b, 1.05))
		b.mouse_exited.connect(func(): UIKit._bump(b, 1.0))
		b.focus_entered.connect(func(): _preview(idx); Sfx.play("ui_hover", -9.0); UIKit._bump(b, 1.05))
		b.focus_exited.connect(func(): UIKit._bump(b, 1.0))
		b.pressed.connect(func(): _lo_pick(idx))
		grid.add_child(b)
		_lo_tiles.append(b)
	_lo_note = UIKit.label("", 28, UIKit.TEAL_DARK)
	_lo_note.position = Vector2(30, 760)
	_lo_note.size = Vector2(940, 34)
	panel.add_child(_lo_note)
	# the info board of the previewed character (right, under the 3D preview)
	var info := GW.board(Vector2(860, 280), Color(0.06, 0.2, 0.32, 0.9), Color(1, 1, 1, 0.9), 0.04)
	info.position = Vector2(1020, 680)
	root.add_child(info)
	var iv := VBoxContainer.new()
	iv.position = Vector2(54, 10)
	iv.size = Vector2(780, 250)
	iv.add_theme_constant_override("separation", 2)
	info.add_child(iv)
	_sel_name = UIKit.label("", 46, Color.WHITE, 10, Color(0.02, 0.1, 0.2, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	iv.add_child(_sel_name)
	_sel_state = UIKit.label("", 26, Color("7dffb0"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_sel_state.position = Vector2(540, 22)
	_sel_state.size = Vector2(250, 36)
	info.add_child(_sel_state)
	_sel_blurb = UIKit.label("", 28, Color(0.72, 0.86, 0.95), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	iv.add_child(_sel_blurb)
	_sel_perk = UIKit.label("", 26, Color("ffe14a"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	iv.add_child(_sel_perk)
	_sel_bars.clear()
	for t in [["速度", UIKit.BLUE], ["弹跳", UIKit.GREEN], ["力量", UIKit.PINK]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		var tl := UIKit.label(tr(String(t[0])), 26, Color.WHITE, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		tl.custom_minimum_size = Vector2(90, 0)
		h.add_child(tl)
		var pb := ProgressBar.new()
		pb.min_value = 0.8
		pb.max_value = 1.2
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(560, 20)
		pb.add_theme_stylebox_override("background", UIKit.style_box(Color(0.02, 0.1, 0.18, 0.6), 11, 2, Color(1, 1, 1, 0.5)))
		pb.add_theme_stylebox_override("fill", UIKit.style_box(t[1], 11))
		h.add_child(pb)
		iv.add_child(h)
		_sel_bars.append(pb)
	# "random partner every match" switch (only for the CPU-partner slot)
	_lo_rand = Control.new()
	_lo_rand.position = Vector2(1360, 40)
	_lo_rand.size = Vector2(500, 70)
	_lo_rand.add_child(GW.pill_bg(_lo_rand.size, 35.0, MenuEntry.PALE, 0.0))
	var rl := UIKit.label(tr("每场随机队友"), 28, UIKit.INK, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	rl.position = Vector2(30, 0)
	rl.size = Vector2(320, 70)
	_lo_rand.add_child(rl)
	_lo_rand_pill = UIKit.toggle_pill(true, func(v): _lo_set_random(v))
	_lo_rand_pill.position = Vector2(368, 8)
	_lo_rand_pill.size = Vector2(120, 54)
	_lo_rand.add_child(_lo_rand_pill)
	root.add_child(_lo_rand)
	# buttons
	var back := UIKit.button(tr("返回"), Vector2(280, 76), UIKit.PINK, 36)
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.position = Vector2(70, -110)
	back.pressed.connect(func(): _show_page(_lo_return))
	root.add_child(back)
	var rnd := UIKit.button(tr("随机"), Vector2(280, 76), UIKit.BLUE, 36)
	rnd.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	rnd.position = Vector2(380, -110)
	rnd.pressed.connect(_lo_random)
	root.add_child(rnd)
	return root


## open the loadout page on `slot` ("p1" / "p2" / "partner"); Back returns to `ret`
func _open_loadout(slot: String, ret: String) -> void:
	_lo_slot = slot
	_lo_return = ret
	_show_page("loadout")


## dev: --lotest runs the pick / swap / random rules once and prints the result (use with --nosave)
func _lo_selftest() -> void:
	var out := []
	Game.p1_char = "m"; Game.p2_char = "bear"; Game.partner_char = ""
	_lo_slot = "p1"; _lo_pick(Roster.index_of("snow"))
	out.append("p1=snow -> p1=%s p2=%s partner='%s'" % [Game.p1_char, Game.p2_char, Game.partner_char])
	_lo_pick(Roster.index_of("bear"))                       # taken by p2: swap
	out.append("p1=bear (swap) -> p1=%s p2=%s" % [Game.p1_char, Game.p2_char])
	_lo_slot = "partner"; _lo_pick(Roster.index_of("bear"))  # random partner picks a taken one: refused
	out.append("partner=bear (denied) -> partner='%s'" % Game.partner_char)
	_lo_pick(Roster.index_of("wang"))
	out.append("partner=wang -> partner='%s'" % Game.partner_char)
	for mode in ["solo", "coop", "versus", "tournament", "rally"]:
		Game.mode = mode
		_make_lineup()
		var all: Array = _lineup["a"] + _lineup["b"]
		var uniq := {}
		for id in all:
			uniq[id] = true
		out.append("%s: A=%s B=%s unique=%s" % [mode, _lineup["a"], _lineup["b"], uniq.size() == all.size()])
	_lo_set_random(true)
	out.append("random on -> partner='%s'" % Game.partner_char)
	_lo_set_random(false)
	out.append("random off -> partner='%s'" % Game.partner_char)
	for l in out:
		print("[lotest] ", l)
	get_tree().quit()


func _lo_enter() -> void:
	stage.look(Vector3(0.0, 1.9, 9.5), Vector3(1.5, 1.05, 1.4))
	if _lo_dot != null:
		_lo_dot.visible = false
	if Game.profile != null and not Game.profile.flags.get("loadout_seen", false):
		Game.profile.flags["loadout_seen"] = true
		if Game.profile_enabled and not (Game.main != null and Game.main.dev.has("nosave")):
			Game.profile.save()
	_lo_note.text = ""
	_lo_refresh()
	var id := _lo_char(_lo_slot)
	var idx := Roster.index_of(id) if id != "" else 0
	_lo_tiles[idx].call_deferred("grab_focus")
	_preview(idx, "cheer")


func _lo_choose_slot(slot: String) -> void:
	_lo_slot = slot
	Sfx.play("ui_click", -4.0)
	_lo_refresh()
	var id := _lo_char(slot)
	var idx := Roster.index_of(id) if id != "" else 0
	_lo_tiles[idx].grab_focus()
	_preview(idx, "cheer", true)


## tags on the tiles (who wears this character), the highlighted chip, the random switch
func _lo_refresh() -> void:
	for slot in LO_SLOTS:
		var b: Button = _lo_chips[slot]
		var sel: bool = slot == _lo_slot
		GW.pill_set(b.get_meta("bg") as ColorRect, b.size, 50.0, MenuEntry.TEAL if sel else MenuEntry.PALE, 0.5 if sel else 0.0)
		var id := _lo_char(slot)
		var holder: Control = b.get_meta("holder")
		for c in holder.get_children():
			c.queue_free()
		if id != "":
			var av := UIKit.avatar(id, 80, _lo_tint(slot), 4)
			holder.add_child(av)
		else:
			var ph := _Slot.new()
			ph.size = Vector2(80, 80)
			ph.tint = _lo_tint(slot)
			holder.add_child(ph)
		var ink: Color = Color.WHITE if sel else UIKit.INK
		var t1: Label = b.get_meta("t1")
		var t2: Label = b.get_meta("t2")
		t1.text = _lo_title(slot)
		t1.add_theme_color_override("font_color", Color(1, 1, 1, 0.92) if sel else Color(0.3, 0.45, 0.52))
		t2.text = tr(String(Roster.by_id(id)["name"])) if id != "" else tr("随机")
		t2.add_theme_color_override("font_color", ink)
	for i in _lo_tiles.size():
		_lo_decorate(_lo_tiles[i], String(_roster[i]["id"]))
	_lo_rand.visible = _lo_slot == "partner"
	var on: bool = Game.partner_char == ""
	_lo_rand_pill.set_pressed_no_signal(on)
	_lo_rand_pill.text = "开" if on else "关"
	_update_state_tag(_preview_idx)


func _lo_decorate(tile: Button, id: String) -> void:
	var deco: Control = tile.get_node("Deco")
	for c in deco.get_children():
		c.queue_free()
	var x := 6.0
	for slot in LO_SLOTS:
		if _lo_char(slot) != id:
			continue
		var col := _lo_tint(slot)
		var tag := Panel.new()
		var w := 44.0 if slot != "partner" else 62.0
		tag.position = Vector2(x, 2)
		tag.size = Vector2(w, 26)
		tag.add_theme_stylebox_override("panel", UIKit.style_box(col, 13, 2, Color.WHITE, 2))
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tl := UIKit.label("P1" if slot == "p1" else ("P2" if slot == "p2" else tr("队友")), 17, Color.WHITE)
		tl.set_anchors_preset(Control.PRESET_FULL_RECT)
		tag.add_child(tl)
		deco.add_child(tag)
		x += w + 4.0
	if _lo_char(_lo_slot) == id:
		var ck := GW.glyph("check", 36.0, Color("14b08a"))
		ck.position = Vector2(108, 2)
		deco.add_child(ck)


func _preview(idx: int, clip := "", force := false) -> void:
	if idx == _preview_idx and not force:
		return
	_preview_idx = idx
	var e := Roster.by_id(_roster[idx]["id"])
	if _preview_rig and is_instance_valid(_preview_rig):
		_preview_rig.queue_free()
		stage.rigs.erase(_preview_rig)
	_preview_rig = stage.add_rig(e, Vector3(3.2, 0, 1.4), PI + 0.5, clip if clip != "" else ["cheer", "ready", "bump", "set"][randi() % 4])
	_preview_rig.scale = Vector3.ONE * float(e["scale"]) * 1.25
	_sel_name.text = tr(String(e["name"]))
	_sel_blurb.text = tr(String(e["blurb"]))
	var pk := Roster.perk_info(String(e.get("perk", "")))
	_sel_perk.text = (tr("特性「%s」 %s") % [tr(String(pk["name"])), tr(String(pk["desc"]))]) if pk["name"] != "" else ""
	var st: Dictionary = e["stats"]
	_sel_bars[0].value = st["speed"]
	_sel_bars[1].value = st["jump"]
	_sel_bars[2].value = st["power"]
	_update_state_tag(idx)


func _update_state_tag(idx: int) -> void:
	if _sel_state == null or idx < 0:
		return
	var id := String(_roster[idx]["id"])
	if _lo_char(_lo_slot) == id:
		_sel_state.text = tr("使用中")
		_sel_state.add_theme_color_override("font_color", Color("7dffb0"))
	else:
		_sel_state.text = tr("点击装备")
		_sel_state.add_theme_color_override("font_color", Color(0.72, 0.86, 0.95))


func _lo_say(msg: String) -> void:
	_lo_note.text = msg
	_lo_note.modulate.a = 1.0
	if _lo_note_tw != null and _lo_note_tw.is_valid():
		_lo_note_tw.kill()
	_lo_note_tw = _lo_note.create_tween()
	_lo_note_tw.tween_interval(1.6)
	_lo_note_tw.tween_property(_lo_note, "modulate:a", 0.0, 0.3)


## equip tile `idx` for the current slot. A character can only be worn by one slot: if another slot has it, the two swap.
func _lo_pick(idx: int) -> void:
	var id: String = _roster[idx]["id"]
	var cur := _lo_char(_lo_slot)
	if id == cur:
		Sfx.play("ui_confirm", -8.0)
		return
	for s2 in LO_SLOTS:
		if s2 != _lo_slot and _lo_char(s2) == id:
			if cur == "":
				_lo_say(tr("已被%s使用") % _lo_title(s2))
				Sfx.play("ui_back", -4.0)
				return
			_lo_set(s2, cur)
			break
	_lo_set(_lo_slot, id)
	Sfx.play("ui_confirm", -2.0)
	Game.save_settings()
	_lo_refresh()
	_preview(idx, "cheer", true)


func _lo_random() -> void:
	if _lo_slot == "partner":
		_lo_set_random(true)
		_lo_refresh()
		return
	var pool: Array = []
	for i in _roster.size():
		var id: String = _roster[i]["id"]
		if id != _lo_char(_lo_slot) and not (_lo_char("p1") == id or _lo_char("p2") == id or _lo_char("partner") == id):
			pool.append(i)
	if not pool.is_empty():
		var pick: int = pool[randi() % pool.size()]
		_lo_pick(pick)
		_lo_tiles[pick].grab_focus()


func _lo_set_random(on: bool) -> void:
	if on:
		Game.partner_char = ""
	elif Game.partner_char == "":
		# switch to a fixed partner: the one being previewed if it is free, else the first free character
		var want := String(_roster[maxi(_preview_idx, 0)]["id"])
		if want == Game.p1_char or want == Game.p2_char:
			for e in _roster:
				if e["id"] != Game.p1_char and e["id"] != Game.p2_char:
					want = String(e["id"])
					break
		Game.partner_char = want
	Game.save_settings()
	_lo_refresh()


func _random_ids(count: int, exclude: Array) -> Array:
	var pool: Array = []
	for e in _roster:
		if not exclude.has(e["id"]):
			pool.append(e["id"])
	pool.shuffle()
	return pool.slice(0, count)


## the saved CPU partner, or a random one when none is set (or it is taken)
func _pick_partner(exclude: Array) -> String:
	var pc: String = Game.partner_char
	if pc != "" and not exclude.has(pc):
		return pc
	return String(_random_ids(1, exclude)[0])


## teams for the current mode from the saved loadout (the CPU players are random)
func _make_lineup() -> void:
	var p1: String = Game.p1_char
	var p2: String = Game.p2_char
	var a: Array = []
	var b: Array = []
	match Game.mode:
		"coop":
			a = [p1, p2]
			b = _random_ids(2, a)
		"versus":
			var used: Array = [p1, p2]
			var mate := _pick_partner(used)
			used.append(mate)
			a = [p1, mate]
			b = [p2, String(_random_ids(1, used)[0])]
		"tournament":
			var used_t: Array = Game.tournament_ids() + [p1]
			var mate_t := _pick_partner(used_t)
			a = [p1, mate_t]
			Game.team_a = a.duplicate()
			b = Game.tournament_opponents(0)
		_:                                 # solo / rally / training: you + a partner against two CPU players
			var used_s: Array = [p1]
			var mate_s := _pick_partner(used_s)
			used_s.append(mate_s)
			a = [p1, mate_s]
			b = _random_ids(2, used_s)
	_lineup["a"] = a
	_lineup["b"] = b


## "Start": straight into the match with the saved loadout
func _start_game() -> void:
	_make_lineup()
	_start_match()


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


func _page_title(root: Control, text: String, width := 560.0, glyph := "ball") -> void:
	var h := GW.header(text, glyph, maxf(width, 760.0))
	h.position = Vector2(70, 34)
	root.add_child(h)


var _set_panel: Control
var _set_cards: Control
var _set_cat := 0


func _build_settings() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page_title(root, "设置", 700.0, "gear")
	# category list (left), like the reference's Options sidebar
	_set_cards = Control.new()
	root.add_child(_set_cards)
	var cats := [["声音", "调整音乐与音效", "speaker"], ["画面", "画质、全屏、镜头", "eye"], ["操作", "按键、触屏、提示", "keys"], ["语言", "Language / 语言", "globe"]]
	var y := 190.0
	for i in cats.size():
		var en := MenuEntry.new().build(String(cats[i][0]), String(cats[i][1]), String(cats[i][2]), Vector2(560, 100), "pale", "", 2.0, 38)
		en.position = Vector2(100, y)
		var ci := i
		en.chosen.connect(func(): _fill_settings(ci))
		en.focus_entered.connect(func(): _fill_settings(ci))
		_set_cards.add_child(en)
		y += 120.0
	_set_cards.set_meta("n", cats.size())
	var cr := MenuEntry.new().build("制作与素材", "", "star", Vector2(560, 84), "pale", "", 2.0, 34)
	cr.position = Vector2(100, 810)
	cr.chosen.connect(func(): _show_page("credits"))
	_set_cards.add_child(cr)
	# the rows on frosted glass (right)
	_set_panel = GW.frost(Vector2(1000, 700), 40.0)
	_set_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_set_panel.position = Vector2(-1000.0 - 60.0, 170)
	root.add_child(_set_panel)
	var back := UIKit.button("返回", Vector2(280, 76), UIKit.PINK, 36)
	back.position = Vector2(70, 920)
	back.pressed.connect(func(): Game.save_settings(); _show_page("main"))
	root.add_child(back)
	_fill_settings(0)
	return root


func _fill_settings(cat: int) -> void:
	_set_cat = cat
	for i in int(_set_cards.get_meta("n")):
		(_set_cards.get_child(i) as MenuEntry).mark(i == cat)
	# the frosted panel is rebuilt to fit its rows (a short list on a huge pane looks empty)
	var rows_n: int = [2, 3, 6, 1][cat]
	var ph := float(rows_n) * 96.0 + 72.0 + (96.0 if cat == 2 else 0.0)
	var old_panel := _set_panel
	_set_panel = GW.frost(Vector2(1000, ph), 40.0)
	_set_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_set_panel.position = Vector2(-1000.0 - 60.0, 190)
	old_panel.get_parent().add_child(_set_panel)
	old_panel.queue_free()
	var col := VBoxContainer.new()
	col.position = Vector2(48, 36)
	col.size = Vector2(904, ph - 60.0)
	col.add_theme_constant_override("separation", 16)
	_set_panel.add_child(col)
	var onoff := func(title: String, key: String):
		col.add_child(GW.option_row(title, ["关", "开"], 1 if Game.settings[key] else 0, func(i):
			Game.settings[key] = i == 1
			Game.apply_settings()
			Game.save_settings(), 904.0, 150.0))
	match cat:
		0:
			col.add_child(GW.slider_row("音乐音量", float(Game.settings["music"]), func(v): Game.settings["music"] = v; Game.apply_settings(); Sfx.play("ui_hover", -6.0), 904.0))
			col.add_child(GW.slider_row("音效音量", float(Game.settings["sfx"]), func(v): Game.settings["sfx"] = v; Game.apply_settings(); Sfx.play("ui_hover", -6.0), 904.0))
		1:
			col.add_child(GW.option_row("画面质量", ["低 (手机)", "中", "高"], int(Game.settings["quality"]), func(i): Game.settings["quality"] = i; Game.save_settings(), 904.0, 170.0))
			onoff.call("全屏", "fullscreen")
			onoff.call("镜头震动", "shake")
		2:
			col.add_child(GW.option_row("触屏控制", ["自动", "开启", "关闭"], maxi(["auto", "on", "off"].find(Game.settings["touch"]), 0), func(i):
				Game.settings["touch"] = ["auto", "on", "off"][i]
				Game._detect_touch()
				Game.save_settings(), 904.0, 150.0))
			col.add_child(GW.option_row("落点提示", ["关闭", "简洁", "标准"], int(Game.settings["landing_hint"]), func(i): Game.settings["landing_hint"] = i; Game.settings["landing_hint_set"] = true; Game.save_settings(), 904.0, 150.0))
			onoff.call("击球时机提示圈", "timing_guide")
			onoff.call("触觉震动（手机 / 手柄）", "haptics")
			onoff.call("左手模式（触屏按键镜像）", "left_handed")
			var kb := UIKit.button("按键设置", Vector2(360, 70), UIKit.GREEN, 34)
			kb.pressed.connect(func(): _show_page("keys"))
			var wrap := HBoxContainer.new()
			wrap.alignment = BoxContainer.ALIGNMENT_CENTER
			wrap.add_child(kb)
			col.add_child(wrap)
		3:
			col.add_child(GW.option_row("Language / 语言", Loc.LANG_NAMES, maxi(Loc.LANGS.find(String(Game.settings["language"])), 0), func(i):
				Game.settings["language"] = Loc.LANGS[i]
				Game.save_settings()
				Loc.apply(String(Loc.LANGS[i]))
				Game.goto("menu", {"page": "settings"}), 904.0, 220.0))


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
	_page_title(root, "制作与素材", 640.0, "star")
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
	_page_title(root, "按键设置 (玩家1 键盘)", 860.0, "keys")
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


# ---- HOW TO PLAY (scripts/ui/howto_page.gd)
func _build_howto() -> Control:
	var hp := HowToPage.new().build()
	hp.back_pressed.connect(func(): _show_page("main"))
	return hp

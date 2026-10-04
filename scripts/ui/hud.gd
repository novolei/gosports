extends CanvasLayer
## In-match HUD: Switch-Sports-style scoreboard, serve bubble, "next action" hint, popups, banners,
## pause menu and touch controls.


var ms: MatchScene
var director: MatchDirector
var root_c: Control
var score_lbl: Array[Label] = []
var bar: Array[Control] = []
var markers: Array = []             # {a: Athlete, n: Control} head markers of the human players
var serve_icon: Array[Control] = []
var name_lbl: Array = [[], []]
var popup_layer: Control
var banner: Label
var hint_panel: PanelContainer
var hint_lbl: Label
var hint_pre: Label
var hint_sub: Label
var serve_bubble: Control
var serve_pill: Panel
var hint_icon: _ActionBubble
var _match_point_team := -1
var _combo_root: Control                    # top-right combo counter (rally length + Nice chain), tilted, elastic
var _combo_num: Callout
var _combo_word: Callout
var _combo_chain: Callout
var _combo_n := 0
var _clock: Control
var _clock_lbl: Label
var _clock_last := -1
var pause_root: Control
var touch: TouchControls
var tutorial: Control
var _hint_text := ""
var _hint_icon_name := ""
var _banner_tween: Tween
var _last_score := [0, 0]
var _msg_label: Label
var replay_overlay: ReplayOverlay
var _vs_card: VsCard = null
var _pause_btn: Button
var _flash: ColorRect
var tracker: _EdgeTracker
var _mate_icon: Control
var _mate_id := ""
var _mate_off_t := 0.0
var _vs_hold := false
var replay_mode := false:
	set(v):
		replay_mode = v
		_set_replay_hud(v)


func bind(p_ms: MatchScene) -> void:
	ms = p_ms
	director = ms.director
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root_c = Control.new()
	root_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_c)
	popup_layer = Control.new()
	popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_scoreboard()
	_build_hint()
	_build_banner()
	_build_serve_bubble()
	_build_markers()
	_build_tracker()
	_build_feel_layers()
	_build_hype()
	_build_practice()
	root_c.add_child(popup_layer)
	replay_overlay = ReplayOverlay.new().build(get_viewport().get_visible_rect().size)
	root_c.add_child(replay_overlay)
	_build_pause_button()
	_build_pause_menu()
	_build_touch()
	_build_tutorial()
	director.score_changed.connect(_on_score)
	director.popup.connect(_on_popup)
	director.phase_changed.connect(_on_phase)
	director.rally_event.connect(_on_rally_event)
	director.point_scored.connect(_on_point)
	director.match_over.connect(_on_match_over)
	Game.touch_mode_changed.connect(func(_t): _build_touch())
	_refresh_score(false)
	_build_mode_tag()
	if Game.main != null and Game.main.dev.has("combodemo"):         # dev: --combodemo counts the combo badge up (4..14) and adds a Nice chain
		_dev_combo()
	if Game.main != null and Game.main.dev.has("cardshot"):       # dev: --cardshot=0|1 plays the point card for that team (score 4-3)
		_dev_card(int(Game.main.dev["cardshot"]))
	if Game.profile != null and Game.profile_enabled:
		Game.profile.achievement_unlocked.connect(_on_achievement)
		Game.profile.mission_done.connect(_on_mission_done)
		Game.profile.level_up.connect(_on_level_up)


## tournament: a small round tag at the top and a title card a moment after "READY?"
func _build_mode_tag() -> void:
	if Game.mode != "tournament":
		return
	var rd: int = int(Game.tournament["round"])
	var r: Dictionary = Game.TOURNAMENT_ROUNDS[rd]
	var vp := get_viewport().get_visible_rect().size
	var tag := Panel.new()
	tag.size = Vector2(400, 50)
	tag.position = Vector2((vp.x - 400.0) * 0.5, 18.0 + float(Game.safe_insets()["t"]))
	tag.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.95, 0.55, 0.1, 0.92), 25, 3, Color.WHITE, 8))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_c.add_child(tag)
	var l := UIKit.label("锦标赛 · %s  (%d/%d)" % [r["name"], rd + 1, Game.TOURNAMENT_ROUNDS.size()], 26, Color.WHITE, 6, Color(0.5, 0.2, 0.0, 0.85))
	l.size = tag.size
	tag.add_child(l)
	get_tree().create_timer(2.4).timeout.connect(func():
		if is_inside_tree():
			show_banner(String(r["name"]), Color("ffd24a"), 120, 1.5, Color("c4501a")))


# ------------------------------------------------------------------ action pictograms
static var _icon_cache := {}


static func act_icon(n: String) -> Texture2D:
	if not _icon_cache.has(n):
		var path := "res://assets/ui/act_%s.png" % n
		_icon_cache[n] = load(path) if ResourceLoader.exists(path) else null
	return _icon_cache[n]


## round double-ring bubble with a white action pictogram inside ("Next: bump", the server marker)
class _ActionBubble:
	extends Control
	var icon: Texture2D
	var ring := Color(0.55, 1.0, 0.9)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 5.0
		draw_circle(c + Vector2(0, 5), r, Color(0, 0, 0, 0.2))
		draw_circle(c, r, Color(0.06, 0.28, 0.33, 0.84))
		draw_arc(c, r, 0.0, TAU, 72, Color(1, 1, 1, 0.96), 5.0, true)
		draw_arc(c, r - 9.0, 0.0, TAU, 72, ring, 3.0, true)
		if icon != null:
			var s := r * 1.5
			draw_texture_rect(icon, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false)


# ------------------------------------------------------------------ scoreboard
func _build_scoreboard() -> void:
	var holder := Control.new()
	scoreboard_holder = holder
	var inset: Dictionary = Game.safe_insets()
	holder.position = Vector2(26 + float(inset["l"]), 20 + float(inset["t"]))
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_c.add_child(holder)
	for t in 2:
		var y := t * 124.0
		var col := UIKit.team_color(t)
		var row := Control.new()
		row.position = Vector2(0, y)
		row.size = Vector2(480, 112)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(row)
		# long tapering bar behind the avatars, the score sits near its end
		var p := _ScoreBar.new()
		p.position = Vector2(64, 14)
		p.size = Vector2(312, 62)
		p.col = col
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(p)
		bar.append(p)
		var ids: Array = Game.team_a if t == 0 else Game.team_b
		for i in 2:
			var a := UIKit.avatar(ids[i], 92, col, 5)
			a.position = Vector2(i * 88.0, -4)
			row.add_child(a)
			var nm := Panel.new()
			nm.position = Vector2(i * 88.0 + 4, 82)
			nm.size = Vector2(84, 24)
			nm.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.1, 0.15, 0.3, 0.88), 12))
			nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(nm)
			var l := UIKit.label(Roster.by_id(ids[i])["name"], 17, Color.WHITE)
			l.set_anchors_preset(Control.PRESET_FULL_RECT)
			nm.add_child(l)
		# small ball marks the serving team
		var ic := _BallIcon.new()
		ic.position = Vector2(184, 24)
		ic.size = Vector2(42, 42)
		ic.visible = false
		row.add_child(ic)
		serve_icon.append(ic)
		var sc := UIKit.label("0", 84, Color.WHITE, 16, UIKit.team_dark(t))
		sc.position = Vector2(262, -4)
		sc.size = Vector2(110, 96)
		sc.pivot_offset = Vector2(55, 48)
		sc.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.25))
		sc.add_theme_constant_override("shadow_offset_y", 4)
		row.add_child(sc)
		score_lbl.append(sc)


## Switch-Sports-like score bar: a pill that lightens to the left, saturates in the middle and fades out at its tail.
## Generated once per team colour into a texture (a handful of pixel loops) - drawing it every frame as polygons cost
## ~190 canvas draw calls per bar on phones.
class _ScoreBar:
	extends Control
	static var _cache := {}
	var col := Color.WHITE
	var _tex: Texture2D

	func _ready() -> void:
		var key := col.to_html() + "|%dx%d" % [int(size.x), int(size.y)]
		if not _cache.has(key):
			_cache[key] = _make(int(size.x), int(size.y))
		_tex = _cache[key]
		queue_redraw()

	func _draw() -> void:
		if _tex != null:
			draw_texture(_tex, Vector2(0, -6))

	func _make(w: int, h: int) -> Texture2D:
		var pad := 6
		var img := Image.create(w, h + pad * 2, false, Image.FORMAT_RGBA8)
		var r := float(h) * 0.5
		var cy := float(h) * 0.5 + float(pad)
		var light := col.lightened(0.38)
		for x in w:
			var u := float(x) / float(w)
			var hh := r
			if x < r:
				hh = sqrt(maxf(r * r - (r - float(x)) * (r - float(x)), 0.0))
			elif float(x) > float(w) - r:
				hh = sqrt(maxf(r * r - (float(x) - (float(w) - r)) * (float(x) - (float(w) - r)), 0.0))
			hh *= lerpf(1.0, 0.84, u)
			var c := light.lerp(col, clampf(u / 0.5, 0.0, 1.0))
			var fade := 1.0 - 0.62 * smoothstep(0.62, 1.0, u)
			for y in range(0, h + pad * 2):
				var fy := float(y) + 0.5
				var out := Color(0, 0, 0, 0)
				# soft shadow, 6 px lower
				var sd := absf(fy - (cy + 6.0))
				var sc := clampf(hh - sd + 0.5, 0.0, 1.0) * 0.22 * fade
				if sc > 0.0:
					out = Color(0, 0, 0, sc)
				# body
				var dy := absf(fy - cy)
				var bc := clampf(hh - dy + 0.5, 0.0, 1.0) * fade
				if bc > 0.0:
					var bodyc := Color(c.r, c.g, c.b, bc)
					# top gloss
					var gy := (cy - fy) / maxf(hh, 1.0)         # 0 at the centre line, 1 at the top edge
					if gy > 0.34 and gy < 0.82:
						var gl := 0.34 * fade
						bodyc = Color(bodyc.r + (1.0 - bodyc.r) * gl, bodyc.g + (1.0 - bodyc.g) * gl, bodyc.b + (1.0 - bodyc.b) * gl, bodyc.a)
					# source-over onto the shadow
					var ao := bodyc.a + out.a * (1.0 - bodyc.a)
					if ao > 0.0:
						out = Color((bodyc.r * bodyc.a + out.r * out.a * (1.0 - bodyc.a)) / ao, (bodyc.g * bodyc.a + out.g * out.a * (1.0 - bodyc.a)) / ao, (bodyc.b * bodyc.a + out.b * out.a * (1.0 - bodyc.a)) / ao, ao)
				img.set_pixel(x, y, out)
		return ImageTexture.create_from_image(img)


class _BallIcon:
	extends Control
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(c + Vector2(0, 2), r, Color(0, 0, 0, 0.2))
		draw_circle(c, r, Color.WHITE)
		draw_arc(c, r, 0, TAU, 32, Color(0.2, 0.2, 0.3), 2.5, true)
		draw_arc(c + Vector2(-r * 1.1, 0), r * 1.0, -0.9, 0.9, 16, Color(0.2, 0.2, 0.3), 2.5, true)
		draw_arc(c + Vector2(r * 1.1, 0), r * 1.0, PI - 0.9, PI + 0.9, 16, Color(0.2, 0.2, 0.3), 2.5, true)
		draw_arc(c + Vector2(0, -r * 1.1), r * 1.0, 1.57 - 0.9, 1.57 + 0.9, 16, Color(1.0, 0.55, 0.1), 3.5, true)


func _refresh_score(animate := true) -> void:
	for t in 2:
		score_lbl[t].text = str(director.score[t])
		# match point: the leader's numeral turns gold (like the reference scoreboard)
		var mp: bool = director.target_points < 9000 and int(director.score[t]) >= director.target_points - 1 and int(director.score[t]) > int(director.score[1 - t])
		score_lbl[t].add_theme_color_override("font_color", Color("ffe14a") if mp else Color.WHITE)
		score_lbl[t].add_theme_color_override("font_outline_color", Color("b8730a") if mp else UIKit.team_dark(t))
		serve_icon[t].visible = director.serving_team == t
		if animate and _last_score[t] != director.score[t]:
			var l := score_lbl[t]
			l.scale = Vector2(1.7, 1.7)
			var tw := l.create_tween()
			tw.tween_property(l, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_last_score[t] = director.score[t]


func _dev_combo() -> void:
	await get_tree().create_timer(1.5).timeout
	for n in range(4, 15):
		_set_combo(n)
		if n == 8:
			_set_chain(3)
		await get_tree().create_timer(0.45).timeout


func _dev_card(team: int) -> void:
	await get_tree().create_timer(1.0).timeout
	director.score = [4, 3] if team == 0 else [3, 4]
	_refresh_score(false)
	director.score[team] -= 1
	_refresh_score(false)
	director.score[team] += 1
	await get_tree().create_timer(0.25).timeout
	show_point_card(team, String(Game.main.dev.get("cardreason", "得分!")))


func _on_score(_s: Array, _serving: int) -> void:
	if director.phase == MatchDirector.P.POINT or director.phase == MatchDirector.P.OVER:
		_refresh_score_icons()                    # numbers follow the point card's roll; only the serve marker moves now
		return
	_refresh_score()


func _refresh_score_icons() -> void:
	for t in 2:
		serve_icon[t].visible = director.serving_team == t


# ------------------------------------------------------------------ hint / banner / bubbles
func _build_hint() -> void:
	hint_panel = PanelContainer.new()
	hint_panel.add_theme_stylebox_override("panel", UIKit.style_box(Color(1, 1, 1, 0.0), 40, 0, Color.WHITE, 0, 0))
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint_panel.position = Vector2(0, 76)                       # (the match clock sits above it)
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_c.add_child(hint_panel)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_child(vb)
	# one row: [icon] [下一步:] [扣球]  - all three centred on the same horizontal axis; the explanation goes under the row
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(line)
	hint_icon = _ActionBubble.new()
	hint_icon.custom_minimum_size = Vector2(92, 92)
	hint_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint_icon.visible = false
	line.add_child(hint_icon)
	hint_pre = UIKit.label("", 34, Color("8fe9d2"), 10, Color("17806f"))
	hint_pre.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(hint_pre)
	hint_lbl = UIKit.label("", 62, Color("c8fff0"), 14, Color("17806f"))
	var lbl_box := MarginContainer.new()                      # (the big glyphs sit ~2.5 px low in their line box: nudge them up so they share the icon's axis)
	lbl_box.add_theme_constant_override("margin_bottom", 5)
	lbl_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_box.add_child(hint_lbl)
	line.add_child(lbl_box)
	hint_sub = UIKit.label("", 26, Color.WHITE, 8, Color(0.05, 0.1, 0.25, 0.9))
	vb.add_child(hint_sub)
	hint_panel.modulate.a = 0.0
	var vp := get_viewport().get_visible_rect().size
	var inset: Dictionary = Game.safe_insets()
	_combo_root = Control.new()
	_combo_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_root.position = Vector2(vp.x - 250.0 - float(inset["r"]), 215.0 + float(inset["t"]))
	_combo_root.rotation = deg_to_rad(-8.0)
	_combo_root.modulate.a = 0.0
	root_c.add_child(_combo_root)
	_build_clock(vp, inset)


## The callout lane: every ambient "flying text" (Ready / Fever / Nice / combo / power spike / timing hints ...) lives in a calm strip
## above the net, centred, out of the way of the players and the ball. One slot each for the headline, the timing / quality line
## and a small flavour line; a newer callout replaces the old one in its slot.
const LANE_Y := 0.235
const LANE_SLOT_Y := {"main": 0.0, "sub": 92.0, "sub2": 150.0}
var _lane := {}


func _build_banner() -> void:
	banner = UIKit.label("", 150, Color.WHITE, 26, UIKit.INK)          # (kept for older call sites; the lane draws the text now)
	banner.modulate.a = 0.0
	banner.visible = false
	root_c.add_child(banner)


func say(slot: String, text: String, font_size: int, top: Color, bottom: Color, outline: Color, hold := 1.0, sparkle := false) -> Callout:
	var vp := get_viewport().get_visible_rect().size
	var c := Callout.make(text, font_size, top, bottom, outline)
	c.position = Vector2(vp.x * 0.5, vp.y * LANE_Y + float(LANE_SLOT_Y.get(slot, 0.0)))
	var old = _lane.get(slot)
	if old != null and is_instance_valid(old):
		(old as Callout).dismiss()
	_lane[slot] = c
	popup_layer.add_child(c)
	c.play(hold, 1.5 if slot == "main" else 1.3, 22.0, sparkle)
	return c


## headline callout in the lane (old call sites keep their arguments: `size` is the legacy 96-150 px size, scaled down for the lane)
func show_banner(text: String, color := Color.WHITE, size := 150, dur := 1.1, outline := Color(0.1, 0.15, 0.35)) -> void:
	var fs := clampi(int(float(size) * 0.62), 62, 96)
	var top := color.lerp(Color.WHITE, 0.45)
	var bottom := color.darkened(0.12)
	if color.get_luminance() > 0.93:                                   # plain white text: a cool grey-blue lower half
		bottom = Color(0.74, 0.86, 1.0)
	say("main", text, fs, top, bottom, outline, dur, size >= 120 and color != Color.WHITE)


# ------------------------------------------------------------------ match clock (top centre)
func _build_clock(vp: Vector2, inset: Dictionary) -> void:
	_clock = Control.new()
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock.position = Vector2(vp.x * 0.5 - 78.0, 14.0 + float(inset["t"]))
	_clock.size = Vector2(156, 46)
	var bg := Panel.new()
	bg.size = _clock.size
	bg.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.05, 0.14, 0.26, 0.62), 23, 2, Color(1, 1, 1, 0.55), 4))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock.add_child(bg)
	var dot := Panel.new()                                  # a small ball-coloured dot: the clock is running
	dot.position = Vector2(16, 17)
	dot.size = Vector2(12, 12)
	dot.add_theme_stylebox_override("panel", UIKit.style_box(Color("ffd24a"), 6))
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock.add_child(dot)
	_clock_lbl = UIKit.label("00:00", 34, Color.WHITE, 6, Color(0.02, 0.1, 0.22, 0.9))
	_clock_lbl.position = Vector2(30, -1)
	_clock_lbl.size = Vector2(120, 46)
	_clock.add_child(_clock_lbl)
	root_c.add_child(_clock)


func _update_clock() -> void:
	if _clock == null or director == null:
		return
	var t := int(director.match_time)
	if t != _clock_last:
		_clock_last = t
		_clock_lbl.text = "%02d:%02d" % [t / 60, t % 60]


# ------------------------------------------------------------------ combo counter (top right, tilted, elastic)
const COMBO_TIERS := [
	[4, Color("fff6b0"), Color("ffc02e"), Color("b5470f")],
	[7, Color("ffe6c0"), Color("ff8a3a"), Color("a8380c")],
	[11, Color("ffdcee"), Color("ff5aa5"), Color("a8135f")],
	[16, Color("eee2ff"), Color("a56bff"), Color("4a1fa8")],
]


func _combo_colors(n: int) -> Array:
	var best: Array = COMBO_TIERS[0]
	for t in COMBO_TIERS:
		if n >= int(t[0]):
			best = t
	return best


func _set_combo(n: int) -> void:
	if n < 4:
		if _combo_n >= 4:
			_hide_combo()
		_combo_n = n
		return
	var tier := _combo_colors(n)
	var milestone := n == 4 or n == 8 or n == 12 or n == 16 or n == 20 or n == 25
	if _combo_num != null and is_instance_valid(_combo_num):
		_combo_num.queue_free()
	_combo_num = Callout.make(str(n), 104 if n < 10 else 92, tier[1], tier[2], tier[3])
	_combo_num.position = Vector2(0, 0)
	_combo_root.add_child(_combo_num)
	if _combo_word == null or not is_instance_valid(_combo_word):
		_combo_word = Callout.make(tr("连击"), 44, Color.WHITE, Color("ffe9b0"), Color(0.35, 0.15, 0.05))
		_combo_word.position = Vector2(0, 112)
		_combo_root.add_child(_combo_word)
	_combo_num.pop(1.7 if milestone else 1.45, milestone)
	_combo_word.pop(1.3)
	# the whole badge swings: a quick tilt kick that settles at -8 degrees
	var rt := _combo_root.create_tween()
	rt.set_ignore_time_scale(true)
	_combo_root.rotation = deg_to_rad(-15.0)
	rt.tween_property(_combo_root, "rotation", deg_to_rad(-8.0), 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_show_combo_root()
	_combo_n = n


func _set_chain(n: int) -> void:
	if _combo_chain != null and is_instance_valid(_combo_chain):
		_combo_chain.queue_free()
	_combo_chain = Callout.make("Nice ×%d" % n, 46, Color("fff0f8"), Color("ff8ac8"), Color("b81e68"))
	_combo_chain.position = Vector2(0, 170)
	_combo_root.add_child(_combo_chain)
	_combo_chain.pop(1.5, n >= 3)
	_show_combo_root()


func _show_combo_root() -> void:
	_combo_root.modulate.a = 1.0
	if _combo_fade != null:
		_combo_fade.kill()
		_combo_fade = null


var _combo_fade: Tween


func _hide_combo() -> void:
	_combo_n = 0
	if _combo_root == null or _combo_root.modulate.a <= 0.01:
		return
	_combo_fade = _combo_root.create_tween()
	_combo_fade.set_ignore_time_scale(true)
	_combo_fade.tween_interval(0.5)
	_combo_fade.tween_property(_combo_root, "modulate:a", 0.0, 0.3)
	_combo_fade.tween_callback(func():
		for c in [_combo_num, _combo_word, _combo_chain]:
			if c != null and is_instance_valid(c):
				c.queue_free()
		_combo_num = null
		_combo_word = null
		_combo_chain = null)


func _build_serve_bubble() -> void:
	serve_bubble = Control.new()
	serve_bubble.visible = false
	serve_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_c.add_child(serve_bubble)
	var bub := _ActionBubble.new()
	bub.size = Vector2(128, 128)
	bub.position = Vector2(-64, -196)
	bub.icon = act_icon("serve")
	bub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	serve_bubble.add_child(bub)
	serve_pill = Panel.new()
	serve_pill.position = Vector2(-56, -72)
	serve_pill.size = Vector2(112, 42)
	serve_pill.add_theme_stylebox_override("panel", UIKit.style_box(Color("2fc7b0"), 21, 4, Color.WHITE, 8))
	serve_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	serve_bubble.add_child(serve_pill)
	var l := UIKit.label("发球", 26, Color.WHITE)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	serve_pill.add_child(l)


## "P1" tag with a little arrow above the head of every human player (instead of the 3D name label)
func _build_markers() -> void:
	for a in ms.athletes:
		if not a.is_human:
			continue
		var m := Control.new()
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col := UIKit.team_color(a.team)
		var pn := Panel.new()
		pn.position = Vector2(-36, -44)
		pn.size = Vector2(72, 36)
		pn.add_theme_stylebox_override("panel", UIKit.style_box(Color.WHITE, 18, 0, Color.WHITE, 6))
		pn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(pn)
		var l := UIKit.label("P%d" % a.player_index, 26, col.darkened(0.1), 0)
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		pn.add_child(l)
		var tri := Polygon2D.new()
		tri.polygon = PackedVector2Array([Vector2(-9, -10), Vector2(9, -10), Vector2(0, 4)])
		tri.color = Color.WHITE
		m.add_child(tri)
		root_c.add_child(m)
		markers.append({"a": a, "n": m})


func _update_markers() -> void:
	var cam := ms.cam_rig.cam
	for e in markers:
		var a: Athlete = e["a"]
		var m: Control = e["n"]
		var wp := a.global_position + Vector3(0, 1.75, 0)
		var hide := cam.is_position_behind(wp) or (director.phase == MatchDirector.P.SERVING and director.server == a and a.state == Athlete.S.SERVE_HOLD)
		m.visible = not hide
		if not hide:
			m.position = cam.unproject_position(wp) + Vector2(0, sin(Time.get_ticks_msec() * 0.006 + float(a.player_index)) * 3.0)


# ------------------------------------------------------------------ off-screen trackers
## ball icon pinned to the screen edge while the ball is out of view (a coloured streak points back at the court),
## plus an arrow bubble for a team mate who is off screen
class _EdgeTracker:
	extends Control
	var ball_show := false
	var ball_pos := Vector2.ZERO
	var ball_dir := Vector2.UP
	var ball_col := Color.WHITE
	var mate_show := false
	var mate_pos := Vector2.ZERO
	var mate_dir := Vector2.UP
	var mate_col := Color.WHITE

	func _draw() -> void:
		if ball_show:
			var back := -ball_dir
			var perp := Vector2(-back.y, back.x)
			var tail := PackedVector2Array([ball_pos + back * 30.0 + perp * 12.0, ball_pos + back * 30.0 - perp * 12.0, ball_pos + back * 92.0])
			draw_colored_polygon(tail, Color(ball_col.r, ball_col.g, ball_col.b, 0.62))
			draw_circle(ball_pos + Vector2(0, 3), 31.0, Color(0, 0, 0, 0.22))
			draw_circle(ball_pos, 31.0, Color.WHITE)
			draw_circle(ball_pos, 26.0, Color(1.0, 0.86, 0.26))
			var seam := Color(0.2, 0.42, 0.92)
			draw_arc(ball_pos + Vector2(-20, 6), 24.0, -1.0, 0.5, 12, seam, 4.0, true)
			draw_arc(ball_pos + Vector2(20, 6), 24.0, PI - 0.5, PI + 1.0, 12, seam, 4.0, true)
			draw_arc(ball_pos + Vector2(0, -24), 20.0, 0.5, PI - 0.5, 12, seam, 4.0, true)
			draw_circle(ball_pos + Vector2(-9, -10), 7.0, Color(1, 1, 1, 0.5))
			_arrow(ball_pos, ball_dir, 42.0, Color.WHITE)
		if mate_show:
			_arrow(mate_pos, mate_dir, 52.0, mate_col)

	func _arrow(c: Vector2, d: Vector2, dist: float, col: Color) -> void:
		var perp := Vector2(-d.y, d.x)
		var tip := c + d * (dist + 12.0)
		var base := c + d * dist
		draw_colored_polygon(PackedVector2Array([tip, base + perp * 10.0, base - perp * 10.0]), col)


func _build_tracker() -> void:
	tracker = _EdgeTracker.new()
	tracker.set_anchors_preset(Control.PRESET_FULL_RECT)
	tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_c.add_child(tracker)
	_mate_icon = Control.new()
	_mate_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mate_icon.visible = false
	root_c.add_child(_mate_icon)


func _human_and_mate() -> Array:
	for a in ms.athletes:
		if a.is_human:
			var m: Athlete = director.mate_of(a)
			return [a, m]
	return [null, null]


func _update_tracker(dt: float) -> void:
	var cam := ms.cam_rig.cam
	var vp := get_viewport().get_visible_rect().size
	var live: bool = director.phase == MatchDirector.P.RALLY or director.phase == MatchDirector.P.SERVING
	# --- ball
	var b := ms.ball
	var show_ball := false
	if live and b.live and not cam.is_position_behind(b.global_position):
		var sp := cam.unproject_position(b.global_position)
		var ex := 70.0 if absf(sp.x - vp.x * 0.5) > 460.0 else 180.0       # keep clear of the hint text at the top centre
		if sp.y < 46.0 or sp.x < 30.0 or sp.x > vp.x - 30.0:
			var pos := Vector2(clampf(sp.x, 80.0, vp.x - 80.0), maxf(sp.y, ex))
			tracker.ball_pos = pos
			var d := sp - pos
			tracker.ball_dir = d.normalized() if d.length() > 1.0 else Vector2.UP
			tracker.ball_col = BallRibbon.speed_color(b.vel.length())
			show_ball = true
	if show_ball != tracker.ball_show or show_ball:
		tracker.ball_show = show_ball
		tracker.queue_redraw()
	# --- team mate
	var hm := _human_and_mate()
	var h: Athlete = hm[0]
	var m: Athlete = hm[1]
	var show_mate := false
	if h != null and m != null and not m.is_human and live:
		var wp := m.global_position + Vector3(0, 1.0, 0)
		var behind := cam.is_position_behind(wp)
		var sp2 := cam.unproject_position(wp)
		var off := behind or sp2.x < 40.0 or sp2.x > vp.x - 40.0 or sp2.y < 60.0 or sp2.y > vp.y - 40.0
		_mate_off_t = _mate_off_t + dt if off else 0.0
		if _mate_off_t > 0.25:
			show_mate = true
			if behind:
				sp2 = Vector2(vp.x * 0.5, vp.y) + (Vector2(vp.x * 0.5, vp.y) - sp2)
			var pos2 := Vector2(clampf(sp2.x, 70.0, vp.x - 70.0), clampf(sp2.y, 130.0, vp.y - 110.0))
			var d2 := sp2 - pos2
			tracker.mate_pos = pos2
			tracker.mate_dir = d2.normalized() if d2.length() > 1.0 else Vector2.DOWN
			tracker.mate_col = UIKit.team_color(m.team)
			if _mate_id != String(m.entry_id()):
				_mate_id = String(m.entry_id())
				for c in _mate_icon.get_children():
					c.queue_free()
				var av := UIKit.avatar(_mate_id, 74, UIKit.team_color(m.team), 5)
				av.position = Vector2(-37, -37)
				_mate_icon.add_child(av)
			_mate_icon.position = pos2
	else:
		_mate_off_t = 0.0
	_mate_icon.visible = show_mate
	if show_mate != tracker.mate_show or show_mate:
		tracker.mate_show = show_mate
		tracker.queue_redraw()


# ------------------------------------------------------------------ toasts (achievements / missions / level up)
## round badge: gold star for achievements, green tick for missions, blue arrow for level ups
class _Badge:
	extends Control
	var kind := "ach"

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		var base := Color("ffc93c")
		if kind == "mission":
			base = Color("4fd16b")
		elif kind == "level":
			base = Color("3aa8ff")
		draw_circle(c + Vector2(0, 3), r, Color(0, 0, 0, 0.22))
		draw_circle(c, r, Color.WHITE)
		draw_circle(c, r - 4.0, base)
		draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.42, Color(1, 1, 1, 0.28))
		match kind:
			"mission":
				var pts := PackedVector2Array([c + Vector2(-r * 0.42, 0.0), c + Vector2(-r * 0.12, r * 0.32), c + Vector2(r * 0.46, -r * 0.34)])
				draw_polyline(pts, Color.WHITE, 6.0, true)
			"level":
				var tri := PackedVector2Array([c + Vector2(0, -r * 0.5), c + Vector2(r * 0.46, r * 0.14), c + Vector2(r * 0.16, r * 0.14), c + Vector2(r * 0.16, r * 0.5),
						c + Vector2(-r * 0.16, r * 0.5), c + Vector2(-r * 0.16, r * 0.14), c + Vector2(-r * 0.46, r * 0.14)])
				draw_colored_polygon(tri, Color.WHITE)
			_:
				var star := PackedVector2Array()
				for i in 10:
					var a := -PI / 2.0 + PI * float(i) / 5.0
					var rr := r * (0.58 if i % 2 == 0 else 0.26)
					star.append(c + Vector2(cos(a), sin(a)) * rr)
				draw_colored_polygon(star, Color.WHITE)


var _toasts: Array = []
var _toast_busy := false


func show_toast(kind: String, title: String, sub: String) -> void:
	_toasts.append([kind, title, sub])
	if not _toast_busy:
		_next_toast()


func _next_toast() -> void:
	if _toasts.is_empty():
		_toast_busy = false
		return
	_toast_busy = true
	var t: Array = _toasts.pop_front()
	var vp := get_viewport().get_visible_rect().size
	var inset: Dictionary = Game.safe_insets()
	var card := Panel.new()
	card.size = Vector2(440, 100)
	card.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.08, 0.2, 0.3, 0.92), 50, 3, Color(1, 1, 1, 0.9), 10))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bd := _Badge.new()
	bd.kind = String(t[0])
	bd.position = Vector2(10, 10)
	bd.size = Vector2(80, 80)
	card.add_child(bd)
	var l1 := UIKit.label(String(t[1]), 30, Color("fff3a0") if t[0] == "ach" else Color("c8fff0"), 6, Color(0.03, 0.12, 0.2, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	l1.position = Vector2(102, 12)
	l1.size = Vector2(320, 40)
	card.add_child(l1)
	var l2 := UIKit.label(String(t[2]), 22, Color.WHITE, 4, Color(0.03, 0.12, 0.2, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	l2.position = Vector2(102, 52)
	l2.size = Vector2(330, 36)
	card.add_child(l2)
	var x_on := vp.x - 470.0 - float(inset["r"])
	card.position = Vector2(vp.x + 20.0, 136.0 + float(inset["t"]))
	root_c.add_child(card)
	Sfx.play("ui_confirm", -6.0)
	var tw := card.create_tween()
	tw.tween_property(card, "position:x", x_on, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.6)
	tw.tween_property(card, "position:x", vp.x + 20.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		card.queue_free()
		_next_toast())


func _on_achievement(a: Dictionary) -> void:
	show_toast("ach", "成就解锁: %s" % a["name"], "%s   +%d 经验" % [a["desc"], int(a.get("xp", 0))])


func _on_mission_done(m: Dictionary) -> void:
	show_toast("mission", "每日任务完成!", "%s   +%d 经验" % [m["text"], int(m["xp"])])


func _on_level_up(lv: int) -> void:
	show_toast("level", "升级! Lv.%d" % lv, "继续比赛来解锁更多拖尾 / 球 / 球场")


# ------------------------------------------------------------------ speed lines + timing ring
## radial white streaks around the screen edge for a big hit
class _SpeedLines:
	extends Control
	var life := 0.0
	var total := 0.3
	var strength := 1.0

	func trigger(dur: float, s: float) -> void:
		total = maxf(dur, 0.05)
		life = dur
		strength = s
		visible = true

	func _process(dt: float) -> void:
		if life <= 0.0:
			visible = false
			return
		life -= dt / maxf(Engine.time_scale, 0.05)      # real time: it must also play during the hit-stop
		queue_redraw()

	func _draw() -> void:
		var a := clampf(life / total, 0.0, 1.0)
		var c := size * 0.5
		var rng := RandomNumberGenerator.new()
		rng.seed = int(Time.get_ticks_msec() / 45)        # re-rolls every 2-3 frames: a hand-drawn flicker
		var rmax := c.length()
		for i in 54:
			var ang := rng.randf() * TAU
			var d := Vector2(cos(ang), sin(ang))
			var r0 := rmax * rng.randf_range(0.58, 0.86)
			var r1 := rmax * rng.randf_range(0.96, 1.12)
			draw_line(c + d * r0, c + d * r1, Color(1, 1, 1, a * strength * rng.randf_range(0.22, 0.6)), rng.randf_range(2.0, 5.5))


## shrinking ring around the ball: the moment it reaches the small inner ring is the moment to hit
class _TimingRing:
	extends Control
	## "Hit NOW" guide around the ball: a FIXED target ring and a ring that shrinks onto it. The shrink is driven by the distance to
	## the ideal contact point, so the moment the moving ring lands on the target IS the perfect window (white = early, yellow =
	## good window, green = perfect window + a flash). Same shapes and colours every time, so the timing becomes muscle memory.
	var centre := Vector2.ZERO
	var radius := 150.0
	var target_r := 42.0
	var level := 0
	var alpha := 0.0
	var pop := 0.0

	func _draw() -> void:
		if alpha <= 0.01:
			return
		var a := alpha
		var perfect := level == 2
		var tcol := Color(0.55, 1.0, 0.7, a) if perfect else Color(1, 1, 1, 0.92 * a)
		# the target ring (fixed): soft glow + crisp line + four small notches
		draw_arc(centre, target_r, 0.0, TAU, 56, Color(tcol.r, tcol.g, tcol.b, 0.2 * a), 16.0, true)
		draw_arc(centre, target_r, 0.0, TAU, 56, tcol, 5.0, true)
		for i in 4:
			var ang := PI * 0.5 * float(i) + PI * 0.25
			var d := Vector2(cos(ang), sin(ang))
			draw_line(centre + d * (target_r + 4.0), centre + d * (target_r + 14.0), tcol, 4.0, true)
		if perfect:
			draw_circle(centre, target_r - 3.0, Color(0.45, 1.0, 0.62, 0.2 * a))
		# the shrinking ring
		var col := Color(1, 1, 1, 0.9 * a)
		var w := 6.0
		if level == 1:
			col = Color(1.0, 0.9, 0.3, a)
			w = 9.0
		elif perfect:
			col = Color(0.45, 1.0, 0.62, a)
			w = 12.0
		draw_arc(centre, radius, 0.0, TAU, 72, Color(col.r, col.g, col.b, 0.22 * a), w + 12.0, true)
		draw_arc(centre, radius, 0.0, TAU, 72, col, w, true)
		# the flash when the perfect window opens
		if pop > 0.01:
			draw_arc(centre, target_r + 46.0 * (1.0 - pop), 0.0, TAU, 56, Color(1, 1, 1, 0.8 * pop * a), 8.0, true)


var _ring_shot_done := false
var speed_lines: _SpeedLines
var timing_ring: _TimingRing


func _build_feel_layers() -> void:
	speed_lines = _SpeedLines.new()
	speed_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	speed_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_lines.visible = false
	root_c.add_child(speed_lines)
	timing_ring = _TimingRing.new()
	timing_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	timing_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_c.add_child(timing_ring)


## white flash over the whole picture for a frame or two (perfect smashes)
func flash_screen(alpha := 0.2, dur := 0.12) -> void:
	if _flash == null:
		_flash = ColorRect.new()
		_flash.color = Color(1, 1, 1, 0)
		_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root_c.add_child(_flash)
		root_c.move_child(_flash, 0)
	_flash.color = Color(1, 1, 1, alpha)
	var tw := _flash.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(_flash, "color:a", 0.0, dur)


func flash_speed_lines(dur: float, strength := 1.0) -> void:
	if speed_lines != null:
		speed_lines.trigger(dur, strength)


func _update_timing_ring(dt: float) -> void:
	var h: Athlete = null
	for a in ms.athletes:
		if a.is_human:
			h = a
			break
	var want := false
	var near := 0.0                    # touch HIT button pulse: 0 = nothing to hit yet, -> 1 as the ball arrives
	var hit_kind := "bump"
	if h != null and director.phase != MatchDirector.P.POINT and ms.ball.live and h.state != Athlete.S.KNOCKED 			and h.state != Athlete.S.STUMBLE and director.can_hit(h):
		var kind: String = h._choose_kind()
		hit_kind = kind
		var dist := h.hit_distance(kind)
		var ip: Vector3 = h.ideal_point(kind)
		var to := ip - ms.ball.global_position
		var closing := ms.ball.vel.dot(to.normalized()) if to.length() > 0.001 else 0.0
		if dist < 4.2 and closing > 1.0:
			var eta := dist / closing
			if eta < 1.2:
				near = 1.0 - clampf(eta / 0.75, 0.0, 1.0)
				if Game.settings.get("timing_guide", true) and dist < 2.4:
					want = true
					var w := h.timing_window_scale()
					var pe := 0.36 * w                                       # the perfect window (see Athlete._quality_of)
					var ge := 0.66 * w
					var u := clampf((dist - pe) / (1.8 - pe), 0.0, 1.0)
					timing_ring.radius = timing_ring.target_r + (150.0 - timing_ring.target_r) * pow(u, 0.85)
					var lv := 2 if dist < pe else (1 if dist < ge else 0)
					if lv == 2 and timing_ring.level < 2:
						timing_ring.pop = 1.0
						Sfx.play("ui_hover", -11.0, 1.7)                      # one soft tick as the perfect window opens
					timing_ring.level = lv
					var cam := ms.cam_rig.cam
					if not cam.is_position_behind(ms.ball.global_position):
						timing_ring.centre = cam.unproject_position(ms.ball.global_position)
					else:
						want = false
	if touch != null and is_instance_valid(touch):
		touch.set_hit_hint(near, hit_kind, dt)
	timing_ring.alpha = move_toward(timing_ring.alpha, 1.0 if want else 0.0, dt * (9.0 if want else 12.0))
	timing_ring.pop = maxf(timing_ring.pop - dt * 4.0, 0.0)
	if not want and timing_ring.alpha < 0.05:
		timing_ring.level = 0
	if want and timing_ring.alpha > 0.9 and Game.main != null and Game.main.dev.has("ringshot") and not _ring_shot_done and timing_ring.radius < 90.0:
		_ring_shot_done = true
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(str(Game.main.dev["ringshot"]))
	timing_ring.queue_redraw()


# ------------------------------------------------------------------ hype gauge + fever frame
## flame icon + pill gauge: fills with the team's excitement, shows the remaining time during fever
class _HypeBar:
	extends Control
	var _sb_track := StyleBoxFlat.new()
	var _sb_fill := StyleBoxFlat.new()
	var _sb_gloss := StyleBoxFlat.new()
	var value := 0.0
	var fever := 0.0                  # 0 = not in fever, else 0..1 = fraction of fever time left
	var _t := 0.0

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	static func flame(c: Vector2, s: float, col: Color, inner: Color) -> Array:
		var pts := PackedVector2Array([Vector2(0.0, -1.0), Vector2(0.28, -0.5), Vector2(0.55, -0.08), Vector2(0.5, 0.45), Vector2(0.22, 0.85), Vector2(0.0, 0.95),
				Vector2(-0.22, 0.85), Vector2(-0.5, 0.45), Vector2(-0.55, -0.08), Vector2(-0.3, -0.38), Vector2(-0.12, -0.2)])
		var outer := PackedVector2Array()
		var inn := PackedVector2Array()
		for p in pts:
			outer.append(c + p * s)
			inn.append(c + Vector2(p.x * 0.55, p.y * 0.55 + 0.28) * s)
		return [outer, inn, col, inner]

	func _draw() -> void:
		var h := size.y
		var in_fever := fever > 0.0
		var pulse := 0.5 + 0.5 * sin(_t * 10.0)
		var x0 := h * 0.95
		var w := size.x - x0
		var r := h * 0.5 - 2.0
		# gauge: a rounded pill with a glossy gradient fill and a spark at the tip (same language as the score bars)
		var bh := h * 0.5
		var bg := Rect2(Vector2(x0, (h - bh) * 0.5), Vector2(w, bh))
		_sb_track.set_corner_radius_all(int(bh * 0.5))
		_sb_track.bg_color = Color(0.04, 0.12, 0.24, 0.62)
		_sb_track.set_border_width_all(3)
		_sb_track.border_color = Color(1, 1, 1, 0.92)
		_sb_track.shadow_size = 6
		_sb_track.shadow_color = Color(0, 0, 0, 0.25)
		_sb_track.shadow_offset = Vector2(0, 3)
		draw_style_box(_sb_track, bg)
		var frac := clampf(fever if in_fever else value, 0.0, 1.0)
		if frac > 0.004:
			var fw := maxf((bg.size.x - 8.0) * frac, bh - 8.0)
			var fill := Rect2(bg.position + Vector2(4, 4), Vector2(fw, bh - 8.0))
			var col := Color("ffd24a").lerp(Color("ff6a2a"), frac)
			if in_fever:
				col = col.lightened(0.15 * pulse)
			_sb_fill.set_corner_radius_all(int((bh - 8.0) * 0.5))
			_sb_fill.bg_color = col
			_sb_fill.anti_aliasing = true
			draw_style_box(_sb_fill, fill)
			_sb_gloss.set_corner_radius_all(int((bh - 8.0) * 0.25))
			_sb_gloss.bg_color = Color(1, 1, 1, 0.3)
			draw_style_box(_sb_gloss, Rect2(fill.position + Vector2(6, 2), Vector2(maxf(fill.size.x - 12.0, 2.0), fill.size.y * 0.38)))
			if in_fever or frac > 0.5:
				var tip := fill.position + Vector2(fill.size.x - 3.0, fill.size.y * 0.5)
				draw_circle(tip, 5.0 + 3.0 * pulse, Color(1, 1, 0.85, 0.45 + 0.4 * pulse))
		# flame emblem (Gemini sticker icon); it swells and flickers during fever time
		var tex := _flame_tex()
		var k := 1.0 + (0.12 * pulse if in_fever else 0.03 * sin(_t * 3.0))
		var fs := h * 1.12 * k
		var fc := Vector2(h * 0.5, h * 0.5 + (0.0 if not in_fever else -2.0 * pulse))
		if tex != null:
			draw_texture_rect(tex, Rect2(fc - Vector2(fs, fs) * 0.5, Vector2(fs, fs)), false)
		else:
			draw_circle(fc, r, Color("ff7a2e"))

	static var _ftex: Texture2D
	static func _flame_tex() -> Texture2D:
		if _ftex == null and ResourceLoader.exists("res://assets/ui/emb_flame.png"):
			_ftex = load("res://assets/ui/emb_flame.png")
		return _ftex


var hype_bar: _HypeBar
var fever_frame: ColorRect
var _fever_shown := 0.0


func _build_hype() -> void:
	var inset: Dictionary = Game.safe_insets()
	hype_bar = _HypeBar.new()
	hype_bar.position = Vector2(30 + float(inset["l"]), 262 + float(inset["t"]))
	hype_bar.size = Vector2(300, 40)
	hype_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_c.add_child(hype_bar)
	fever_frame = ColorRect.new()
	fever_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	fever_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/fever_frame.gdshader")
	fever_frame.material = sm
	fever_frame.color = Color.WHITE
	fever_frame.visible = false
	root_c.add_child(fever_frame)
	root_c.move_child(fever_frame, 0)
	director.fever_started.connect(_on_fever_started)
	director.fever_ended.connect(_on_fever_ended)


func _on_fever_started(team: int) -> void:
	if team == 0 or Game.mode == "versus":
		show_banner("热血时刻!", Color("ffd24a"), 128, 1.0, Color("c4501a"))


func _on_fever_ended(_team: int) -> void:
	pass


func _update_hype_ui(dt: float) -> void:
	var team := 0
	var in_fever := director.is_fever(team)
	hype_bar.value = float(director.hype[team])
	hype_bar.fever = float(director.fever_left[team]) / MatchDirector.FEVER_TIME if in_fever else 0.0
	_fever_shown = move_toward(_fever_shown, 1.0 if in_fever else 0.0, dt * 3.0)
	fever_frame.visible = _fever_shown > 0.01
	if fever_frame.visible:
		(fever_frame.material as ShaderMaterial).set_shader_parameter("intensity", _fever_shown)


# ------------------------------------------------------------------ practice modes (rally challenge / training)
class _Hearts:
	extends Control
	var lives := 3
	var total := 3

	func _heart(c: Vector2, s: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 28:
			var t := TAU * float(i) / 28.0
			var x := 16.0 * pow(sin(t), 3.0)
			var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
			pts.append(c + Vector2(x, y) * s)
		return pts

	func _draw() -> void:
		for i in total:
			var c := Vector2(22.0 + float(i) * 46.0, 22.0)
			var alive := i < lives
			var poly := _heart(c, 1.18)
			draw_colored_polygon(poly, Color("ff4f6e") if alive else Color(0.75, 0.78, 0.85, 0.7))
			if alive:
				draw_circle(c + Vector2(-6.0, -6.0), 4.0, Color(1, 1, 1, 0.55))
			draw_polyline(poly + PackedVector2Array([poly[0]]), Color(0.3, 0.1, 0.2, 0.9) if alive else Color(0.5, 0.52, 0.6, 0.8), 2.5, true)


class _MedalRow:
	extends Control
	var best := 0

	func _draw() -> void:
		var font: Font = ThemeDB.fallback_font
		if get_theme_default_font():
			font = get_theme_default_font()
		for i in Profile.MEDALS.size():
			var m: Dictionary = Profile.MEDALS[i]
			var c := Vector2(30.0 + float(i) * 120.0, 28.0)
			var got := best >= int(m["goal"])
			var col: Color = m["color"]
			draw_circle(c + Vector2(0, 3), 24.0, Color(0, 0, 0, 0.18))
			draw_circle(c, 24.0, Color.WHITE)
			draw_circle(c, 20.0, col if got else Color(0.8, 0.83, 0.9, 0.9))
			if got:
				draw_circle(c + Vector2(-6.0, -6.0), 7.0, Color(1, 1, 1, 0.45))
			draw_string(font, c + Vector2(-22.0, 54.0), "%d" % int(m["goal"]), HORIZONTAL_ALIGNMENT_CENTER, 44.0, 22, Color(0.9, 0.96, 1.0))


class _Check:
	extends Control
	var on := false

	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color.WHITE)
		draw_circle(c, r - 3.0, Color("2fc7b0") if on else Color(0.62, 0.66, 0.7))
		if on:
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.42, 0), c + Vector2(-r * 0.1, r * 0.34), c + Vector2(r * 0.48, -r * 0.34)]), Color.WHITE, 5.0, true)
		else:
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.42, 0), c + Vector2(-r * 0.1, r * 0.34), c + Vector2(r * 0.48, -r * 0.34)]), Color(0.82, 0.85, 0.88), 5.0, true)


var scoreboard_holder: Control
var _pr_panel: Control
var _pr_cur: Label
var _pr_best: Label
var _pr_hearts: _Hearts
var _pr_medals: _MedalRow
var _pr_title: Label
var _co_rows: Array = []
var _co_banner: Control
var _co_title: Label
var _co_tip_rich: RichTextLabel
var _co_step: Label
var _co_count: Label
var _medal_seen := 0


func _build_practice() -> void:
	if not director.is_practice():
		return
	scoreboard_holder.visible = false
	var inset: Dictionary = Game.safe_insets()
	var pos := Vector2(30.0 + float(inset["l"]), 24.0 + float(inset["t"]))
	if director.mode_rules == "rally":
		_pr_panel = GW.board(Vector2(440, 258), Color(0.06, 0.2, 0.32, 0.88), Color(1, 1, 1, 0.9), 0.045)
		_pr_panel.position = pos
		root_c.add_child(_pr_panel)
		_pr_title = UIKit.label("回合挑战", 28, Color("8fe9d2"), 6, Color(0.02, 0.1, 0.2, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
		_pr_title.position = Vector2(44, 12)
		_pr_title.size = Vector2(220, 40)
		_pr_panel.add_child(_pr_title)
		_pr_cur = UIKit.label("0", 92, Color.WHITE, 14, Color(0.1, 0.35, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
		_pr_cur.position = Vector2(44, 40)
		_pr_cur.size = Vector2(190, 100)
		_pr_panel.add_child(_pr_cur)
		var unit := UIKit.label("次触球", 24, Color(0.75, 0.88, 0.95), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		unit.position = Vector2(162, 94)
		unit.size = Vector2(120, 34)
		_pr_panel.add_child(unit)
		_pr_hearts = _Hearts.new()
		_pr_hearts.position = Vector2(262, 22)
		_pr_hearts.size = Vector2(160, 44)
		_pr_hearts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pr_panel.add_child(_pr_hearts)
		_pr_best = UIKit.label("最佳 0", 28, Color("ffe14a"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		_pr_best.position = Vector2(262, 80)
		_pr_best.size = Vector2(170, 40)
		_pr_panel.add_child(_pr_best)
		_pr_medals = _MedalRow.new()
		_pr_medals.position = Vector2(40, 140)
		_pr_medals.size = Vector2(380, 70)
		_pr_medals.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pr_panel.add_child(_pr_medals)
		hype_bar.position = Vector2(pos.x + 4.0, pos.y + 268.0)
		director.practice_rally_over.connect(_on_practice_rally_over)
	elif director.mode_rules == "training" and ms.coach != null:
		_build_tutorial_ui()
		hype_bar.position = Vector2(pos.x + 4.0, pos.y + 4.0)
		ms.coach.changed.connect(_refresh_coach)
		ms.coach.finished.connect(func(): show_banner("教学完成!", Color("ffd24a"), 120, 1.4, Color("c4501a")))
		_refresh_coach()


## the reference game's tutorial look: a dark title pill + instruction banner at the top, a step card with check circles
func _build_tutorial_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var inset: Dictionary = Game.safe_insets()
	_co_banner = Control.new()
	# the coach text sits in the lower part of the screen (above the key prompts), clear of the sky and the action
	_co_banner.position = Vector2(vp.x * 0.5 - 500.0, vp.y - 262.0 - float(inset["b"]))
	_co_banner.size = Vector2(1000, 150)
	_co_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_c.add_child(_co_banner)
	var panel := Panel.new()
	panel.position = Vector2(0, 38)
	panel.size = Vector2(1000, 86)
	panel.add_theme_stylebox_override("panel", UIKit.style_box(Color(1, 1, 1, 0.9), 30, 0, Color.WHITE, 10))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_co_banner.add_child(panel)
	var pill := Panel.new()
	pill.position = Vector2(0, 0)
	pill.size = Vector2(260, 52)
	pill.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.24, 0.3, 0.33, 0.95), 26, 0, Color.WHITE, 6))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_co_banner.add_child(pill)
	_co_title = UIKit.label("", 30, Color.WHITE)
	_co_title.size = pill.size
	pill.add_child(_co_title)
	_co_tip_rich = RichTextLabel.new()
	_co_tip_rich.bbcode_enabled = true
	_co_tip_rich.fit_content = false
	_co_tip_rich.scroll_active = false
	_co_tip_rich.position = Vector2(34, 54)
	_co_tip_rich.size = Vector2(940, 62)
	_co_tip_rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_co_tip_rich.add_theme_font_size_override("normal_font_size", 32)
	_co_tip_rich.add_theme_color_override("default_color", Color(0.18, 0.22, 0.3))
	_co_banner.add_child(_co_tip_rich)
	# step card (right side)
	_pr_panel = Panel.new()
	_pr_panel.size = Vector2(340, 190)
	# step card: right side, a little below the middle (on phones higher, clear of the jump / dive buttons)
	_pr_panel.position = Vector2(vp.x - 340.0 - 36.0 - float(inset["r"]), vp.y * (0.34 if Game.is_touch else 0.5))
	_pr_panel.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.93, 0.95, 0.96, 0.95), 30, 0, Color.WHITE, 10))
	_pr_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_c.add_child(_pr_panel)
	_co_step = UIKit.label("", 40, Color(0.22, 0.27, 0.32))
	_co_step.position = Vector2(0, 14)
	_co_step.size = Vector2(340, 56)
	_pr_panel.add_child(_co_step)
	_co_rows.clear()
	for i in 3:
		var ck := _Check.new()
		ck.position = Vector2(34.0 + 100.0 * float(i), 92)
		ck.size = Vector2(72, 72)
		ck.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pr_panel.add_child(ck)
		_co_rows.append(ck)
	_co_count = UIKit.label("", 44, Color(0.18, 0.5, 0.45))
	_co_count.position = Vector2(0, 92)
	_co_count.size = Vector2(340, 72)
	_pr_panel.add_child(_co_count)


func _refresh_coach() -> void:
	var coach: TrainingCoach = ms.coach
	if coach == null or _co_banner == null:
		return
	var cur := coach.current()
	if cur.is_empty():
		_co_title.text = "全部完成"
		_co_tip_rich.text = Loc.t("[color=#e0307f]教学完成![/color]  马上结算奖励…")
		_co_step.text = "毕业!"
		for ck in _co_rows:
			(ck as _Check).on = true
			(ck as _Check).queue_redraw()
		_co_count.text = ""
		return
	_co_title.text = String(cur["title"])
	_co_tip_rich.text = Loc.t(String(cur["tip"])).replace("[b]", "[color=#e0307f]").replace("[/b]", "[/color]")
	_co_step.text = "%s!" % cur["title"]
	var need := int(cur["need"])
	var have := coach.count_of(String(cur["id"]))
	var circles := need <= 3
	for i in _co_rows.size():
		var ck := _co_rows[i] as _Check
		ck.visible = circles
		ck.on = i < have
		ck.queue_redraw()
	_co_count.text = "" if circles else "%d / %d" % [have, need]


func _on_practice_rally_over(length: int, lost: bool) -> void:
	if lost:
		show_banner("失误!  %d 连击" % length, Color("ff6b6b"), 96, 1.0, Color(0.35, 0.05, 0.1))
	elif length >= 3:
		show_banner("%d 连击!" % length, Color("c8fff0"), 96, 1.0, Color("17806f"))


func _update_practice() -> void:
	if _pr_panel == null or director.mode_rules != "rally":
		return
	var cur := director.rally_len if director.phase == MatchDirector.P.RALLY else 0
	_pr_cur.text = str(cur)
	_pr_best.text = "最佳 %d" % maxi(director.rally_best, cur)
	_pr_hearts.lives = director.lives
	_pr_hearts.queue_redraw()
	var best := maxi(director.rally_best, cur)
	_pr_medals.best = best
	_pr_medals.queue_redraw()
	var lvl := 0
	for i in Profile.MEDALS.size():
		if best >= int(Profile.MEDALS[i]["goal"]):
			lvl = i + 1
	if lvl > _medal_seen:
		_medal_seen = lvl
		var m: Dictionary = Profile.MEDALS[lvl - 1]
		show_toast("ach", "%s达成!" % m["name"], "回合连续 %d 次触球  +%d 经验" % [int(m["goal"]), int(m["xp"])])


# ------------------------------------------------------------------ pause
func _build_pause_button() -> void:
	var b := Button.new()
	b.text = "II"
	b.flat = false
	b.custom_minimum_size = Vector2(76, 76)
	b.add_theme_font_size_override("font_size", 34)
	b.add_theme_stylebox_override("normal", UIKit.style_box(Color(1, 1, 1, 0.82), 38, 0, Color.WHITE, 8))
	b.add_theme_stylebox_override("hover", UIKit.style_box(Color(1, 1, 1, 1.0), 38, 0, Color.WHITE, 10))
	b.add_theme_stylebox_override("pressed", UIKit.style_box(Color(0.85, 0.9, 1.0, 1.0), 38, 0, Color.WHITE, 4))
	b.add_theme_color_override("font_color", UIKit.INK)
	b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	var inset: Dictionary = Game.safe_insets()
	b.position = Vector2(-102 - float(inset["r"]), 24 + float(inset["t"]))
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): ms.toggle_pause())
	root_c.add_child(b)
	_pause_btn = b


var _pause_main: Control
var _pause_sub: Control


## pause menu in the reference game's style: no panel, just a blurred picture, a heading and a stack of pills
func _build_pause_menu() -> void:
	pause_root = Control.new()
	pause_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_root.visible = false
	pause_root.process_mode = Node.PROCESS_MODE_ALWAYS
	root_c.add_child(pause_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var blur := ShaderMaterial.new()
	blur.shader = load("res://shaders/ui_blur.gdshader")
	dim.material = blur
	pause_root.add_child(dim)
	# ---- main page
	_pause_main = Control.new()
	_pause_main.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_root.add_child(_pause_main)
	var rb := GW.ribbon("暂停", 460.0, 96.0, UIKit.TEAL, 60)
	rb.set_anchors_preset(Control.PRESET_CENTER_TOP)
	rb.position = Vector2(-230, 150)
	_pause_main.add_child(rb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	vb.set_anchors_preset(Control.PRESET_CENTER_TOP)
	vb.position = Vector2(-280, 290)
	_pause_main.add_child(vb)
	var resume := UIKit.button("继续比赛", Vector2(560, 84), UIKit.GREEN, 40)
	resume.name = "Resume"
	resume.pressed.connect(func(): ms.toggle_pause())
	vb.add_child(resume)
	var again := UIKit.button("重新开始本局", Vector2(560, 76), UIKit.BLUE, 36)
	again.pressed.connect(func():
		get_tree().paused = false
		Game.start_match())
	vb.add_child(again)
	var settings_btn := UIKit.button("更改比赛设置", Vector2(560, 76), UIKit.BLUE, 36)
	settings_btn.pressed.connect(func():
		get_tree().paused = false
		Game.goto("menu", {"page": "mode"}))
	vb.add_child(settings_btn)
	var snd := UIKit.button("声音与提示", Vector2(560, 76), UIKit.BLUE, 36)
	snd.pressed.connect(func(): _pause_page(true))
	vb.add_child(snd)
	var cam := UIKit.button("切换镜头 (C)", Vector2(560, 76), UIKit.BLUE, 36)
	cam.pressed.connect(func(): ms.cam_rig.set_style((ms.cam_rig.style + 1) % 3))
	vb.add_child(cam)
	var quit := UIKit.button("退出到主菜单", Vector2(560, 76), UIKit.BLUE, 36)
	quit.pressed.connect(func():
		get_tree().paused = false
		Game.goto("menu"))
	vb.add_child(quit)
	# ---- sound & hints page
	_pause_sub = Control.new()
	_pause_sub.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_sub.visible = false
	pause_root.add_child(_pause_sub)
	var rb2 := GW.ribbon("声音与提示", 620.0, 96.0, UIKit.TEAL, 56)
	rb2.set_anchors_preset(Control.PRESET_CENTER_TOP)
	rb2.position = Vector2(-310, 130)
	_pause_sub.add_child(rb2)
	var vb2 := VBoxContainer.new()
	vb2.add_theme_constant_override("separation", 14)
	vb2.set_anchors_preset(Control.PRESET_CENTER_TOP)
	vb2.position = Vector2(-390, 270)
	_pause_sub.add_child(vb2)
	vb2.add_child(GW.row_pill("音乐", GW.slider(float(Game.settings["music"]), func(v): Game.settings["music"] = v; Game.apply_settings(), 380.0), 780.0, 74.0, 260.0))
	vb2.add_child(GW.row_pill("音效", GW.slider(float(Game.settings["sfx"]), func(v): Game.settings["sfx"] = v; Game.apply_settings(), 380.0), 780.0, 74.0, 260.0))
	vb2.add_child(GW.row_pill("自动跑位辅助", UIKit.toggle_pill(bool(Game.settings["assist"]), func(v): Game.settings["assist"] = v; Game.save_settings()), 780.0, 74.0, 420.0))
	vb2.add_child(GW.row_pill("击球时机提示圈", UIKit.toggle_pill(bool(Game.settings["timing_guide"]), func(v): Game.settings["timing_guide"] = v; Game.save_settings()), 780.0, 74.0, 420.0))
	var back := UIKit.button("返回", Vector2(360, 76), UIKit.GREEN, 38)
	back.name = "SubBack"
	back.pressed.connect(func(): Game.save_settings(); _pause_page(false))
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(780, 90)
	wrap.add_child(back)
	vb2.add_child(wrap)


func _pause_page(sub: bool) -> void:
	_pause_main.visible = not sub
	_pause_sub.visible = sub
	var f := pause_root.find_child("SubBack" if sub else "Resume", true, false)
	if f != null:
		(f as Control).grab_focus()


func show_pause(on: bool) -> void:
	pause_root.visible = on
	if on:
		root_c.move_child(pause_root, -1)                # above any point card / banner that is still on screen
		Sfx.play("ui_swoosh", -6.0)
		_pause_page(false)
		if Game.main != null and Game.main.dev.has("pauseshot"):
			for i in 4:
				await get_tree().process_frame
			if Game.main.dev.has("pausesub"):
				_pause_page(true)
				for i in 3:
					await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(str(Game.main.dev["pauseshot"]))
			get_tree().quit()


# ------------------------------------------------------------------ touch + tutorial
func _build_touch() -> void:
	if touch and is_instance_valid(touch):
		touch.queue_free()
		touch = null
	if Game.is_touch:
		touch = TouchControls.new()
		root_c.add_child(touch)
		touch.aim_tapped.connect(_on_aim_tap)


func _on_aim_tap(sp: Vector2) -> void:
	if ms.humans.is_empty():
		return
	var h: HumanBrain = ms.humans[0]
	var cam := ms.cam_rig.cam
	var o := cam.project_ray_origin(sp)
	var n := cam.project_ray_normal(sp)
	if absf(n.y) < 0.001:
		return
	var t := -o.y / n.y
	var pt := o + n * t
	pt.x = clampf(pt.x, -Court.HALF_W, Court.HALF_W)
	pt.z = clampf(pt.z, -Court.HALF_D, Court.HALF_D)
	pt.y = 0.0
	h.touch_aim = pt
	Sfx.play("ui_hover", -6.0)


func _build_tutorial() -> void:
	tutorial = Control.new()
	tutorial.set_anchors_preset(Control.PRESET_FULL_RECT)
	tutorial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_c.add_child(tutorial)
	if Game.is_touch:
		var l := UIKit.label("左侧滑动移动  ·  右侧按钮 击球 / 跳 / 扑  ·  点击对面场地设定落点", 26, Color.WHITE, 8, Color(0.05, 0.1, 0.25, 0.95))
		l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		l.position = Vector2(-700, -70)
		l.size = Vector2(1400, 50)
		tutorial.add_child(l)
	else:
		# keycap chips (like the button prompts of the reference game): [key, what it does]
		var pads: bool = Input.get_connected_joypads().size() > 0
		var keys := [["左摇杆", "移动"], ["A", "击球"], ["B", "跳跃"], ["X", "扑救"], ["右摇杆", "瞄准"], ["Start", "暂停"]] if pads \
				else [[_move_keys_text(), "移动"], ["%s / 左键" % Game.key_name("p1_hit"), "击球"], ["%s / 右键" % Game.key_name("p1_jump"), "跳跃"], [Game.key_name("p1_dive"), "扑救"], ["鼠标", "瞄准"], ["Esc", "暂停"]]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 26)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		row.position = Vector2(-760, -84)
		row.size = Vector2(1520, 56)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tutorial.add_child(row)
		for k in keys:
			var cell := HBoxContainer.new()
			cell.add_theme_constant_override("separation", 8)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var cap := PanelContainer.new()
			cap.add_theme_stylebox_override("panel", UIKit.style_box(Color(1, 1, 1, 0.93), 12, 0, Color.WHITE, 5, 14))
			cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var kl := UIKit.label(String(k[0]), 24, UIKit.INK)
			cap.add_child(kl)
			cell.add_child(cap)
			cell.add_child(UIKit.label(String(k[1]), 26, Color.WHITE, 8, Color(0.05, 0.1, 0.25, 0.95)))
			row.add_child(cell)
	var tw := create_tween()
	tw.tween_interval(12.0)
	tw.tween_property(tutorial, "modulate:a", 0.0, 1.0)
	tw.tween_callback(tutorial.queue_free)


# ------------------------------------------------------------------ events
func _on_phase(p: int) -> void:
	match p:
		MatchDirector.P.INTRO:
			if director.vs_time > 0.0:
				_show_vs_card()
			else:
				show_banner("READY?", UIKit.YELLOW, 140, 1.4, UIKit.INK)
				Sfx.play("countdown")
		MatchDirector.P.SERVE_PREP:
			if director.score[0] + director.score[1] == 0 and director.phase_time < 0.2:
				say("main", "GO!", 118, Color("eaffef"), Color("3ddc84"), Color("0a6a3a"), 0.95, true)
				Sfx.play("go")
				Sfx.play("whistle_long", -6.0)
			_refresh_score(false)
			if _match_point_team >= 0:
				_match_point_team = -1
				show_match_banner("赛点", director.serving_team)


func _show_vs_card() -> void:
	_vs_hold = true
	_set_replay_hud(true)
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or director.phase != MatchDirector.P.INTRO or director.vs_time <= 0.0:
		return
	var round_name := ""
	if Game.mode == "tournament":
		round_name = "锦标赛 · %s" % Game.TOURNAMENT_ROUNDS[int(Game.tournament["round"])]["name"]
	_vs_card = VsCard.new().build(ms.athletes, ms.cam_rig.cam, round_name, get_viewport().get_visible_rect().size)
	root_c.add_child(_vs_card)


func _end_vs_card() -> void:
	if _vs_card != null and is_instance_valid(_vs_card):
		_vs_card.dismiss()
	_vs_card = null
	_vs_hold = false
	_set_replay_hud(false)
	if not director.is_practice():
		scoreboard_holder.modulate.a = 0.0
		scoreboard_holder.create_tween().tween_property(scoreboard_holder, "modulate:a", 1.0, 0.4)
	show_target_banner(director.target_points)
	show_title_tag()
	await get_tree().create_timer(1.6, true, false, true).timeout
	if is_inside_tree() and director.phase == MatchDirector.P.INTRO:
		Sfx.play("countdown")


## full-width teal band like "Score 5 points to win!" in the reference game
func show_target_banner(points: int) -> void:
	var vp := get_viewport().get_visible_rect().size
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_c.add_child(c)
	var y0 := vp.y * 0.46
	var hh := 120.0
	var band := Polygon2D.new()
	band.polygon = PackedVector2Array([Vector2(60, y0), Vector2(vp.x + 60, y0), Vector2(vp.x, y0 + hh), Vector2(0, y0 + hh)])
	band.color = Color("2fc7b0")
	c.add_child(band)
	var l := UIKit.label("先得 %d 分获胜!" % points, 78, Color.WHITE, 14, Color("17806f"))
	l.position = Vector2(0, y0 + 8.0)
	l.size = Vector2(vp.x, hh - 10.0)
	c.add_child(l)
	c.position.x = -vp.x - 100.0
	var tw := c.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(c, "position:x", 0.0, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.3)
	tw.tween_property(c, "position:x", vp.x + 100.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(c.queue_free)
	Sfx.play("ui_swoosh", -4.0)


func _on_rally_event(ev: String, data: Dictionary) -> void:
	if ev == "vs_end":
		_end_vs_card()
		return
	if ev == "serve_warn":
		var n := int(data["n"])
		if n == 1:
			say("main", tr("裁判警告 1/2"), 70, Color("fff3c0"), Color("ffc02e"), Color("a8480c"), 1.6, true)
			say("sub", tr("请尽快发球!"), 44, Color.WHITE, Color("ffe08a"), Color("a8480c"), 1.4)
		else:
			say("main", tr("最后警告 2/2"), 76, Color("ffe6e6"), Color("ff6b6b"), Color("8f1224"), 1.8, true)
			say("sub", tr("再不发球将判负!"), 46, Color.WHITE, Color("ffb0b0"), Color("8f1224"), 1.6)
		return
	if ev == "match_point":
		_match_point_team = int(data["team"])
	elif ev == "hit":
		_set_combo(director.rally_len)


func _on_point(team: int, reason: String, pos: Vector3) -> void:
	_hide_combo()
	var col := UIKit.team_color(team)
	var human_team := -1
	for a in ms.athletes:
		if a.is_human:
			human_team = a.team
			break
	await get_tree().create_timer(0.25).timeout
	if director.phase != MatchDirector.P.OVER:
		show_point_card(team, reason)              # (the reason headline + the old -> new score roll, and the scoreboard follows)
	else:
		show_banner(reason, Color.WHITE, 130, 1.4, UIKit.team_dark(team))
		_refresh_score(true)


func _on_popup(text: String, kind: String, wpos: Vector3) -> void:
	if kind == "point" or kind == "info":
		return
	if kind == "inout":
		var cam := ms.cam_rig.cam
		if cam.is_position_behind(wpos):
			return
		_inout_pill(text, cam.unproject_position(wpos), wpos)
		return
	match kind:
		"perfect":
			if text.begins_with("Nice") and text.contains("×"):              # chained perfect touches: a pink line under the combo counter
				_set_chain(int(text.get_slice("×", 1)))
			elif text.begins_with("Nice"):
				say("sub", text, 56, Color("eafff8"), Color("6fe8c8"), Color("11705f"), 0.5)
			else:
				say("sub", text, 66, Color("fff6b0"), Color("ffc02e"), Color("b5470f"), 0.55, true)
		"good":
			say("sub", text, 48, Color("eaffef"), Color("8be6ad"), Color("1b6f47"), 0.45)
		"late":
			var early := text.begins_with("早")
			say("sub", tr("时机有点早!") if early else tr("时机有点晚!"), 40, Color("fffbe0") if early else Color("f0f8ff"), Color("ffd24a") if early else Color("8fc8ff"), Color(0.08, 0.14, 0.34), 0.7)
		"label":
			say("sub2", text, 40, Color("ffffff"), Color("ffc4e2"), Color("b81e68"), 0.8)


## the line call, drawn like a broadcast judge badge: IN = teal / OUT = coral, a check / cross disc, big caps and a tail pointing
## at the spot where the ball came down; when it was close, a second line says by how much
func _inout_pill(text: String, sp: Vector2, wpos: Vector3) -> void:
	var inn := text == "In"
	var col := Color("14b08a") if inn else Color("f2475f")
	var edge := minf(Court.HALF_W - absf(wpos.x), Court.HALF_D - absf(wpos.z))      # metres inside the line (negative = outside)
	var note := ""
	if inn and edge < 0.1:
		note = tr("压线球！")
	elif absf(edge) < 0.5:
		note = (tr("仅余 %d cm") if inn else tr("差 %d cm")) % int(round(maxf(absf(edge), 0.01) * 100.0))
	var vp := get_viewport().get_visible_rect().size
	var w := 232.0
	var h := 74.0 if note == "" else 100.0
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(clampf(sp.x, w * 0.5 + 24.0, vp.x - w * 0.5 - 24.0), maxf(sp.y, h + 120.0))
	popup_layer.add_child(box)
	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([Vector2(-17, -26), Vector2(17, -26), Vector2(0, -2)])
	tail.color = col
	box.add_child(tail)
	var pill := Control.new()
	pill.position = Vector2(-w * 0.5, -22.0 - h)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pill)
	pill.add_child(GW.pill_bg(Vector2(w, h), 37.0, col))
	var disc := GW.glyph("check" if inn else "cross", 54.0, Color.WHITE)
	disc.set("ink", col)
	disc.position = Vector2(11.0, 10.0)
	pill.add_child(disc)
	var main := UIKit.label(tr("界内").to_upper() if inn else tr("出界").to_upper(), 44, Color.WHITE, 8, col.darkened(0.45))
	main.position = Vector2(70.0, -3.0)
	main.size = Vector2(w - 82.0, 68.0)
	pill.add_child(main)
	if note != "":
		var nl := UIKit.label(note, 26, Color(1, 1, 1, 0.95), 4, col.darkened(0.5))
		nl.position = Vector2(14.0, 62.0)
		nl.size = Vector2(w - 28.0, 32.0)
		pill.add_child(nl)
	box.scale = Vector2(0.25, 0.25)
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.08)
	tw.parallel().tween_property(box, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if inn:
		tw.tween_property(box, "scale", Vector2(1.06, 1.06), 0.1)
		tw.tween_property(box, "scale", Vector2.ONE, 0.1)
	else:
		for i in 3:                                       # a head-shake "no"
			tw.tween_property(pill, "position:x", -w * 0.5 + 9.0, 0.045)
			tw.tween_property(pill, "position:x", -w * 0.5 - 9.0, 0.045)
		tw.tween_property(pill, "position:x", -w * 0.5, 0.045)
	tw.tween_interval(1.15)
	tw.tween_property(box, "position:y", box.position.y - 26.0, 0.3)
	tw.parallel().tween_property(box, "modulate:a", 0.0, 0.3)
	tw.tween_callback(box.queue_free)


## big centre card after a point. It opens on the OLD score, lights up the team that won the rally (team-coloured glow, hopping
## avatars, the other side dims), then the winner's numeral rolls up to the new value like an odometer with a "+1", one ring
## pulse and a few sparkles; the scoreboard at the top left changes at the same moment.
func show_point_card(winner: int, reason := "得分!") -> void:
	var card := Control.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := get_viewport().get_visible_rect().size
	card.position = Vector2(vp.x * 0.5, vp.y * 0.38)
	root_c.add_child(card)
	var new_score: int = director.score[winner]
	var old_score := maxi(new_score - 1, 0)
	var wcol := UIKit.team_color(winner)
	var groups: Array[Control] = []
	var avatars: Array = [[], []]
	var num_pos: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
	var old_l: Label = null
	var new_l: Label = null
	var glow: Panel = null
	for t in 2:
		var ids: Array = Game.team_a if t == 0 else Game.team_b
		var sgn := -1.0 if t == 0 else 1.0
		var g := Control.new()
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(g)
		groups.append(g)
		var center := Vector2(sgn * 150.0, 0.0)
		num_pos[t] = center
		if t == winner:
			glow = Panel.new()
			glow.size = Vector2(190, 190)
			glow.position = center - glow.size * 0.5
			glow.pivot_offset = glow.size * 0.5
			glow.add_theme_stylebox_override("panel", UIKit.style_box(Color(wcol.r, wcol.g, wcol.b, 0.30), 95))
			glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			glow.modulate.a = 0.0
			g.add_child(glow)
		for i in 2:
			var a := UIKit.avatar(ids[i], 92, UIKit.team_color(t), 5)
			a.position = Vector2(sgn * (330.0 + float(i) * 88.0) - (92.0 if t == 0 else 0.0), -46)
			g.add_child(a)
			avatars[t].append(a)
			var nm := Panel.new()
			nm.position = a.position + Vector2(4, 84)
			nm.size = Vector2(84, 24)
			nm.add_theme_stylebox_override("panel", UIKit.style_box(Color(0.1, 0.15, 0.3, 0.88), 12))
			nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var nl := UIKit.label(Roster.by_id(ids[i])["name"], 17, Color.WHITE)
			nl.set_anchors_preset(Control.PRESET_FULL_RECT)
			nm.add_child(nl)
			g.add_child(nm)
			avatars[t].append(nm)
		# the numeral sits in a clipping window so the odometer roll never leaks out
		var win := Control.new()
		win.position = center + Vector2(-110, -80)
		win.size = Vector2(220, 150)
		win.clip_contents = true
		win.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.add_child(win)
		var shown := old_score if t == winner else int(director.score[t])
		var lab := UIKit.label(str(shown), 120, Color.WHITE, 22, UIKit.team_dark(t))
		lab.size = win.size
		win.add_child(lab)
		if t == winner:
			old_l = lab
			new_l = UIKit.label(str(new_score), 120, Color.WHITE, 22, UIKit.team_dark(t))
			new_l.size = win.size
			new_l.position = Vector2(0, 150)
			win.add_child(new_l)
	var dash := UIKit.label("-", 100, Color.WHITE, 18, UIKit.INK)
	dash.position = Vector2(-40, -78)
	dash.size = Vector2(80, 140)
	card.add_child(dash)
	# who scored: a team-coloured caption under the numbers
	var human_teams := {}
	for a2 in ms.athletes:
		if a2.is_human:
			human_teams[a2.team] = true
	var cap_text := tr("蓝队得分") if winner == 0 else tr("粉队得分")
	if human_teams.size() == 1:
		cap_text = tr("我方得分") if human_teams.has(winner) else tr("对方得分")
	var cap := Control.new()
	cap.position = Vector2(num_pos[winner].x - 140.0, -148)         # above the winner's numeral (the headline is a full line higher)
	cap.size = Vector2(280, 56)
	cap.pivot_offset = cap.size * 0.5
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_child(GW.pill_bg(cap.size - Vector2(0, 8), 24.0, wcol))
	var cl := UIKit.label(cap_text, 28, Color.WHITE, 6, wcol.darkened(0.5))
	cl.clip_text = true
	cl.size = cap.size - Vector2(0, 8)
	cap.add_child(cl)
	cap.modulate.a = 0.0
	cap.scale = Vector2(0.7, 0.7)
	card.add_child(cap)
	# the headline (what happened): ACE! / 得分! / 出界 / 触网 ... in the lane style, above the team tag
	var hc := _reason_colors(reason, wcol)
	var head := Callout.make(reason, 84, hc[0], hc[1], hc[2])
	head.position = Vector2(0, -282)
	card.add_child(head)
	head.scale = Vector2(1.5, 1.5)
	head.modulate.a = 0.0
	var htw := head.create_tween()
	htw.tween_interval(0.12)
	htw.tween_callback(func():
		var t2 := head.create_tween().set_parallel(true)
		t2.tween_property(head, "modulate:a", 1.0, 0.1)
		t2.tween_property(head, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t2.tween_method(func(v: float): head.fill_mat.set_shader_parameter("sheen", v), -0.25, 1.25, 0.55))
	# card in
	card.modulate.a = 0.0
	card.scale = Vector2(0.8, 0.8)
	card.pivot_offset = Vector2.ZERO
	var tw := card.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.9)
	tw.tween_property(card, "modulate:a", 0.0, 0.3)
	tw.tween_callback(card.queue_free)
	# beat 1 (0.28 s): light up the winner, dim the other side, caption pops
	var t1 := card.create_tween()
	t1.tween_interval(0.28)
	t1.tween_callback(func():
		var gt := glow.create_tween().set_parallel(true)
		glow.scale = Vector2(0.6, 0.6)
		gt.tween_property(glow, "modulate:a", 1.0, 0.2)
		gt.tween_property(glow, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		groups[1 - winner].create_tween().tween_property(groups[1 - winner], "modulate", Color(1, 1, 1, 0.55), 0.25)
		var ct := cap.create_tween().set_parallel(true)
		ct.tween_property(cap, "modulate:a", 1.0, 0.18)
		ct.tween_property(cap, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		for k in avatars[winner].size():                 # the winners hop (staggered)
			var n: Control = avatars[winner][k]
			var y0 := n.position.y
			var ht := n.create_tween()
			ht.tween_interval(0.05 * float(k / 2))
			ht.tween_property(n, "position:y", y0 - 14.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			ht.tween_property(n, "position:y", y0, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT))
	# beat 2 (0.62 s): the roll
	var t2 := card.create_tween()
	t2.tween_interval(0.62)
	t2.tween_callback(func():
		var rt := old_l.create_tween().set_parallel(true)
		rt.tween_property(old_l, "position:y", -150.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		rt.tween_property(old_l, "modulate:a", 0.0, 0.3)
		var nt := new_l.create_tween()
		nt.tween_property(new_l, "position:y", 0.0, 0.36).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var pt := glow.create_tween()                      # a little punch on the glow disc as the number lands
		pt.tween_property(glow, "scale", Vector2(1.14, 1.14), 0.1)
		pt.tween_property(glow, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_refresh_score(true)                               # the scoreboard changes in the same instant
		Sfx.play("xp_tick", -5.0, 1.2)
		_point_card_fx(card, num_pos[winner], wcol))


## colours of the headline by what happened: [top, bottom, outline]
func _reason_colors(reason: String, team_col: Color) -> Array:
	match reason:
		"ACE!": return [Color("fff4b0"), Color("ffb62e"), Color("b5470f")]
		"出界", "触网", "发球失误", "发球超时": return [Color("ffeaea"), Color("ff8f98"), Color("a3182f")]
	return [Color.WHITE.lerp(team_col, 0.1), team_col.lightened(0.55), team_col.darkened(0.5)]


## "+1", one ring pulse and a handful of sparkles around the numeral that just changed (kept small on purpose)
func _point_card_fx(card: Control, at: Vector2, col: Color) -> void:
	var plus := UIKit.label("+1", 62, Color.WHITE, 12, col.darkened(0.45))
	plus.size = Vector2(120, 70)
	plus.pivot_offset = plus.size * 0.5
	var outward := -1.0 if at.x < 0.0 else 1.0                      # the "+1" rises on the outer shoulder of the numeral
	plus.position = at + Vector2(outward * 105.0 - 60.0, -125)
	plus.scale = Vector2(0.4, 0.4)
	plus.modulate.a = 0.0
	card.add_child(plus)
	var pt := plus.create_tween()
	pt.tween_property(plus, "modulate:a", 1.0, 0.1)
	pt.parallel().tween_property(plus, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pt.parallel().tween_property(plus, "position:y", plus.position.y - 34.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	pt.tween_interval(0.35)
	pt.tween_property(plus, "modulate:a", 0.0, 0.3)
	var ring := Panel.new()
	ring.size = Vector2(150, 150)
	ring.position = at - ring.size * 0.5
	ring.pivot_offset = ring.size * 0.5
	var sb := UIKit.style_box(Color(col.r, col.g, col.b, 0.0), 75, 7, col.lightened(0.25))
	ring.add_theme_stylebox_override("panel", sb)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(ring)
	var rt := ring.create_tween().set_parallel(true)
	rt.tween_property(ring, "scale", Vector2(1.9, 1.9), 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "modulate:a", 0.0, 0.55)
	rt.chain().tween_callback(ring.queue_free)
	var sp := CPUParticles2D.new()
	sp.position = at
	sp.amount = 12
	sp.lifetime = 0.65
	sp.one_shot = true
	sp.explosiveness = 1.0
	sp.emitting = true
	sp.direction = Vector2(0, -1)
	sp.spread = 180.0
	sp.initial_velocity_min = 130.0
	sp.initial_velocity_max = 250.0
	sp.damping_min = 140.0
	sp.damping_max = 200.0
	sp.scale_amount_min = 5.0
	sp.scale_amount_max = 9.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	sp.color_ramp = ramp
	card.add_child(sp)


## teal capsule in the middle of the screen ("Start", "Game!") - the reference game's cue style
func show_pill(text: String, dur := 1.1, col := Color("2fc7b0")) -> void:
	var vp := get_viewport().get_visible_rect().size
	var pill := Panel.new()
	pill.size = Vector2(maxf(400.0, 66.0 * float(text.length()) + 170.0), 108)
	pill.position = Vector2((vp.x - pill.size.x) * 0.5, vp.y * LANE_Y - pill.size.y * 0.5)
	pill.add_theme_stylebox_override("panel", UIKit.style_box(col, 54, 5, Color.WHITE, 12))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(text, 64, Color.WHITE, 12, col.darkened(0.45))
	l.size = pill.size
	pill.add_child(l)
	pill.pivot_offset = pill.size * 0.5
	pill.scale = Vector2(0.4, 0.4)
	pill.modulate.a = 0.0
	root_c.add_child(pill)
	var tw := pill.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(pill, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(pill, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(dur)
	tw.tween_property(pill, "modulate:a", 0.0, 0.25)
	tw.tween_callback(pill.queue_free)


## full-width team-coloured band with the serving pair's avatars: "Match Point"
func show_match_banner(text: String, team: int) -> void:
	var vp := get_viewport().get_visible_rect().size
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_c.add_child(c)
	var col := UIKit.team_color(team)
	var y0 := vp.y * 0.38
	var hh := 150.0
	var band := ColorRect.new()
	band.color = Color(col.r, col.g, col.b, 0.94)
	band.position = Vector2(0, y0)
	band.size = Vector2(vp.x, hh)
	c.add_child(band)
	for yy in [y0, y0 + hh - 5.0]:
		var ln := ColorRect.new()
		ln.color = Color(1, 1, 1, 0.9)
		ln.position = Vector2(0, yy)
		ln.size = Vector2(vp.x, 5)
		c.add_child(ln)
	var ids: Array = Game.team_a if team == 0 else Game.team_b
	var x0 := vp.x * 0.5 - 430.0
	for i in 2:
		var a := UIKit.avatar(ids[i], 108, col, 5)
		a.position = Vector2(x0 + float(i) * 100.0, y0 + 21.0)
		c.add_child(a)
	var l := UIKit.label(text, 112, Color.WHITE, 22, col.darkened(0.5), HORIZONTAL_ALIGNMENT_LEFT)
	l.position = Vector2(x0 + 250.0, y0 + 6.0)
	l.size = Vector2(900, 140)
	c.add_child(l)
	c.position.x = -vp.x
	var tw := c.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(c, "position:x", 0.0, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.5)
	tw.tween_property(c, "position:x", vp.x, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(c.queue_free)
	Sfx.play("ui_swoosh", -4.0)


## "排球 · court name" in the top left while the intro camera glides over the venue (like the reference's stage intro)
func show_title_tag(dur := 2.6) -> void:
	var vp := get_viewport().get_visible_rect().size
	var inset: Dictionary = Game.safe_insets()
	var box := Control.new()
	box.position = Vector2((vp.x - 820.0) * 0.5, 36.0 + float(inset["t"]))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_c.add_child(box)
	var court_name := String(Profile.item("court", ms.arena.theme_id)["name"])
	var l := UIKit.label("排球  ·  %s" % court_name, 46, Color.WHITE, 10, Color(0.05, 0.14, 0.3, 0.9))
	l.size = Vector2(820, 60)
	box.add_child(l)
	var ln := ColorRect.new()
	ln.color = Color(1, 1, 1, 0.8)
	ln.position = Vector2(160, 66)
	ln.size = Vector2(500, 3)
	box.add_child(ln)
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(box, "modulate:a", 1.0, 0.3)
	tw.tween_interval(dur)
	tw.tween_property(box, "modulate:a", 0.0, 0.4)
	tw.tween_callback(box.queue_free)


func _on_match_over(_winner: int) -> void:
	show_pill("比赛结束!", 1.5)             # the scene calls show_win_banner() after the instant replay


## diagonal band across the screen: "胜利!" + the final score + the winning pair (like the reference game's Win! card)
func show_win_banner(winner: int) -> void:
	var vp := get_viewport().get_visible_rect().size
	var human_good := winner == 0 or Game.mode == "versus"
	var col := Color("2fc7b0") if human_good else Color("7d8bb0")
	var dark := Color("17806f") if human_good else Color("424d70")
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_c.add_child(c)
	var y0 := vp.y * 0.3
	var hh := 250.0
	var skew := 120.0
	var band := Polygon2D.new()
	band.polygon = PackedVector2Array([Vector2(skew, y0), Vector2(vp.x + skew, y0), Vector2(vp.x, y0 + hh), Vector2(0, y0 + hh)])
	band.color = col
	c.add_child(band)
	for e in [[-14.0, 0.0], [hh + 6.0, 0.0]]:
		var ln := Polygon2D.new()
		ln.polygon = PackedVector2Array([Vector2(skew, y0 + e[0]), Vector2(vp.x + skew, y0 + e[0]), Vector2(vp.x + skew - 3.0, y0 + e[0] + 8.0), Vector2(skew - 3.0, y0 + e[0] + 8.0)])
		ln.color = Color(1, 1, 1, 0.9)
		c.add_child(ln)
	var txt := "胜利!"
	if Game.mode == "versus":
		txt = "A 队获胜!" if winner == 0 else "B 队获胜!"
	elif not human_good:
		txt = "再接再厉!"
	var l := UIKit.label(txt, 150, Color.WHITE, 28, dark, HORIZONTAL_ALIGNMENT_LEFT)
	l.position = Vector2(120, y0 + 38)
	l.size = Vector2(900, 180)
	c.add_child(l)
	var sc := UIKit.label("%d - %d" % [director.score[0], director.score[1]], 140, Color.WHITE, 24, dark, HORIZONTAL_ALIGNMENT_RIGHT)
	sc.position = Vector2(vp.x - 760, y0 + 42)
	sc.size = Vector2(640, 170)
	c.add_child(sc)
	var ids: Array = Game.team_a if winner == 0 else Game.team_b
	for i in 2:
		var a := UIKit.avatar(ids[i], 120, UIKit.team_color(winner), 6)
		a.position = Vector2(vp.x * 0.5 + 40.0 + float(i) * 110.0 - 110.0, y0 + 64)
		c.add_child(a)
	c.position.x = -vp.x - 200.0
	var tw := c.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(c, "position:x", 0.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.4)
	tw.tween_property(c, "position:x", vp.x + 200.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(c.queue_free)
	Sfx.play("ui_swoosh", -2.0)
	if Game.main != null and Game.main.dev.has("winshot"):
		await get_tree().create_timer(1.1, true, false, true).timeout
		get_viewport().get_texture().get_image().save_png(str(Game.main.dev["winshot"]))
		get_tree().quit()


# ------------------------------------------------------------------ per-frame
func _process(_dt: float) -> void:
	var _p := Prof.t0()
	_process_impl(_dt)
	Prof.add("hud", _p)


func _process_impl(dt: float) -> void:
	if director == null or replay_mode or _vs_hold:
		return
	_update_clock()
	_update_serve_bubble()
	_update_markers()
	_update_tracker(dt)
	_update_timing_ring(dt)
	_update_hype_ui(dt)
	_update_practice()
	_update_hint()


## during an instant replay only the scoreboard stays: hide hints, markers, rings and touch controls
func _set_replay_hud(on: bool) -> void:
	for n in [hint_panel, serve_bubble, _combo_root, _clock, timing_ring, hype_bar, popup_layer, touch, scoreboard_holder, tracker, _mate_icon, tutorial, _pause_btn]:
		if n != null and is_instance_valid(n):
			if n == scoreboard_holder and not on and director != null and director.is_practice():
				continue                                   # the practice modes have their own panels instead
			(n as CanvasItem).visible = not on
	if on:
		for n in [speed_lines, fever_frame]:
			if n != null:
				(n as CanvasItem).visible = false           # (they switch themselves back on when needed)
	for e in markers:
		(e["n"] as Control).visible = not on


func _update_serve_bubble() -> void:
	var s := director.server
	var show := s != null and director.phase == MatchDirector.P.SERVING and s.state == Athlete.S.SERVE_HOLD
	serve_bubble.visible = show
	if show:
		var cam := ms.cam_rig.cam
		var wp := s.global_position + Vector3(0, 1.95, 0)
		if not cam.is_position_behind(wp):
			serve_bubble.position = cam.unproject_position(wp)
			var bob := sin(Time.get_ticks_msec() * 0.008) * 5.0
			serve_bubble.position.y += bob
		serve_pill.add_theme_stylebox_override("panel", UIKit.style_box(UIKit.team_color(s.team), 21, 4, Color.WHITE, 8))


func _update_hint() -> void:
	var h: Athlete = null
	for a in ms.athletes:
		if a.is_human:
			h = a
			break
	var text := ""
	var sub := ""
	var icon_name := ""
	if h != null and not (director.mode_rules == "training" and director.phase == MatchDirector.P.RALLY):
		var d := director
		var hit_key := _hit_key_name()
		if d.phase == MatchDirector.P.SERVING and d.server == h:
			if h.state == Athlete.S.SERVE_HOLD:
				text = "发球"
				icon_name = "serve"
				sub = "按 %s 抛球，再按一次击球（先按跳跃可跳发）" % hit_key
			elif h.state == Athlete.S.SERVE_TOSS or h.state == Athlete.S.AIR:
				text = "击球!"
				icon_name = "serve"
				sub = "球到最高点时按 %s" % hit_key
		elif d.phase == MatchDirector.P.RALLY:
			var plan: Dictionary = d.plans[h.team]
			if plan.get("who") == h and plan.get("mode") == "play":
				var tn: int = plan["touch"]
				text = ["下一步: 垫球", "下一步: 传球", "下一步: 扣球"][clampi(tn - 1, 0, 2)]
				icon_name = ["bump", "set", "spike"][clampi(tn - 1, 0, 2)]
				# hardly any time left and the ball is far away: a dive is the only way
				var spot: Vector3 = plan["pos"]
				var far := Vector2(spot.x - h.global_position.x, spot.z - h.global_position.z).length()
				if tn == 1 and float(plan.get("margin", 1.0)) < 0.12 and far > 1.9 and h.state == Athlete.S.READY:
					text = "下一步: 扑救"
					icon_name = "dive"
				sub = "圈内球靠近时按 %s" % hit_key if tn < 3 else "起跳后在最高点按 %s 扣杀" % hit_key
				if icon_name == "dive":
					sub = "按 扑救键 飞身救球"
			elif d.last_team == 1 - h.team and d.touches[1 - h.team] == 2 and absf(h.global_position.z) < 4.2 and h.state == Athlete.S.READY:
				# the other side has just set the ball: a spike is coming - block it at the net
				text = "下一步: 拦网"
				icon_name = "block"
				sub = "在网前按 %s 起跳，举手拦网" % (Game.key_name("p1_jump") if not Game.is_touch else "跳")
	# once the basics are learned the explanatory second line goes away (less to read while playing)
	if Game.profile != null and (Game.profile.flags.get("tutorial_done", false) or int(Game.profile.stats.get("matches", 0)) >= 3) and text != "" and not text.begins_with("发球"):
		sub = ""
	if text != _hint_text:
		_hint_text = text
		var cut := text.find(": ")
		if cut > 0 and text.begins_with("下一步"):
			hint_pre.text = text.substr(0, cut + 1)
			hint_lbl.text = text.substr(cut + 2)
		else:
			hint_pre.text = ""
			hint_lbl.text = text
		hint_sub.text = sub
		_hint_icon_name = icon_name
		hint_icon.icon = act_icon(icon_name) if icon_name != "" else null
		hint_icon.visible = hint_icon.icon != null
		hint_icon.queue_redraw()
		var tw := hint_panel.create_tween()
		if text == "":
			tw.tween_property(hint_panel, "modulate:a", 0.0, 0.25)
		else:
			hint_panel.modulate.a = 0.0
			tw.tween_property(hint_panel, "modulate:a", 1.0, 0.18)
	hint_panel.position.x = (get_viewport().get_visible_rect().size.x - hint_panel.size.x) * 0.5


func _move_keys_text() -> String:
	var t := Game.key_name("p1_up") + Game.key_name("p1_left") + Game.key_name("p1_down") + Game.key_name("p1_right")
	return "WASD" if t == "WASD" else t


func _hit_key_name() -> String:
	if Game.is_touch:
		return "击球键"
	if Input.get_connected_joypads().size() > 0 and Input.is_joy_known(Input.get_connected_joypads()[0]) and Game.main and Game.main.dev.get("pad", false):
		return "A"
	return "%s / 鼠标左键" % Game.key_name("p1_hit")

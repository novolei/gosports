extends Node
## Global game state, settings persistence, input map and scene flow (autoload "Game").

signal settings_changed
signal touch_mode_changed(is_touch: bool)

const SAVE_PATH := "user://settings.cfg"

const DIFFICULTY_NAMES := ["轻松", "普通", "困难", "大师"]
const MODE_NAMES := {"solo": "单人对战", "coop": "双人合作", "versus": "双人对决", "training": "新手教学", "rally": "回合挑战", "tournament": "锦标赛"}

var settings := {
	"music": 0.7,
	"sfx": 0.9,
	"assist": true,          # auto-run to the ball landing spot when the stick is idle
	"difficulty": 1,
	"points": 11,
	"shake": true,
	"touch": "auto",         # auto | on | off
	"fullscreen": false,
	"quality": 2,            # 0 low (phones), 1 medium, 2 high
	"left_handed": false,
	"haptics": true,         # phone / gamepad vibration on hits and bumps
	"timing_guide": true,    # shrinking ring around the ball that shows the moment to hit
	"language": "auto",       # auto / zh / en (see Loc)
	"landing_hint": 1,       # where-to-stand marker: 0 off / 1 minimal / 2 standard (see Vfx._update_marks)
	"landing_hint_set": false, # the player chose a level (otherwise newcomers get the full marker for a few matches)
	"replays": true,         # instant replay after the big points and at the end of a match
	"render_scale": 0.0,     # 3D resolution scale; 0 = automatic (phones render below native resolution)
	"shadow_size": 0,        # directional shadow map; 0 = automatic
	"dbg": "",               # dev: comma separated render kill switches (see Game.dbg) for phone profiling
}

var is_touch := false
var main: Node = null
var base_time_scale := 1.0     # dev / test only: speeds the whole simulation up

# match configuration
var mode := "solo"           # solo | coop | versus
var p1_char := "m"
var p2_char := "bear"
var partner_char := ""                # the CPU partner you play with ("" = a random one every match)
var team_a: Array = ["m", "bear"]      # near team (x: camera side) ids
var team_b: Array = ["snow", "wang"]
var last_result: Dictionary = {}
var player_stats := {"played": 0, "won": 0}
var profile: Profile = null          # XP / unlocks / achievements / missions (user://profile.json)
var profile_enabled := true          # off for dev autoplay so test runs never touch the save


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	Loc.apply(String(settings["language"]))
	var ppath := Profile.PATH
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			ppath = a.substr(10)                          # dev: keep test runs on their own save file
	profile = Profile.new(ppath)
	if not profile.load_from_disk() and (int(player_stats["played"]) > 0 or int(player_stats["won"]) > 0):
		var played := int(player_stats["played"])
		var won := mini(int(player_stats["won"]), played)
		profile.stats["matches"] = played                         # carry over the old win / loss record
		profile.stats["wins"] = won
		profile.counters["wins"] = won
		profile.counters["matches"] = played
	profile.recheck_all()
	profile.ensure_daily()
	_setup_inputs()
	var f: Font = _make_font()
	var th := Theme.new()
	th.default_font = f
	th.default_font_size = 28
	get_tree().root.theme = th
	_detect_touch()
	if OS.has_feature("mobile"):
		Engine.max_fps = 60          # battery / thermals; physics interpolation keeps motion smooth
	apply_settings()


## Fonts: assets/fonts/ui_font.ttf is the Chinese UI font (trial version, see docs section 22 for licensed alternatives).
## Optional: drop a Latin font at assets/fonts/ui_font_en.ttf (e.g. Fredoka, OFL) and it takes over every Latin glyph, with the
## Chinese font behind it as a fallback - no code change needed.
func _make_font() -> Font:
	var path := "res://assets/fonts/ui_font.ttf"
	var en_path := "res://assets/fonts/ui_font_en.ttf"
	if ResourceLoader.exists(path):
		var ff: FontFile = load(path)
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "Droid Sans Fallback", "sans-serif"])
		ff.fallbacks = [sf]
		if ResourceLoader.exists(en_path):
			var en: FontFile = load(en_path)
			en.fallbacks = [ff]
			return en
		return ff
	var s := SystemFont.new()
	s.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "Droid Sans Fallback", "sans-serif"])
	s.font_weight = 700
	return s


func _detect_touch() -> void:
	var want := false
	match settings["touch"]:
		"on": want = true
		"off": want = false
		_: want = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	set_touch(want)


func set_touch(v: bool) -> void:
	if is_touch != v:
		is_touch = v
		touch_mode_changed.emit(v)


## Every second: if the average frame took longer than ~21 ms lower the 3D resolution a notch, if it was comfortably
## fast for 3 seconds in a row raise it again (never above the quality tier, never below 0.5).
func _dynamic_resolution(dt: float) -> void:
	if not _dr_enabled:
		return
	_dr_acc += dt
	_dr_n += 1
	if _dr_acc < 1.0:
		return
	var avg := _dr_acc / float(_dr_n)
	_dr_acc = 0.0
	_dr_n = 0
	var vp := get_viewport()
	if avg > 1.0 / 48.0:
		_dr_good = 0
		_dr_scale = maxf(_dr_scale - 0.05, 0.5)
	elif avg < 1.0 / 57.0:
		_dr_good += 1
		if _dr_good >= 3 and _dr_scale < _dr_cap:
			_dr_good = 0
			_dr_scale = minf(_dr_scale + 0.03, _dr_cap)
	else:
		_dr_good = 0
	if not is_equal_approx(vp.scaling_3d_scale, _dr_scale):
		vp.scaling_3d_scale = _dr_scale


var _perf_t := 0.0
var _perf_on
var _perf_frames := 0

# dynamic resolution (phones, automatic render scale only): keep ~60 fps by trading 3D resolution
var _dr_cap := 1.0                  # the quality tier's own scale: never go above it
var _dr_scale := 1.0
var _dr_acc := 0.0
var _dr_n := 0
var _dr_good := 0
var _dr_enabled := false


## phone debug builds: one line every 5 s in logcat (adb logcat -s godot) with fps / frame times / memory
func _process(dt: float) -> void:
	_dynamic_resolution(dt)
	if not (OS.has_feature("mobile") and OS.is_debug_build()):
		return
	if not _perf_on:
		_perf_on = true
		Prof.on = true
		RenderingServer.viewport_set_measure_render_time(get_tree().root.get_viewport_rid(), true)
	_perf_t += dt
	_perf_frames += 1
	if _perf_t >= 5.0:
		_perf_t = 0.0
		var rid := get_tree().root.get_viewport_rid()
		print("[perf] fps=%d  scale=%.2f  script=%.1fms physics=%.1fms  render_cpu=%.1fms render_gpu=%.1fms  mem=%.0fMB nodes=%d draws=%d prims=%dk" % [
				Engine.get_frames_per_second(), get_viewport().scaling_3d_scale, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				RenderingServer.viewport_get_measured_render_time_cpu(rid), RenderingServer.viewport_get_measured_render_time_gpu(rid),
				OS.get_static_memory_usage() / 1048576.0, get_tree().get_node_count(),
				int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
				int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)) / 1000])
		print("[prof] ms/frame: ", Prof.report(_perf_frames))
		_perf_frames = 0


func _input(event: InputEvent) -> void:
	if settings["touch"] == "auto" and event is InputEventScreenTouch and not is_touch:
		set_touch(true)
	if settings["touch"] == "auto" and is_touch and (event is InputEventKey or event is InputEventJoypadButton) and not OS.has_feature("mobile"):
		# a real keyboard / gamepad press on a desktop with a touch screen: go back to normal UI
		set_touch(false)
	if event.is_action_pressed("toggle_fullscreen"):
		settings["fullscreen"] = not settings["fullscreen"]
		apply_settings()


# ---------------------------------------------------------------- settings
## P1 keyboard actions the player can remap (settings -> key bindings)
const REBINDABLE := [["left", "左移"], ["right", "右移"], ["up", "上移"], ["down", "下移"], ["hit", "击球"], ["jump", "跳跃 / 拦网"], ["dive", "扑救"]]
const DEFAULT_KEYS := {"p1_left": KEY_A, "p1_right": KEY_D, "p1_up": KEY_W, "p1_down": KEY_S, "p1_hit": KEY_J, "p1_jump": KEY_K, "p1_dive": KEY_L}
var key_overrides := {}                  # action -> physical keycode (only what differs from the default)


func key_of(act: String) -> int:
	for e in InputMap.action_get_events(act):
		if e is InputEventKey:
			return int((e as InputEventKey).physical_keycode)
	return 0


func key_name(act: String) -> String:
	var k := key_of(act)
	return OS.get_keycode_string(k as Key) if k != 0 else "-"


func _apply_key(act: String, code: int) -> void:
	for e in InputMap.action_get_events(act):
		if e is InputEventKey:
			InputMap.action_erase_event(act, e)
	_key(act, code as Key)


## bind a key to an action; if another action already uses it the two swap keys. Returns the swapped action ("" = none)
func set_key(act: String, code: int) -> String:
	var swapped := ""
	for other in DEFAULT_KEYS.keys():
		if other != act and key_of(other) == code:
			var mine := key_of(act)
			_apply_key(other, mine)
			key_overrides[other] = mine
			swapped = other
	_apply_key(act, code)
	key_overrides[act] = code
	save_settings()
	return swapped


func reset_keys() -> void:
	key_overrides.clear()
	for act in DEFAULT_KEYS.keys():
		_apply_key(act, int(DEFAULT_KEYS[act]))
	# the defaults of jump / dive also had a second key
	_key("p1_jump", KEY_SPACE)
	_key("p1_dive", KEY_SHIFT)
	save_settings()


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		# first run: phones start on medium quality (no MSAA 4x / fewer spectators)
		if OS.has_feature("mobile"):
			settings["quality"] = 1
		return
	for k in settings.keys():
		if cf.has_section_key("settings", k):
			settings[k] = cf.get_value("settings", k)
	if not [7, 11, 15].has(int(settings["points"])):
		settings["points"] = 11                 # old dev runs could leave odd values behind
	settings["difficulty"] = clampi(int(settings["difficulty"]), 0, 3)
	p1_char = cf.get_value("profile", "p1_char", p1_char)
	p2_char = cf.get_value("profile", "p2_char", p2_char)
	partner_char = cf.get_value("profile", "partner_char", partner_char)
	if (partner_char != "" and String(Roster.by_id(partner_char)["id"]) != partner_char) or partner_char == p1_char or partner_char == p2_char:
		partner_char = ""
	player_stats["played"] = cf.get_value("profile", "played", 0)
	player_stats["won"] = cf.get_value("profile", "won", 0)
	if cf.has_section("keys"):
		for act in cf.get_section_keys("keys"):
			if DEFAULT_KEYS.has(act):
				key_overrides[act] = int(cf.get_value("keys", act))


func save_settings() -> void:
	if main != null and main.dev.has("nosave"):          # dev runs never touch the saved settings
		return
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("settings", k, settings[k])
	cf.set_value("profile", "p1_char", p1_char)
	cf.set_value("profile", "p2_char", p2_char)
	cf.set_value("profile", "partner_char", partner_char)
	cf.set_value("profile", "played", player_stats["played"])
	cf.set_value("profile", "won", player_stats["won"])
	for act in key_overrides.keys():
		cf.set_value("keys", act, key_overrides[act])
	cf.save(SAVE_PATH)


func apply_settings() -> void:
	if DisplayServer.get_name() != "headless":
		var want_full: bool = settings["fullscreen"]
		var is_full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if want_full != is_full and not OS.has_feature("mobile"):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_full else DisplayServer.WINDOW_MODE_WINDOWED)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx:
		sfx.apply_volumes()
	if is_inside_tree():
		var q: int = settings["quality"]
		var vp := get_viewport()
		# no MSAA on phones: it leaks driver memory / drops frames on several mobile GPUs
		vp.msaa_3d = Viewport.MSAA_DISABLED if OS.has_feature("mobile") else [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(q, 0, 2)]
		# phones: the 3D view is rendered below native resolution (the UI stays sharp) and with a smaller shadow map
		var mobile := OS.has_feature("mobile")
		var scale: float = float(settings["render_scale"])
		if scale <= 0.0:
			scale = [0.62, 0.74, 0.9][clampi(q, 0, 2)] if mobile else 1.0
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if (mobile or dbg("fsr")) else Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = clampf(scale, 0.4, 1.0)
		_dr_cap = clampf(scale, 0.4, 1.0)
		_dr_scale = _dr_cap
		_dr_enabled = mobile and float(settings["render_scale"]) <= 0.0 and not dbg("nodynres")
		var shadow: int = int(settings["shadow_size"])
		if shadow <= 0 and mobile:
			shadow = 1024 if q < 2 else 2048
		if shadow > 0 and DisplayServer.get_name() != "headless":
			RenderingServer.directional_shadow_atlas_set_size(shadow, true)
	settings_changed.emit()


## dev render kill switches, e.g. settings.cfg "dbg=nosky,noferns": ambient (flat ambient + no reflections), nosky, nofog,
## noadjust, notonemap, noshadow, noferns, nostands, nobackdrop, nocrowd, nohud, nocourt, fsr
func dbg(flag: String) -> bool:
	return String(settings.get("dbg", "")).split(",").has(flag)


## short vibration on a phone / gamepad (strength 0..1). Silent on desktop without a pad.
func haptic(ms: int, strength := 0.6) -> void:
	if not settings.get("haptics", true):
		return
	var s := clampf(strength, 0.05, 1.0)
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, s)
	for d in Input.get_connected_joypads():
		Input.start_joy_vibration(d, s * 0.5, s, float(ms) / 1000.0)


## a live gameplay event (power spike, fever, knock-down ...): counts for achievements and today's missions
func live(key: String, n := 1) -> void:
	if profile == null or not profile_enabled:
		return
	profile.bump(key, n)
	profile.mission_progress(key, n)


## Notch / cut-out safe area in canvas pixels: {"l","t","r","b"} insets (all 0 on desktop).
func safe_insets() -> Dictionary:
	var zero := {"l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0}
	if not OS.has_feature("mobile") or DisplayServer.get_name() == "headless":
		return zero
	var win := Vector2(DisplayServer.window_get_size())
	if win.x < 1.0 or win.y < 1.0:
		return zero
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var vp := get_viewport().get_visible_rect().size
	var sx := vp.x / win.x
	var sy := vp.y / win.y
	return {
		"l": maxf(safe.position.x, 0.0) * sx, "t": maxf(safe.position.y, 0.0) * sy,
		"r": maxf(win.x - safe.end.x, 0.0) * sx, "b": maxf(win.y - safe.end.y, 0.0) * sy,
	}


# ---------------------------------------------------------------- scene flow
func goto(scene: String, data := {}) -> void:
	if main:
		main.goto(scene, data)


## tournament: three rounds against tougher and tougher pairs (short 7-point matches)
const TOURNAMENT_ROUNDS := [
	{"name": "小组赛", "opponents": ["tabby", "shiba"], "diff": 1},
	{"name": "半决赛", "opponents": ["rhino", "moose"], "diff": 2},
	{"name": "决赛", "opponents": ["ninja_red", "ninja_black"], "diff": 3},
]
var tournament := {"active": false, "round": 0}
var launched_via_start := false      # false when a dev flag opened the match scene directly
var match_difficulty := 1            # the difficulty / target of the match about to start (tournament overrides the settings)
var match_points := 11


func tournament_ids() -> Array:
	var out := []
	for r in TOURNAMENT_ROUNDS:
		out.append_array(r["opponents"])
	return out


## the round's fixed opponents, swapping out anyone the player picked for their own team
func tournament_opponents(round_idx: int) -> Array:
	var out: Array = (TOURNAMENT_ROUNDS[round_idx]["opponents"] as Array).duplicate()
	var all_opp := tournament_ids()
	for i in out.size():
		if team_a.has(out[i]):
			for e in Roster.all():
				var id: String = e["id"]
				if not team_a.has(id) and not out.has(id) and not all_opp.has(id):
					out[i] = id
					break
	return out


func tournament_start() -> void:
	mode = "tournament"
	tournament = {"active": true, "round": 0}
	start_match()


func tournament_next() -> void:
	tournament["round"] = mini(int(tournament["round"]) + 1, TOURNAMENT_ROUNDS.size() - 1)
	start_match()


func is_practice() -> bool:
	return mode == "rally" or mode == "training"


func start_match() -> void:
	launched_via_start = true
	player_stats["played"] += 1
	match_difficulty = int(settings["difficulty"])
	match_points = int(settings["points"])
	if mode == "tournament":
		var r: Dictionary = TOURNAMENT_ROUNDS[int(tournament["round"])]
		team_b = tournament_opponents(int(tournament["round"]))
		match_difficulty = int(r["diff"])
		match_points = 7
	elif tournament.get("active", false):
		tournament = {"active": false, "round": 0}
	if main != null and main.dev.has("log"):
		print("[match] mode=%s round=%d A=%s B=%s diff=%d points=%d" % [mode, int(tournament["round"]), team_a, team_b, match_difficulty, match_points])
	rebind_aim_keys()
	goto("match")


## arrow keys aim for P1 only when nobody else needs them for movement
func rebind_aim_keys() -> void:
	for d in ["left", "right", "up", "down"]:
		var act: String = "p1_aim_" + d
		for e in InputMap.action_get_events(act):
			if e is InputEventKey:
				InputMap.action_erase_event(act, e)
	if mode == "solo":
		_key("p1_aim_left", KEY_LEFT); _key("p1_aim_right", KEY_RIGHT); _key("p1_aim_up", KEY_UP); _key("p1_aim_down", KEY_DOWN)


# ---------------------------------------------------------------- input map
func _add_action(name: String, deadzone := 0.2) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, deadzone)
	else:
		InputMap.action_erase_events(name)


func _key(a: String, code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	InputMap.action_add_event(a, e)


func _mouse(a: String, btn: MouseButton) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	InputMap.action_add_event(a, e)


func _pad_btn(a: String, btn: JoyButton, device: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	e.device = device
	InputMap.action_add_event(a, e)


func _pad_axis(a: String, axis: JoyAxis, value: float, device: int) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = device
	InputMap.action_add_event(a, e)


func _setup_inputs() -> void:
	for p in [1, 2]:
		for d in ["left", "right", "up", "down", "hit", "jump", "dive", "aim_left", "aim_right", "aim_up", "aim_down"]:
			_add_action("p%d_%s" % [p, d])
	# aim keys: P1 arrow keys (added in rebind_aim_keys() for solo play), P2 numpad
	_key("p2_aim_left", KEY_KP_4); _key("p2_aim_right", KEY_KP_6); _key("p2_aim_up", KEY_KP_8); _key("p2_aim_down", KEY_KP_5)
	# --- P1: WASD + J/K/L, mouse, space, shift ; gamepad device 0
	_key("p1_left", KEY_A); _key("p1_right", KEY_D); _key("p1_up", KEY_W); _key("p1_down", KEY_S)
	_key("p1_hit", KEY_J); _mouse("p1_hit", MOUSE_BUTTON_LEFT)
	_key("p1_jump", KEY_K); _key("p1_jump", KEY_SPACE); _mouse("p1_jump", MOUSE_BUTTON_RIGHT)
	_key("p1_dive", KEY_L); _key("p1_dive", KEY_SHIFT)
	# --- P2: arrows + numpad / ,./
	_key("p2_left", KEY_LEFT); _key("p2_right", KEY_RIGHT); _key("p2_up", KEY_UP); _key("p2_down", KEY_DOWN)
	_key("p2_hit", KEY_KP_1); _key("p2_hit", KEY_COMMA)
	_key("p2_jump", KEY_KP_2); _key("p2_jump", KEY_PERIOD)
	_key("p2_dive", KEY_KP_3); _key("p2_dive", KEY_SLASH)
	# --- gamepads: dev 0 -> P1 (and any pad when P2 absent), dev 1 -> P2
	for p in [1, 2]:
		var dev: int = int(p) - 1
		var pre: String = "p%d_" % p
		_pad_axis(pre + "aim_left", JOY_AXIS_RIGHT_X, -1.0, dev)
		_pad_axis(pre + "aim_right", JOY_AXIS_RIGHT_X, 1.0, dev)
		_pad_axis(pre + "aim_up", JOY_AXIS_RIGHT_Y, -1.0, dev)
		_pad_axis(pre + "aim_down", JOY_AXIS_RIGHT_Y, 1.0, dev)
		_pad_axis(pre + "left", JOY_AXIS_LEFT_X, -1.0, dev)
		_pad_axis(pre + "right", JOY_AXIS_LEFT_X, 1.0, dev)
		_pad_axis(pre + "up", JOY_AXIS_LEFT_Y, -1.0, dev)
		_pad_axis(pre + "down", JOY_AXIS_LEFT_Y, 1.0, dev)
		_pad_btn(pre + "left", JOY_BUTTON_DPAD_LEFT, dev)
		_pad_btn(pre + "right", JOY_BUTTON_DPAD_RIGHT, dev)
		_pad_btn(pre + "up", JOY_BUTTON_DPAD_UP, dev)
		_pad_btn(pre + "down", JOY_BUTTON_DPAD_DOWN, dev)
		_pad_btn(pre + "hit", JOY_BUTTON_A, dev)
		_pad_btn(pre + "hit", JOY_BUTTON_RIGHT_SHOULDER, dev)
		_pad_axis(pre + "hit", JOY_AXIS_TRIGGER_RIGHT, 1.0, dev)
		_pad_btn(pre + "jump", JOY_BUTTON_B, dev)
		_pad_btn(pre + "jump", JOY_BUTTON_LEFT_SHOULDER, dev)
		_pad_btn(pre + "dive", JOY_BUTTON_X, dev)
		_pad_axis(pre + "dive", JOY_AXIS_TRIGGER_LEFT, 1.0, dev)
	for act in key_overrides.keys():
		_apply_key(act, int(key_overrides[act]))
	_add_action("pause")
	_key("pause", KEY_ESCAPE); _key("pause", KEY_P)
	_pad_btn("pause", JOY_BUTTON_START, -1)
	_add_action("toggle_fullscreen")
	_key("toggle_fullscreen", KEY_F11)
	_add_action("camera_toggle")
	_key("camera_toggle", KEY_C)
	_add_action("debug_slowmo")
	_key("debug_slowmo", KEY_F9)

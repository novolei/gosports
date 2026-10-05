class_name TouchControls
extends Control
## On-screen controls for phones / tablets: a floating movement stick (left), the HIT / JUMP / DIVE buttons (right; the actions p1_hit / p1_jump /
## p1_dive) and a tap on the opponent's half of the court to place the aim marker. Writes into the InputMap actions of player 1.
## The HIT button's pictogram follows the context (bump / set / spike / serve / block, see Hud._update_timing_ring()) and pulses when the ball
## is about to be in reach.
##
## The feel - sizes in millimetres (real DPI), a radial dead zone, finger routing, a minimum press, cancel handling, haptics, Android edge-gesture
## exclusion and an on-device tuner - lives in the sport-agnostic touch kit under scripts/touch/ (TouchMetrics, TouchFeel, StickModel, TouchRouter,
## TouchHaptics, GestureExclusion, TouchTuner; ported from the basketball game, which re-implemented the Minitanks touch research). This node is the
## volleyball glue: layout, drawing, the action mapping, the aim tap. See docs/TOUCH_CONTROLS.md.

signal aim_tapped(screen_pos: Vector2)

## Geometry is physical (mm): r = radius, dx / dy = distance of the centre from the right / bottom screen edge for a right-handed player. HIT sits
## where the thumb rests, JUMP to its left, DIVE above it (the layout players already knew, now with real sizes: the old buttons were 15.6 / 10.8 /
## 9.4 mm wide and JUMP's lower edge was 4.5 mm above the bottom edge, inside the system home-gesture zone).
const BTN := {
	"hit": {"r_mm": 9.5, "dx": 27.0, "dy": 21.0, "color": Color(1.0, 0.76, 0.16), "icon": "bump"},
	"jump": {"r_mm": 8.0, "dx": 47.0, "dy": 15.0, "color": Color(0.28, 0.72, 1.0), "icon": "jump"},
	"dive": {"r_mm": 7.5, "dx": 21.0, "dy": 43.0, "color": Color(1.0, 0.42, 0.66), "icon": "dive"},
}
const KEYS := ["hit", "jump", "dive"]
const KIND_ICON := {"bump": "bump", "dig": "bump", "set": "set", "spike": "spike", "serve": "serve", "block": "block"}
const STICK_ZONE_W := 0.42                  ## the left 42 % of the screen below the top 38 % starts the stick (mirrored for left-handed play)
const STICK_ZONE_TOP := 0.38
const STICK_HOME := Vector2(32.0, 27.0)     ## mm from the left / bottom edge: where the resting stick hint is drawn (and the fixed stick sits)
const AIM_FIELD := Rect2(0.12, 0.0, 0.76, 0.72)   ## the aim-tap field (fractions of the screen): the middle of the screen above the lower quarter
const AIM_BUTTON_MARGIN := 1.4              ## a near miss of a button (up to 1.4 radii) is not an aim tap
static var _icons := {}

var player := 1
var feel: TouchFeel = TouchFeel.shared()
var router: TouchRouter = TouchRouter.new()
var tuner: TouchTuner
var hit_hint := 0.0          ## 0..1: the ball is about to be in reach -> the HIT button pulses
var hit_kind := "bump"       ## what the button will do right now (bump / set / spike / serve / block)
var _mm := 0.0644            ## millimetres per canvas pixel (TouchMetrics)
var _c := {}                 ## button -> centre (px)
var _r := {}                 ## button -> radius (px)
var _stick_r := 110.0
var _stick_home := Vector2.ZERO
var _btn_down := {}          ## button name -> bool (drawn state)
var _pop := 0.0              ## icon "pop" when the context changes
var _t := 0.0
var _log := false
var _last_stick_log := 0
var _was_paused := false
var _reserved_controls: Array[Control] = []   ## HUD buttons (pause / camera ...): their touches belong to the GUI, never to the stick or the aim tap


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS             # (the HUD above is ALWAYS anyway) the pause edge is handled by hand: see _process / _input
	_log = Game.main != null and Game.main.dev.has("touchlog")
	TouchFeel.hidden = ["auto_sprint", "sprint_on", "sprint_off", "haptic_sweet_ms", "haptic_sweet_amp", "haptic_sprint_ms", "haptic_sprint_amp"]
	TouchHaptics.allowed = func() -> bool: return bool(Game.settings.get("haptics", true))
	apply_settings()
	_compute_layout()
	router.button_down.connect(_on_button_down)
	router.button_up.connect(_on_button_up)
	router.stick_changed.connect(_on_stick_changed)
	get_viewport().size_changed.connect(_relayout)
	Game.settings_changed.connect(_relayout)
	if OS.has_feature("debug") and TouchMetrics.touch_ui() or TouchTuner.wanted() or feel.tuner_gesture:
		tuner = TouchTuner.new()
		tuner.show_chip = (OS.has_feature("debug") and TouchMetrics.touch_ui()) or TouchTuner.wanted()
		tuner.relayout = _relayout
		tuner.readout = _readout
		tuner.mm_per_px = _mm
		add_child(tuner)
		tuner.layout(get_viewport_rect().size)
	if _log or OS.has_feature("debug"):
		print("[touch] dpi=%.1f src=%s mm/px=%.4f canvas=%s window=%s stick_r=%.0fpx (%.1fmm) btn_r=%.0f/%.0f/%.0fpx centres hit=%s jump=%s dive=%s stick_home=%s model=%s exclusion=%s" % [TouchMetrics.dpi(), TouchMetrics.last_source, _mm, get_viewport_rect().size, get_window().size, _stick_r, feel.stick_radius_mm, _r["hit"], _r["jump"], _r["dive"], str(_c["hit"]), str(_c["jump"]), str(_c["dive"]), str(_stick_home), OS.get_model_name(), str(GestureExclusion.last_rects)])


## HUD buttons next to the controls (pause, camera): a touch on them is left to the GUI
func reserve(c: Control) -> void:
	_reserved_controls.append(c)


## the player's settings (Game.settings) into the shared feel; a key the tuner saved keeps its tuned value
func apply_settings() -> void:
	if not TouchFeel.is_tuned("button_scale"):
		feel.button_scale = [0.85, 1.0, 1.15][clampi(int(Game.settings.get("touch_size", 1)), 0, 2)]
	feel.stick_fixed = String(Game.settings.get("touch_stick", "float")) == "fixed"


func _relayout() -> void:
	apply_settings()
	_compute_layout()
	queue_redraw()


## millimetres -> pixels for the current screen: button positions and sizes, the stick zone / home, the router's hit areas
func _compute_layout() -> void:
	_mm = TouchMetrics.mm_per_px(get_viewport())
	var ppm := 1.0 / _mm
	var s := get_viewport_rect().size
	var left_hand: bool = bool(Game.settings.get("left_handed", false)) or (Game.main != null and Game.main.dev.has("lefty"))
	var inset: Dictionary = Game.safe_insets()
	var mx := feel.edge_margin_mm
	var mb := feel.bottom_margin_mm
	var area := Rect2(Vector2(float(inset["l"]) + mx * ppm, float(inset["t"])), Vector2(s.x - float(inset["l"]) - float(inset["r"]) - 2.0 * mx * ppm, s.y - float(inset["t"]) - float(inset["b"]) - mb * ppm))
	var k := feel.button_scale
	for key in KEYS:
		var d: Dictionary = BTN[key]
		var r: float = float(d["r_mm"]) * k * ppm
		# the fan is scaled about the margin corner, so a bigger button also moves a little outwards (no overlap)
		var dx := (float(d["dx"]) - mx) * k + mx
		var dy := (float(d["dy"]) - mb) * k + mb
		var cx := area.end.x + mx * ppm - dx * ppm if not left_hand else area.position.x - mx * ppm + dx * ppm
		var cy := area.end.y + mb * ppm - dy * ppm
		_c[key] = Vector2(clampf(cx, area.position.x + r, area.end.x - r), clampf(cy, area.position.y + r, area.end.y - r))
		_r[key] = r
	_resolve_overlaps()
	for key in KEYS:
		router.set_button(StringName(key), _c[key], _r[key], feel.hit_extra_mm * ppm)
	_stick_r = feel.stick_radius_mm * ppm
	var st := router.stick
	st.radius = _stick_r
	st.dead = feel.stick_dead_mm * ppm
	st.full_at = feel.stick_full_at
	st.response = feel.stick_response
	st.follow = feel.stick_follow
	st.fixed = feel.stick_fixed
	st.reach = feel.stick_fixed_reach
	var hx: float = float(inset["l"]) + STICK_HOME.x * ppm if not left_hand else s.x - float(inset["r"]) - STICK_HOME.x * ppm
	_stick_home = Vector2(hx, s.y - float(inset["b"]) - STICK_HOME.y * ppm)
	st.home = _stick_home
	router.min_press_msec = feel.min_press_ms
	var zw := s.x * STICK_ZONE_W
	var zt := s.y * STICK_ZONE_TOP
	router.stick_zone = Rect2(0.0, zt, zw, s.y - zt) if not left_hand else Rect2(s.x - zw, zt, zw, s.y - zt)
	if tuner != null:
		tuner.mm_per_px = _mm
		tuner.layout(s)
	_update_gesture_exclusion()


## push overlapping circles apart (a clamp at a small screen can squeeze two buttons together): the one further from the HIT button moves
func _resolve_overlaps() -> void:
	var gap := 1.0 / _mm                                                                 # 1 mm
	for pair: Array in [["jump", "hit"], ["dive", "hit"], ["jump", "dive"]]:
		var a: String = pair[0]
		var b: String = pair[1]
		var need: float = float(_r[a]) + float(_r[b]) + gap
		var away: Vector2 = (_c[a] as Vector2) - (_c[b] as Vector2)
		if away.length() < need:
			var dir := away.normalized() if away.length() > 0.001 else Vector2.UP
			_c[a] = (_c[b] as Vector2) + dir * need


## the Android back-gesture columns next to the stick and the buttons: touches there are not taken by the system
func _update_gesture_exclusion() -> void:
	if not GestureExclusion.supported():
		return
	if not feel.gesture_exclusion or (Game.main != null and Game.main.dev.has("noexclusion")):       # (--noexclusion: A/B test on a device)
		GestureExclusion.clear()
		return
	var scale := TouchMetrics.canvas_scale(get_viewport())
	var ok := GestureExclusion.apply_edges(get_window().size, _stick_home.y * scale, float((_c["hit"] as Vector2).y) * scale, feel.gesture_edge_dp)
	if _log:
		print("[touch] gesture exclusion sent=%s error='%s' rects=%s" % [str(ok), GestureExclusion.last_error, str(GestureExclusion.last_rects)])


## touches that belong to something else on top of the controls: the tuner panel / chip and the HUD buttons
func _sync_reserved() -> void:
	router.reserved.clear()
	if tuner != null:
		if tuner.is_open():
			router.reserved.append(tuner.rect())
		var chip := tuner.chip_rect()
		if chip.has_area():
			router.reserved.append(chip)
	for c in _reserved_controls:
		if is_instance_valid(c) and c.is_visible_in_tree():
			router.reserved.append(c.get_global_rect().grow(10.0))


func _readout() -> String:
	var st := router.stick
	return "stick v (%.2f, %.2f)  strength %.2f   stick r %.0f px = %.1f mm   fingers %d" % [st.value.x, st.value.y, st.strength, _stick_r, _stick_r * _mm, router._fingers.size()]


# ------------------------------------------------------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if not visible or get_tree().paused:                 # (the pause menu owns every touch while the game is paused)
		return
	var touch := event as InputEventScreenTouch
	if touch != null and touch.pressed:
		_sync_reserved()
	if _log and (touch != null or event is InputEventScreenDrag):
		_log_event(event)
	if router.handle(event):
		get_viewport().set_input_as_handled()
		return
	if touch != null and touch.pressed and _tap_ok(touch.position):
		aim_tapped.emit(touch.position)                  # a tap on the opponent's half = the aim marker


## the aim-tap field: the middle of the screen above the lower quarter, clear of the stick zone's grab and of every button (a near miss of a
## button is not an aim tap), the HUD buttons and the tuner
func _tap_ok(p: Vector2) -> bool:
	var s := get_viewport_rect().size
	if not Rect2(AIM_FIELD.position * s, AIM_FIELD.size * s).has_point(p):
		return false
	for k in KEYS:
		if p.distance_to(_c[k]) <= float(_r[k]) * AIM_BUTTON_MARGIN:
			return false
	for r in router.reserved:
		if r.has_point(p):
			return false
	return true


func _log_event(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		print("[touch] %s idx=%d pos=(%.0f,%.0f) canceled=%s t=%d" % ["down" if e.pressed else "up", e.index, e.position.x, e.position.y, str(e.canceled), Time.get_ticks_msec()])


func _on_button_down(name: StringName) -> void:
	_btn_down[String(name)] = true
	Input.action_press("p%d_%s" % [player, name])
	TouchHaptics.pulse(&"press", feel.haptic_press_ms, feel.haptic_press_amp, 60)
	if _log:
		print("[touch] button down %s t=%d" % [name, Time.get_ticks_msec()])
	queue_redraw()


func _on_button_up(name: StringName, held_msec: int, cancelled: bool) -> void:
	_btn_down[String(name)] = false
	Input.action_release("p%d_%s" % [player, name])
	if _log:
		print("[touch] button up %s held=%dms cancelled=%s t=%d" % [name, held_msec, str(cancelled), Time.get_ticks_msec()])
	queue_redraw()


func _on_stick_changed() -> void:
	var st := router.stick
	var p := "p%d_" % player
	# HumanBrain reads the stick with Input.get_vector(.., DEADZONE) which re-maps again: pre-compensate so the player gets exactly st.value
	var v := st.value
	var len := v.length()
	if len > 0.0:
		v = v / len * (HumanBrain.DEADZONE + (1.0 - HumanBrain.DEADZONE) * len)
	_axis(p + "left", p + "right", v.x)
	_axis(p + "up", p + "down", v.y)
	if _log and Time.get_ticks_msec() - _last_stick_log > 120:
		_last_stick_log = Time.get_ticks_msec()
		print("[touch] stick v=(%.2f,%.2f) strength=%.2f active=%s t=%d" % [st.value.x, st.value.y, st.strength, str(st.active), _last_stick_log])
	queue_redraw()


func _axis(neg: String, pos: String, v: float) -> void:
	if v < 0.0:
		Input.action_press(neg, minf(1.0, -v))
		Input.action_release(pos)
	elif v > 0.0:
		Input.action_press(pos, minf(1.0, v))
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


## the app lost the focus / was paused / the controls were hidden: no up event will arrive, nothing may stay pressed
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_PAUSED]:
		if (what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT) and not OS.has_feature("mobile") 				and Game.main != null and Game.main.dev.has("touchbot"):
			return                                  # dev: another window took the focus of a desktop --touchbot run (the bot checks the focus-loss path itself)
		router.release_all()
		_release_actions()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		router.release_all()
		_release_actions()


func _release_actions() -> void:
	for d in ["left", "right", "up", "down", "hit", "jump", "dive"]:
		Input.action_release("p%d_%s" % [player, d])
	for k in KEYS:
		_btn_down[k] = false
	queue_redraw()


## what the HIT button will do right now (bump / set / spike / serve / block) and how close the ball is (0..1)
func set_hit_hint(v: float, kind: String, dt: float) -> void:
	if Game.main != null and Game.main.dev.has("hithint"):
		v = 1.0                                  # dev: pin the pulse for screenshots
		kind = String(Game.main.dev["hithint"]) if Game.main.dev["hithint"] is String else "spike"
	kind = String(KIND_ICON.get(kind, "bump"))
	var nv := move_toward(hit_hint, v, dt * (10.0 if v > hit_hint else 5.0))
	if kind != hit_kind:
		hit_kind = kind
		_pop = 1.0
	if nv != hit_hint or _pop > 0.0:
		hit_hint = nv
		queue_redraw()


func _process(dt: float) -> void:
	_t += dt
	if get_tree().paused != _was_paused:                  # the pause menu opened / closed: whatever was held can never be released by an up event
		_was_paused = get_tree().paused
		if _was_paused:
			router.release_all()
			_release_actions()
	router.tick()
	if _pop > 0.0:
		_pop = maxf(_pop - dt * 4.5, 0.0)
	if hit_hint > 0.01 or _pop > 0.0:
		queue_redraw()                       # animated pulse / icon pop
	for k in KEYS:                           # a delayed release (minimum press) ends here: redraw the face
		if bool(_btn_down.get(k, false)) and not router.is_down(StringName(k)):
			_btn_down[k] = false
			queue_redraw()


func _exit_tree() -> void:
	router.release_all()
	_release_actions()
	GestureExclusion.clear()


static func _icon(n: String) -> Texture2D:
	if not _icons.has(n):
		var path := "res://assets/ui/act_%s.png" % n
		_icons[n] = load(path) if ResourceLoader.exists(path) else null
	return _icons[n]


# ------------------------------------------------------------------------------------------------------------------ drawing
func _draw() -> void:
	var st := router.stick
	var R := _stick_r
	# joystick: the base where the thumb landed (or the fixed home), the knob under the thumb; a faint resting hint otherwise
	if st.active:
		var o := st.origin
		draw_circle(o + Vector2(0, 5), R * 1.07, Color(0, 0, 0, 0.14), true, -1.0, true)
		draw_circle(o, R * 1.07, Color(1, 1, 1, 0.16), true, -1.0, true)
		draw_arc(o, R * 1.07, 0, TAU, 48, Color(1, 1, 1, 0.6), 5.0, true)
		var kp := o + st.knob_offset()
		var kr := R * 0.49
		draw_circle(kp + Vector2(0, 5), kr, Color(0, 0, 0, 0.2), true, -1.0, true)
		draw_circle(kp, kr, Color(1, 1, 1, 0.62), true, -1.0, true)
		draw_circle(kp + Vector2(-kr * 0.26, -kr * 0.3), kr * 0.48, Color(1, 1, 1, 0.35), true, -1.0, true)
	else:
		draw_arc(_stick_home, R * 0.92, 0, TAU, 48, Color(1, 1, 1, 0.3), 5.0, true)
		draw_circle(_stick_home, R * 0.36, Color(1, 1, 1, 0.2), true, -1.0, true)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var tip: Vector2 = _stick_home + d * R * 0.72
			var perp := Vector2(-d.y, d.x)
			draw_colored_polygon(PackedVector2Array([tip + d * 12.0, tip + perp * 9.0, tip - perp * 9.0]), Color(1, 1, 1, 0.3))
	for k in KEYS:
		var c: Vector2 = _c[k]
		var r: float = _r[k]
		var col: Color = BTN[k]["color"]
		var down: bool = _btn_down.get(k, false)
		var hot: float = hit_hint if k == "hit" else 0.0
		var u := r / 100.0                                              # (the old pixel offsets were designed for a 100 px radius)
		# soft ground shadow
		draw_circle(c + Vector2(0, 16) * u, r * 0.98, Color(0, 0, 0, 0.2), true, -1.0, true)
		if hot > 0.01:
			var pulse := 0.5 + 0.5 * sin(_t * (9.0 + 8.0 * hot))
			draw_circle(c, r + (10.0 + 18.0 * pulse * hot) * u, Color(1.0, 0.95, 0.5, 0.2 * hot), true, -1.0, true)
			draw_arc(c, r + (12.0 + 10.0 * pulse * hot) * u, 0, TAU, 56, Color(1.0, 0.97, 0.6, 0.9 * hot), 6.0, true)
		# a fat "arcade" button: dark base (the visible edge) + a face that sinks when pressed
		draw_circle(c + Vector2(0, 9) * u, r, Color(col.r * 0.55, col.g * 0.5, col.b * 0.6, 0.95), true, -1.0, true)
		var f := c + Vector2(0, 7 if down else 0) * u
		var fa := 0.97 if down else clampf(0.84 + 0.12 * hot, 0.0, 1.0)
		draw_circle(f, r, Color(col.r, col.g, col.b, fa), true, -1.0, true)
		draw_arc(f, r, 0, TAU, 56, Color(1, 1, 1, 0.95), 5.0, true)                                # flat face + white rim (lightly flat look)
		var tex := _icon(hit_kind if k == "hit" else String(BTN[k]["icon"]))
		if tex != null:
			var sz := r * 1.3
			if k == "hit":
				sz = r * 1.32 * (1.0 + 0.22 * _pop)
			var rect := Rect2(f - Vector2(sz, sz) * 0.5, Vector2(sz, sz))
			draw_texture_rect(tex, Rect2(rect.position + Vector2(3, 5) * u, rect.size), false, Color(0, 0, 0, 0.32))
			draw_texture_rect(tex, rect, false, Color.WHITE)

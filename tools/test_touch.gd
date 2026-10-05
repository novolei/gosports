extends SceneTree
## Offline checks of the touch kit (scripts/touch/): TouchMetrics, StickModel, TouchRouter, TouchFeel, TouchHaptics.
##   godot --headless --path . -s tools/test_touch.gd
## Pure logic only (no autoload, no scene): the full chain events -> TouchControls -> actions -> HumanBrain -> Athlete is checked by the
## in-game bot, see `--touchbot` in docs/TOUCH_CONTROLS.md.

var fails := 0
var checks := 0
var _now := 0                               ## the router's injected clock (msec)
var _log: Array = []                        ## events seen by the router signals


func _initialize() -> void:
	_test_metrics()
	_test_stick()
	_test_stick_fixed()
	_test_router()
	_test_router_min_press()
	_test_router_cancel()
	_test_feel()
	_test_haptics()
	print("RESULT: ", "OK" if fails == 0 else "%d FAILED" % fails, "  (", checks, " checks)")
	quit(1 if fails > 0 else 0)


func _check(name: String, ok: bool, info := "") -> void:
	checks += 1
	print(("   ok   " if ok else "   FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok:
		fails += 1


func _touch(idx: int, pos: Vector2, pressed: bool, canceled := false) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	e.canceled = canceled
	return e


func _drag(idx: int, pos: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	return e


# ------------------------------------------------------------------------------------------------------------------ metrics
func _test_metrics() -> void:
	TouchMetrics.forced_dpi = 0.0
	TouchMetrics.forced_mm_per_px = 0.0
	var vp: Viewport = root
	var canvas_h := float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	_check("desktop: the reference phone (%.1f mm over the canvas height)" % TouchMetrics.REFERENCE_HEIGHT_MM, absf(TouchMetrics.mm_per_px(vp) - TouchMetrics.REFERENCE_HEIGHT_MM / canvas_h) < 0.0001, "%.5f mm/px" % TouchMetrics.mm_per_px(vp))
	TouchMetrics.forced_mm_per_px = 0.05
	_check("forced mm/px wins", absf(TouchMetrics.mm_per_px(vp) - 0.05) < 1e-6 and absf(TouchMetrics.px_per_mm(vp) - 20.0) < 0.01)
	TouchMetrics.forced_mm_per_px = 0.0
	TouchMetrics.forced_dpi = 515.1
	var scale := TouchMetrics.canvas_scale(vp)
	_check("forced dpi: mm/px = window scale * 25.4 / dpi", absf(TouchMetrics.mm_per_px(vp) - scale * 25.4 / 515.1) < 1e-6, "scale %.3f -> %.5f" % [scale, TouchMetrics.mm_per_px(vp)])
	TouchMetrics.forced_dpi = 5000.0
	_check("an absurd dpi is clamped", TouchMetrics.dpi() == TouchMetrics.DPI_MAX)
	TouchMetrics.forced_dpi = 0.0
	_check("model table has the two measured phones", TouchMetrics.dpi_overrides.has("M2011K2C") and TouchMetrics.dpi_overrides.has("M2007J17C"))
	# the Mi 11 case worked out: 1440 px window height, 1080 canvas, 515.1 dpi -> a 11 mm stick radius is 167 canvas px (was 110 px = 7.2 mm)
	var mm := 1440.0 / 1080.0 * 25.4 / 515.1
	_check("Mi 11: 11 mm = %.0f canvas px (the old 110 px were %.1f mm)" % [11.0 / mm, 110.0 * mm], absf(11.0 / mm - 167.3) < 1.0 and absf(110.0 * mm - 7.23) < 0.05)


# ------------------------------------------------------------------------------------------------------------------ stick
func _stick() -> StickModel:
	var s := StickModel.new()
	s.radius = 100.0
	s.dead = 10.0
	s.full_at = 0.9
	s.home = Vector2(200, 600)
	return s


func _test_stick() -> void:
	var s := _stick()
	s.begin(3, Vector2(300, 500))
	_check("floating: a touch anywhere is the zero point (output 0)", s.value == Vector2.ZERO and s.origin == Vector2(300, 500) and s.active and s.index == 3)
	s.drag(Vector2(300 + 9, 500))
	_check("inside the dead zone: 0", s.value == Vector2.ZERO)
	s.drag(Vector2(300 + 10.5, 500))
	_check("just outside the dead zone: a tiny positive value (no jump)", s.value.x > 0.0 and s.value.x < 0.02, "%.4f" % s.value.x)
	s.drag(Vector2(300 + 50, 500))
	_check("half way: (50-10)/(90-10) = 0.5", absf(s.value.x - 0.5) < 0.001 and absf(s.value.y) < 0.001, "%.3f" % s.value.x)
	s.drag(Vector2(300 + 90, 500))
	_check("full_at * radius = length 1", absf(s.value.length() - 1.0) < 0.001)
	s.drag(Vector2(300 + 100, 500))
	_check("past full_at the output stays 1 (plateau)", absf(s.value.length() - 1.0) < 0.001 and absf(s.strength - 1.0) < 0.001)
	s.drag(Vector2(300 + 160, 500))
	_check("dragged past the radius: the base follows, the thumb is exactly one radius from it", absf(s.origin.x - 360.0) < 0.001 and absf((s.pos - s.origin).length() - 100.0) < 0.001, "origin %s" % str(s.origin))
	s.drag(Vector2(300 + 100, 500))
	_check("pulling back 60 px responds at once (the base moved with the thumb: strength 0.4, not still 1.0)", absf(s.strength - 0.4) < 0.001, "%.3f" % s.strength)
	# direction is kept
	var d := _stick()
	d.begin(0, Vector2(100, 100))
	d.drag(Vector2(100 - 30, 100 - 40))
	_check("direction preserved (3-4-5): value points up-left", absf(d.value.normalized().dot(Vector2(-0.6, -0.8)) - 1.0) < 0.0001)
	# response curve
	var r := _stick()
	r.response = 2.0
	r.begin(0, Vector2(0, 0))
	r.drag(Vector2(50, 0))
	_check("response 2.0: half push = 0.25", absf(r.value.length() - 0.25) < 0.001, "%.3f" % r.value.length())
	# sprint hysteresis
	var h := _stick()
	h.begin(0, Vector2(0, 0))
	var seq: Array = [[0.5, false], [0.92, false], [0.94, true], [0.85, true], [0.79, true], [0.77, false], [0.85, false], [0.95, true]]
	var ok := true
	for step: Array in seq:
		h.drag(Vector2(100.0 * float(step[0]), 0.0))
		if h.sprint != bool(step[1]):
			ok = false
	_check("sprint: on at 0.93, stays on down to 0.78, off below, on again at 0.93", ok)
	h.end()
	_check("end() clears everything", not h.active and h.value == Vector2.ZERO and not h.sprint and h.index == -1)


func _test_stick_fixed() -> void:
	var s := _stick()
	s.fixed = true
	_check("fixed: a touch far from home does not take the stick", not s.can_capture(Vector2(200 + 170, 600)) and s.can_capture(Vector2(200 + 150, 600)))
	s.begin(1, Vector2(230, 600))
	_check("fixed: the zero point is home, the first touch already steers", s.origin == Vector2(200, 600) and s.value.x > 0.1, "%.3f" % s.value.x)
	s.drag(Vector2(200 + 250, 600))
	_check("fixed: the base never follows", s.origin == Vector2(200, 600) and absf(s.strength - 1.0) < 0.001)


# ------------------------------------------------------------------------------------------------------------------ router
func _router() -> TouchRouter:
	var r := TouchRouter.new()
	_now = 0
	_log = []
	r.clock = func() -> int: return _now
	r.min_press_msec = 55
	r.stick.radius = 100.0
	r.stick.dead = 10.0
	r.stick_zone = Rect2(0, 200, 400, 400)
	r.set_button(&"a", Vector2(800, 500), 50.0, 12.0)
	r.set_button(&"b", Vector2(910, 500), 40.0, 12.0)
	r.button_down.connect(func(n: StringName) -> void: _log.append("down:%s@%d" % [n, _now]))
	r.button_up.connect(func(n: StringName, held: int, c: bool) -> void: _log.append("up:%s@%d held=%d c=%s" % [n, _now, held, str(c)]))
	r.stick_released.connect(func(c: bool) -> void: _log.append("stick_up:%s" % str(c)))
	return r


func _test_router() -> void:
	var r := _router()
	_check("hit test: inside the drawn circle", r.pick_button(Vector2(800, 520)) == &"a")
	_check("hit test: outside the circle but inside the physical margin still presses", r.pick_button(Vector2(800, 500 + 58)) == &"a")
	_check("hit test: far away = nothing", r.pick_button(Vector2(800, 500 + 90)) == &"")
	_check("hit test: between two buttons the nearest (relative to its hit radius) wins", r.pick_button(Vector2(856, 500)) == &"a" and r.pick_button(Vector2(866, 500)) == &"b")
	_check("the router takes a press on a button", r.handle(_touch(0, Vector2(800, 500), true)) and r.is_down(&"a"))
	_check("... and a second finger on the same button is swallowed (no double press)", r.handle(_touch(1, Vector2(805, 505), true)) and _log.size() == 1)
	r.handle(_touch(1, Vector2(805, 505), false))
	_now = 300
	r.handle(_touch(0, Vector2(800, 500), false))
	_check("a long press is released at once on lift, with its real duration", _log == ["down:a@0", "up:a@300 held=300 c=false"], str(_log))
	# stick + button at once, a stick finger that wanders keeps steering, a button finger that drifts does not press the other button
	r = _router()
	r.handle(_touch(0, Vector2(100, 400), true))
	r.handle(_touch(1, Vector2(800, 500), true))
	_check("two fingers: the stick and a button at the same time", r.stick.active and r.is_down(&"a"))
	r.handle(_drag(0, Vector2(700, 480)))
	_check("the stick finger leaves the zone and keeps steering (bound to the stick)", r.stick.active and r.stick.strength > 0.9)
	r.handle(_drag(1, Vector2(910, 500)))
	_check("a button finger that slides onto another button does not press it", not r.is_down(&"b"))
	r.handle(_touch(2, Vector2(100, 450), true))
	_check("a third finger in the stick zone while the stick is taken is ignored", r.stick.index == 0)
	# reserved rectangle: not routed, left to the GUI
	r = _router()
	r.reserved.append(Rect2(780, 480, 100, 100))
	_check("a touch in a reserved rectangle is not routed", not r.handle(_touch(0, Vector2(800, 500), true)) and not r.is_down(&"a"))
	_check("a touch outside every zone is not routed", not r.handle(_touch(0, Vector2(600, 100), true)))


func _test_router_min_press() -> void:
	var r := _router()
	r.handle(_touch(0, Vector2(800, 500), true))
	_now = 20
	r.handle(_touch(0, Vector2(800, 500), false))
	_check("a 20 ms tap: the up is not emitted yet, the button still counts as down", _log == ["down:a@0"] and r.is_down(&"a"), str(_log))
	_now = 54
	r.tick()
	_check("... not at 54 ms", _log.size() == 1)
	_now = 55
	r.tick()
	_check("... but at the 55 ms minimum press", _log == ["down:a@0", "up:a@55 held=55 c=false"] and not r.is_down(&"a"), str(_log))
	# a quick re-press before the delayed release is due
	r = _router()
	r.handle(_touch(0, Vector2(800, 500), true))
	_now = 10
	r.handle(_touch(0, Vector2(800, 500), false))
	_now = 20
	r.handle(_touch(1, Vector2(800, 500), true))
	_check("a quick re-press: the previous release goes out first, then the new press", _log.size() == 3 and _log[1].begins_with("up:a") and _log[2].begins_with("down:a"), str(_log))


func _test_router_cancel() -> void:
	var r := _router()
	r.handle(_touch(0, Vector2(800, 500), true))
	_now = 10
	r.handle(_touch(0, Vector2(800, 500), false, true))
	_check("a cancelled touch releases at once (even before the minimum press) and says so", _log == ["down:a@0", "up:a@10 held=10 c=true"], str(_log))
	r = _router()
	r.handle(_touch(0, Vector2(100, 400), true))
	r.handle(_touch(0, Vector2(100, 400), false, true))
	_check("a cancelled stick finger resets the stick and says so", not r.stick.active and _log == ["stick_up:true"], str(_log))
	r = _router()
	r.handle(_touch(0, Vector2(800, 500), true))
	_now = 100
	r.handle(_touch(0, Vector2(910, 500), true))
	_check("a press for a finger that is still bound = a lost up event: the old press is cancelled first", _log[1].begins_with("up:a") and _log[1].ends_with("c=true") and _log[2].begins_with("down:b"), str(_log))
	r = _router()
	r.handle(_touch(0, Vector2(100, 400), true))
	r.handle(_touch(1, Vector2(800, 500), true))
	r.release_all()
	_check("release_all (focus lost): nothing stays pressed, all reported cancelled", not r.stick.active and not r.is_down(&"a") and _log.has("stick_up:true") and _log.any(func(l: String) -> bool: return l.begins_with("up:a") and l.ends_with("c=true")), str(_log))


# ------------------------------------------------------------------------------------------------------------------ feel / haptics
func _test_feel() -> void:
	var f := TouchFeel.new()
	var base := f.snapshot()
	f.apply({"stick_radius_mm": 99.0, "stick_dead_mm": -3.0, "auto_sprint": 0.0, "min_press_ms": 77.4, "nope": 1.0})
	_check("apply clamps to the table range (radius 99 -> 18, dead -3 -> 0)", f.stick_radius_mm == 18.0 and f.stick_dead_mm == 0.0)
	_check("apply coerces bool / int fields", f.auto_sprint == false and f.min_press_ms == 77)
	var ch := f.changed(base)
	_check("changed() lists only what differs", ch.size() == 4 and ch.has("stick_radius_mm") and not ch.has("button_scale"), str(ch.keys()))
	f.apply(base)
	_check("apply(defaults) restores everything", f.changed(base).is_empty())
	var rows_ok := true
	for row: Array in TouchFeel.TABLE:
		if f.get(row[0]) == null or float(row[3]) >= float(row[4]) or float(row[2]) <= 0.0:
			rows_ok = false
	_check("every tuner row names a real field with min < max and a positive step", rows_ok)
	TouchFeel.hidden = ["auto_sprint", "stick_radius_mm"]
	var shown := TouchFeel.rows()
	_check("keys a game hides are left out of the tuner rows", shown.size() == TouchFeel.TABLE.size() - 2 and shown.all(func(r: Array) -> bool: return r[0] != "auto_sprint" and r[0] != "stick_radius_mm"))
	TouchFeel.hidden = []
	_check("nothing hidden: every row is shown", TouchFeel.rows().size() == TouchFeel.TABLE.size())
	_check("the defaults are inside the tuner ranges", f.snapshot().keys().all(func(k: String) -> bool:
		for row: Array in TouchFeel.TABLE:
			if row[0] == k:
				return float(f.snapshot()[k]) >= float(row[3]) and float(f.snapshot()[k]) <= float(row[4])
		return false))


func _test_haptics() -> void:
	var got: Array = []
	TouchHaptics.reset()
	TouchHaptics.allowed = Callable()
	TouchHaptics.sink = func(ms: int, amp: float) -> void: got.append([ms, amp])
	_check("a tick goes out", TouchHaptics.pulse(&"press", 10, 0.3, 60) and got.size() == 1)
	_check("a second tick within the 40 ms global gap is dropped", not TouchHaptics.pulse(&"sweet", 18, 0.6, 60) and got.size() == 1)
	OS.delay_msec(50)
	_check("a different kind after the global gap goes out", TouchHaptics.pulse(&"sweet", 18, 0.6, 150) and got.size() == 2)
	OS.delay_msec(50)
	_check("the same kind inside its own gap is dropped", not TouchHaptics.pulse(&"sweet", 18, 0.6, 150) and got.size() == 2)
	_check("ms <= 0 = the tick is switched off", not TouchHaptics.pulse(&"x", 0, 0.5))
	OS.delay_msec(50)
	TouchHaptics.allowed = func() -> bool: return false
	_check("the player's haptics switch silences everything", not TouchHaptics.pulse(&"y", 10, 0.3) and got.size() == 2)
	TouchHaptics.allowed = Callable()
	TouchHaptics.sink = Callable()
	TouchHaptics.reset()

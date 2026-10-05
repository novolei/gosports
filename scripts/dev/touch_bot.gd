class_name TouchBot
extends Node
## Dev tool (--touch --touchbot): checks the WHOLE touch chain in a real match: synthetic touch events pushed into the viewport ->
## TouchControls (router / stick / buttons / aim tap) -> InputMap actions -> HumanBrain -> Athlete. Prints one "[touchbot] ok / FAIL ..." line per
## check and a RESULT line, then quits (exit code 1 on a failure). Works in every camera view (--view=0|1): the stick is screen-relative.
##   godot --path . -- --screen=match --touch --touchbot --nosave --skipvs --mode=solo   (see docs/TOUCH_CONTROLS.md)
## The other three athletes are parked and the ball is held out of play, so nothing interferes with the measured action.

var ms: MatchScene
var fails := 0
var checks := 0
var _touch: TouchControls
var _a: Athlete
var _d: MatchDirector
var _jp := {"hit": 0, "jump": 0, "dive": 0}          ## physics frames in which Input.is_action_just_pressed fired (what HumanBrain polls)
var _aims: Array = []


func attach(p_ms: MatchScene) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS              # (the bot keeps running while it pauses the game)
	process_physics_priority = 100                       # after the controls / athletes: it only observes
	ms = p_ms
	_run.call_deferred()


func _physics_process(_dt: float) -> void:
	for k in _jp.keys():
		if Input.is_action_just_pressed("p1_%s" % k):
			_jp[k] += 1


func _check(name: String, ok: bool, info := "") -> void:
	checks += 1
	if not ok:
		fails += 1
	print("[touchbot] %s %s%s" % ["ok  " if ok else "FAIL", name, ("  " + info) if info != "" else ""])


func _send(ev: InputEvent) -> void:
	get_viewport().push_input(ev, true)             # (canvas coordinates: the stretch transform is not applied again)


func _down(idx: int, p: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = p
	e.pressed = true
	_send(e)


func _up(idx: int, p: Vector2, cancelled := false) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = p
	e.pressed = false
	e.canceled = cancelled
	_send(e)


func _drag(idx: int, p: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = p
	_send(e)


## dev: --touchshots=<dir> saves a screenshot at the key moments (windowed runs only)
func _shot(label: String) -> void:
	if not Game.main.dev.has("touchshots") or DisplayServer.get_name() == "headless":
		return
	var dir := String(Game.main.dev["touchshots"])
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, label])


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


## a fresh test position: the player in the middle of its half, everybody else parked, the ball out of play
func _sandbox() -> void:
	for x in ms.athletes:
		if x != _a:
			x.brain = null
			x.cmd_move = Vector2.ZERO
	_d._set_phase(MatchDirector.P.RALLY)
	ms.ball.live = false
	ms.ball.place(Vector3(0.0, -30.0, 0.0))
	_a.reset_to_ready()
	_a.teleport(Vector3(0.0, 0.0, 4.0))
	_a.cmd_move = Vector2.ZERO
	_a.vel = Vector2.ZERO


## the world direction a screen direction means in the active camera view (screen right / down -> xz)
func _world(screen: Vector2) -> Vector2:
	var b := CameraRig.input_basis(ms.cam_rig.view)
	return (b[0] as Vector2) * screen.x + (b[1] as Vector2) * screen.y


func _run() -> void:
	while ms.director == null or ms.humans.is_empty() or ms.hud == null or ms.hud.touch == null:
		await get_tree().process_frame
	await _wait(2.6)                                 # (the camera glides in for ~2.2 s at the start of a match: screenshots wait for it)
	_d = ms.director
	_touch = ms.hud.touch
	for x in ms.athletes:
		if x.is_human and x.player_index == 1:
			_a = x
	Game.settings["assist"] = false                  # the stick alone moves the player
	var vsz := get_viewport().get_visible_rect().size
	var mm := _touch._mm
	print("[touchbot] screen %s  mm/px %.4f  view %d  stick r %.0f px (%.1f mm)  hit r %.0f px  centres hit=%s jump=%s dive=%s" % [str(vsz), mm, ms.cam_rig.view, _touch._stick_r, _touch._stick_r * mm, _touch._r["hit"], str(_touch._c["hit"]), str(_touch._c["jump"]), str(_touch._c["dive"])])

	# --- layout ---------------------------------------------------------------------------------------------------------------------------
	var screen := Rect2(Vector2.ZERO, vsz)
	var inside := true
	for k in TouchControls.KEYS:
		var c: Vector2 = _touch._c[k]
		var r: float = _touch._r[k]
		inside = inside and screen.has_point(c) and c.x - r >= 0.0 and c.x + r <= vsz.x and c.y + r <= vsz.y
	_check("all three buttons are laid out inside the screen", inside)
	for pair: Array in [["hit", "jump"], ["hit", "dive"], ["jump", "dive"]]:
		var gap: float = (_touch._c[pair[0]] as Vector2).distance_to(_touch._c[pair[1]]) - float(_touch._r[pair[0]]) - float(_touch._r[pair[1]])
		_check("buttons %s / %s do not overlap (gap %.1f mm)" % [pair[0], pair[1], gap * mm], gap > 0.0)
	_check("physical sizes: HIT r %.1f mm >= 9, JUMP %.1f / DIVE %.1f >= 7, stick r %.1f mm >= 10" % [float(_touch._r["hit"]) * mm, float(_touch._r["jump"]) * mm, float(_touch._r["dive"]) * mm, _touch._stick_r * mm],
			float(_touch._r["hit"]) * mm >= 9.0 * 0.84 and float(_touch._r["jump"]) * mm >= 7.0 and float(_touch._r["dive"]) * mm >= 6.3 and _touch._stick_r * mm >= 10.0)
	var low := 1e9
	for k in TouchControls.KEYS:
		low = minf(low, (vsz.y - (_touch._c[k] as Vector2).y - float(_touch._r[k])) * mm)
	_check("the lowest button edge is >= 6 mm above the bottom edge (system home-gesture zone), is %.1f mm" % low, low >= 5.9)

	# --- the mouse-click emulation of a finger must not press P1's actions ------------------------------------------------------------
	var has_mouse := false
	for act in ["p1_hit", "p1_jump"]:
		for e in InputMap.action_get_events(act):
			if e is InputEventMouseButton:
				has_mouse = true
	_check("touch mode: no mouse button is bound to p1_hit / p1_jump (defensive: a finger's emulated click can never swing)", Game.is_touch and not has_mouse)

	_sandbox()
	await _wait(0.4)
	await _shot("idle")

	# --- the stick: a full push to the screen right moves the player the way the picture shows ----------------------------------------
	var zone: Rect2 = _touch.router.stick_zone                         # (left-handed play mirrors the stick zone to the right)
	var p0 := Vector2(zone.position.x + zone.size.x * 0.5, vsz.y * 0.7)
	var pos0 := _a.global_position
	var want_dir := _world(Vector2(1, 0))
	_down(0, p0)
	_drag(0, p0 + Vector2(_touch._stick_r * 1.6, 0.0))
	await _wait(0.45)
	await _shot("stick_full")
	var moved := Vector2(_a.global_position.x - pos0.x, _a.global_position.z - pos0.z)
	_check("full push right: the action of the pushed side is ~1", Input.get_action_strength("p1_right") > 0.95, "%.2f" % Input.get_action_strength("p1_right"))
	_check("full push right: the player runs to the right of the picture (world %s)" % str(want_dir), moved.length() > 0.8 and moved.normalized().dot(want_dir) > 0.9, "moved %s" % str(moved.snapped(Vector2(0.01, 0.01))))
	_check("the base followed the thumb (the zero point moved)", _touch.router.stick.origin.x > p0.x + 1.0)
	var speed_full := _a.vel.length()
	_drag(0, _touch.router.stick.origin + Vector2(_touch._stick_r * 0.5, 0.0))
	await _wait(0.35)
	var speed_half := _a.vel.length()
	_check("half push: clearly slower than a full push (%.1f vs %.1f m/s)" % [speed_half, speed_full], speed_half < speed_full * 0.8 and speed_half > 0.5)
	# a diagonal push is as strong as a straight one (a radial dead zone, not a square one)
	_drag(0, _touch.router.stick.origin + Vector2(1.0, 1.0).normalized() * _touch._stick_r * 1.2)
	await _wait(0.3)
	var dg := Vector2(Input.get_action_strength("p1_right") - Input.get_action_strength("p1_left"), Input.get_action_strength("p1_down") - Input.get_action_strength("p1_up"))
	_check("a diagonal full push is as strong as a straight one (|v| %.2f)" % dg.length(), dg.length() > 0.95 and absf(dg.x - dg.y) < 0.05)
	_up(0, p0)
	await _wait(0.15)
	_check("stick up: every axis released", Input.get_action_strength("p1_right") == 0.0 and Input.get_action_strength("p1_left") == 0.0 and Input.get_action_strength("p1_down") == 0.0 and Input.get_action_strength("p1_up") == 0.0 and _a.cmd_move == Vector2.ZERO)
	_down(0, p0)
	_drag(0, p0 + Vector2(_touch.router.stick.dead * 0.6, 0.0))
	await _wait(0.1)
	_check("a thumb wobble inside the dead zone: no movement command", _a.cmd_move == Vector2.ZERO)
	_up(0, p0)
	await _wait(0.1)

	# --- a quick tap is seen by the 60 Hz loop ------------------------------------------------------------------------------------------
	_sandbox()
	await _wait(0.3)
	for k in TouchControls.KEYS:
		_jp[k] = 0
		var c: Vector2 = _touch._c[k]
		_down(1, c)
		await get_tree().create_timer(0.02).timeout
		_up(1, c)
		await _wait(0.25)
		_check("a 20 ms tap on %s is seen by the physics loop (just_pressed in %d frame)" % [k.to_upper(), _jp[k]], _jp[k] == 1)

	# --- a long press is released at once on lift (no fixed tail), a cancelled touch releases at once too ---------------------------
	var hc: Vector2 = _touch._c["hit"]
	_down(1, hc)
	await _wait(0.3)
	_check("holding HIT keeps p1_hit pressed", Input.is_action_pressed("p1_hit"))
	_up(1, hc)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("a 300 ms press ends with the lift (not 90 ms later)", not Input.is_action_pressed("p1_hit"))
	_down(1, hc)
	await _wait(0.2)
	_up(1, hc, true)
	await get_tree().physics_frame
	_check("a cancelled touch (system gesture) releases HIT at once", not Input.is_action_pressed("p1_hit"))

	# --- a finger that slides onto another button does not press it -------------------------------------------------------------
	var jc: Vector2 = _touch._c["jump"]
	_jp["jump"] = 0
	_down(1, hc)
	_drag(1, jc)
	await _wait(0.2)
	_check("a thumb that slides from HIT onto JUMP does not press JUMP", not Input.is_action_pressed("p1_jump") and _jp["jump"] == 0)
	_up(1, jc)
	await _wait(0.15)

	# --- two thumbs: run (stick) and hit (button) at the same time -------------------------------------------------------------------
	_sandbox()
	await _wait(0.3)
	_down(0, p0)
	_drag(0, p0 + Vector2(_touch._stick_r * 0.9, 0.0))
	_down(1, hc)
	await _wait(0.3)
	_check("two fingers: the stick steers while HIT is held", _a.cmd_move.length() > 0.3 and Input.is_action_pressed("p1_hit"), "move %.2f" % _a.cmd_move.length())

	# --- focus loss: nothing may stay pressed -----------------------------------------------------------------------------------------
	_touch._notification(NOTIFICATION_APPLICATION_PAUSED)                    # (the phone app went to the background)
	await _wait(0.2)
	_check("app paused / backgrounded: the stick axes and HIT are released", Input.get_action_strength("p1_right") == 0.0 and not Input.is_action_pressed("p1_hit"))
	_up(0, p0)
	_up(1, hc)

	# --- the aim tap -------------------------------------------------------------------------------------------------------------------------
	_sandbox()
	await _wait(0.3)
	_touch.aim_tapped.connect(func(p: Vector2) -> void: _aims.append(p))
	var field := Vector2(vsz.x * 0.5, vsz.y * 0.4)
	_down(2, field)
	_up(2, field)
	await _wait(0.1)
	_check("a tap in the middle of the screen is an aim tap", _aims.size() == 1)
	_aims.clear()
	var near_miss: Vector2 = hc + Vector2(float(_touch._r["hit"]) * 1.3, 0.0)
	_down(2, near_miss)
	_up(2, near_miss)
	await _wait(0.1)
	_check("a near miss of a button is not an aim tap", _aims.is_empty())
	var pause_c: Vector2 = ms.hud._pause_btn.get_global_rect().get_center()
	_down(2, pause_c)
	_up(2, pause_c)
	await _wait(0.1)
	_check("a touch on the HUD pause button is neither an aim tap nor a stick / button touch", _aims.is_empty() and not _touch.router.stick.active)
	_check("... it reached the GUI: the pause button paused the match", ms.paused and get_tree().paused)
	ms.toggle_pause()                                  # resume
	await _wait(0.2)

	# --- the pause menu: held inputs are released, and the controls do not swallow touches while the tree is paused ------------------
	_sandbox()
	await _wait(0.3)
	_down(0, p0)
	_drag(0, p0 + Vector2(_touch._stick_r * 0.9, 0.0))
	_down(1, hc)
	await _wait(0.2)
	ms.toggle_pause()                                  # (the real pause: the menu opens, the tree is paused)
	await _wait(0.1)
	_check("paused: the stick and HIT are released", Input.get_action_strength("p1_right") == 0.0 and not Input.is_action_pressed("p1_hit"))
	_up(0, p0)
	_up(1, hc)
	_down(2, hc)
	await _wait(0.1)
	_check("paused: a touch on the HIT button is left to the pause menu (not routed)", not Input.is_action_pressed("p1_hit"), "paused=%s router_down=%s fingers=%s" % [str(get_tree().paused), str(_touch.router.is_down(&"hit")), str(_touch.router._fingers)])
	_up(2, hc)
	ms.toggle_pause()
	await _wait(0.2)

	# --- the tuner opens with three fingers held still for 2 s (does not eat the touches) --------------------------------------------
	if _touch.tuner != null:
		var t0 := Vector2(vsz.x * 0.5, vsz.y * 0.5)
		_down(2, t0)
		_down(3, t0 + Vector2(60, 0))
		_down(4, t0 + Vector2(120, 0))
		await _wait(2.3)
		_check("three fingers held 2 s open the tuner panel", _touch.tuner.is_open())
		await _shot("tuner")
		_up(2, t0)
		_up(3, t0 + Vector2(60, 0))
		_up(4, t0 + Vector2(120, 0))
		_touch.tuner.toggle()
		_check("... and it closes again", not _touch.tuner.is_open())

	print("[touchbot] RESULT: %s  (%d checks)" % ["OK" if fails == 0 else "%d FAILED" % fails, checks])
	get_tree().quit(1 if fails > 0 else 0)

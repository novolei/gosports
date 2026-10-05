class_name HumanBrain
extends RefCounted
## Translates player input (keyboard+mouse / gamepad / touch) into athlete commands.
## Aiming: mouse cursor, gamepad right stick / arrow keys, or a tapped marker on the court (touch).

var index := 1
var camera: Camera3D = null
var rig: CameraRig = null       # the match camera: the move / aim input is relative to the SCREEN (see CameraRig.input_basis)
var touch_aim = null            # Vector3 set by tapping the court on a touch screen
var _mouse_t := 99.0
var _last_mouse := Vector2(-1, -1)
var _manual_t := 0.0
var aim_marker = null           # current aim point shown to the player (Vector3 or null)
var aim_source := ""             # "key" / "mouse" / "touch" / "move" (where the current aim point comes from)
var _move_v := Vector2.ZERO     # the movement input of this frame (steers the ball when no other aim is active)


## a stick / key vector in SCREEN terms (x = right, y = down) -> the world xz plane, whichever camera view is active
func _to_world(v: Vector2) -> Vector2:
	if rig == null or rig.view == 0:
		return v
	var b := CameraRig.input_basis(rig.view)
	return (b[0] as Vector2) * v.x + (b[1] as Vector2) * v.y


func think(a: Athlete, dt: float) -> void:
	var p := "p%d_" % index
	var v := _to_world(Input.get_vector(p + "left", p + "right", p + "up", p + "down", 0.18))
	_move_v = v
	var d: Node = a.director
	if Game.main != null and Game.main.dev.has("dbghuman") and d.phase == MatchDirector.P.RALLY:
		var pl: Dictionary = d.plans[a.team]
		print("[human] who=%s mode=%s pos=%s me=%s state=%d manual=%.2f v=%s" % [pl.get("who") == a, pl.get("mode"), str(pl.get("pos")), str(a.global_position), a.state, _manual_t, str(v)])
	if v.length() > 0.12:
		_manual_t = 0.45
		a.cmd_move = v
	else:
		_manual_t = maxf(_manual_t - dt, 0.0)
		a.cmd_move = Vector2.ZERO
		# assist: run to where the team plan wants us, until the player takes over
		if Game.settings["assist"] and _manual_t <= 0.0 and d.phase == MatchDirector.P.RALLY:
			var plan: Dictionary = d.plans[a.team]
			if plan.get("who") == a and plan.get("mode") == "play":
				var spot: Vector3 = plan["pos"]
				var to := Vector2(spot.x - a.global_position.x, spot.z - a.global_position.z)
				if to.length() > 0.2 and a.state in [Athlete.S.READY, Athlete.S.AIR]:
					a.cmd_move = to.normalized() * clampf(to.length() * 1.6, 0.0, 1.0)
	if Input.is_action_just_pressed(p + "hit"):
		a.press_hit()
	if Input.is_action_just_pressed(p + "jump"):
		a.press_jump()
	if Input.is_action_just_pressed(p + "dive"):
		a.press_dive()
	_update_aim(a, dt)


func _update_aim(a: Athlete, dt: float) -> void:
	var S := Court.team_sign(a.team)
	a.aim_explicit = false
	aim_marker = null
	aim_source = ""
	var ap = null
	if Game.main != null and Game.main.dev.has("aimdemo"):                 # dev: --aimdemo=x,y holds that direction (e.g. 0.7,-0.7)
		var pr := String(Game.main.dev["aimdemo"]).split(",")
		_move_v = _to_world(Vector2(float(pr[0]), float(pr[1])))
	# 1) explicit aim stick / keys (absolute lane + depth)
	var p := "p%d_" % index
	var st := _to_world(Vector2(Input.get_axis(p + "aim_left", p + "aim_right"), Input.get_axis(p + "aim_up", p + "aim_down")))
	if st.length() > 0.35:
		var deep := -st.y * S                     # +1 = towards the far end line
		ap = Vector3(clampf(st.x * 4.2, -4.2, 4.2), 0.0, -S * lerpf(1.8, 6.4, (deep + 1.0) * 0.5))
		a.aim_explicit = true
		aim_source = "key"
	# 2) mouse
	elif camera != null and index == 1 and not Game.is_touch:
		var mp := a.get_viewport().get_mouse_position()
		if mp.distance_to(_last_mouse) > 2.0:
			_mouse_t = 0.0
			_last_mouse = mp
		else:
			_mouse_t += dt
		if _mouse_t < 3.0:
			var pt = _ray_to_floor(mp)
			if pt != null and (pt as Vector3).z * S < 0.0:
				ap = pt
				aim_source = "mouse"
	# 3) touch marker
	if ap == null and touch_aim != null:
		ap = touch_aim
		aim_source = "touch"
	# 4) the direction held while hitting (WASD / left stick / touch stick): left-right = which side, forward = deep, back = short.
	#    Never turns a bump / set into a dump over the net (that needs an explicit aim: aim_explicit stays false).
	if ap == null and Game.settings.get("aim_by_move", true) and _move_v.length() > 0.5:
		var dir := _move_v.normalized()
		var deep2 := -dir.y * S
		ap = Vector3(clampf(dir.x * 3.5, -3.5, 3.5), 0.0, -S * lerpf(2.4, 5.7, (deep2 + 1.0) * 0.5))
		aim_source = "move"
	a.aim_from_move = aim_source == "move"
	if ap != null:
		a.aim_point = ap
		aim_marker = ap
	else:
		a.aim_point = null


## is this athlete about to hit (holding the ball for the serve, or the ball is closing in on the contact point)? The aim zone
## is only shown then: no floating target while the player is just running around.
func hit_imminent(a: Athlete) -> bool:
	if a.state == Athlete.S.SERVE_HOLD or a.state == Athlete.S.SERVE_TOSS:
		return true
	var d: MatchDirector = a.director
	if a.ball == null or not a.ball.live or not d.can_hit(a):
		return false
	var kind := a._choose_kind()
	var dist := a.hit_distance(kind)
	var to := a.ideal_point(kind) - a.ball.global_position
	var closing := a.ball.vel.dot(to.normalized()) if to.length() > 0.001 else 0.0
	return dist < 3.2 and closing > 1.0 and dist / maxf(closing, 0.1) < 1.4


func clear_touch_aim() -> void:
	touch_aim = null


func _ray_to_floor(sp: Vector2):
	if camera == null or not camera.is_inside_tree():
		return null
	var o := camera.project_ray_origin(sp)
	var n := camera.project_ray_normal(sp)
	if absf(n.y) < 0.001:
		return null
	var t := -o.y / n.y
	if t < 0.0:
		return null
	var pt := o + n * t
	pt.x = clampf(pt.x, -Court.HALF_W, Court.HALF_W)
	pt.z = clampf(pt.z, -Court.HALF_D, Court.HALF_D)
	pt.y = 0.0
	return pt

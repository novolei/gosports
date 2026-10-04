class_name Athlete
extends Node3D
## One player on court: movement, jumping, diving, the contextual hit (bump / set / spike / serve / dig),
## animation selection, floor ring + name tag. Driven by a Brain (human input or AI).

enum S { READY, SERVE_HOLD, SERVE_TOSS, ACTION, AIR, DIVE, GETUP, CELEB, SAD, LOCKED, STUMBLE, KNOCKED }

signal hit_done(ath: Athlete, info: Dictionary)
signal jumped(ath: Athlete)
signal touched_down(ath: Athlete)
signal whiffed(ath: Athlete)
signal dived(ath: Athlete)
signal tossed(ath: Athlete)

const RUN_SPEED := 5.7
const ACCEL := 42.0
const AIR_ACCEL := 8.0
const JUMP_V := 7.7
const AGRAV := 24.0
const DIVE_SPEED := 8.2
const DIVE_TIME := 0.42

# hit kinds: zone = max distance for a legal hit, ideal_y = contact height above the feet,
# reach = how far in front of the chest the contact happens, clip / contact = animation + contact time
const KINDS := {
	"bump":  {"zone": 1.35, "ideal_y": 0.85, "reach": 0.45, "clip": "bump", "contact": 0.20, "lock": 0.5},
	"set":   {"zone": 1.15, "ideal_y": 1.45, "reach": 0.28, "clip": "set", "contact": 0.20, "lock": 0.45},
	"spike": {"zone": 1.45, "ideal_y": 1.5, "reach": 0.42, "clip": "spike", "contact": 0.26, "lock": 0.55},
	"dig":   {"zone": 1.8, "ideal_y": 0.45, "reach": 0.7, "clip": "dive", "contact": 0.24, "lock": 0.0},
	"serve": {"zone": 1.3, "ideal_y": 1.55, "reach": 0.35, "clip": "serve_hit", "contact": 0.30, "lock": 0.6},
}
const LEAD := 0.045                 # animation starts this long before its contact frame

# body collisions (see BodyCollisions): the jolt is the closing speed along the contact normal times the mass share
const BODY_R := 0.36
const NUDGE_JOLT := 1.6             # brushed: pushed apart only
const STUMBLE_JOLT := 4.8           # thrown off balance for a moment (two players chasing one ball)
const KNOCK_JOLT := 8.5             # knocked down: fall, dazed, get up (a real head-on sprint / a dive into someone)

var team := 0
var slot := 0
var entry: Dictionary = {}
var brain = null
var ball: Ball
var director = null
var rig: CharacterRig
var state: int = S.READY
var vel := Vector2.ZERO             # x, z velocity
var vy := 0.0
var yaw := 0.0
var is_human := false
var player_index := 0               # 1 / 2 for humans
var skill := 1.0
var friendly := false               # practice modes: returns the ball softly to the human
var perk := ""                    # character perk id (see Roster.PERKS)
var display_name := ""
var speed_mul := 1.0
var jump_mul := 1.0
var power_mul := 1.0

# commands (written by the brain every frame)
var cmd_move := Vector2.ZERO        # world x / world z, length <= 1
var aim_point = null                # Vector3 (world target on the court) or null = "smart" aim
var aim_explicit := false           # aim came from an explicit stick/key (allows dumping the ball over on touch 1/2)
var _walk_target = null
var _walk_t := 0.0

var _hit_buf := 0.0
var _jump_buf := 0.0
var _dive_buf := 0.0
var _action_t := 0.0
var _action_kind := ""
var _dive_t := 0.0
var _dive_cd := 0.0
var _jump_cd := 0.0
var _getup_t := 0.0
var _step_t := 0.0
var _land_t := 0.0
var _step_dust_t := 0.0
var _since_zone := 9.0           # seconds since the ball was last inside the hit zone (late-press forgiveness)
var _block_pose := false
var _pending_serve_jump := false
var _pending_serve_jump_t := 0.0
var in_perfect_zone := false
var last_quality := ""
var facing_override := NAN
var locked := false
var _stun_t := 0.0                  # STUMBLE: time left
var _stun_total := 0.0
var _stagger := Vector2.ZERO        # world direction we were shoved in
var _ko_phase := 0                  # KNOCKED: 0 = falling / lying, 1 = dazed
var _ko_t := 0.0
var _ko_landed := false
var _dizzy_time := 1.0
var _bump_cd := 0.0                 # reaction cooldown after a collision
var _dizzy_fx: DizzyStars = null
var _gale_t := 0.0                  # perk "gale": a short speed burst after a perfect hit
var _turn_run := false              # sprinting backwards: turn around and run instead of back-pedalling
var _vis_yaw := 0.0                 # visual-only yaw offset (decays to 0): smooths instant turns
var _prev_vel := Vector2.ZERO
var _acc_s := Vector2.ZERO          # smoothed world acceleration (x, z)

var ring: MeshInstance3D
var ring_mat: ShaderMaterial
var team_disc: MeshInstance3D
var tag: Label3D
var _bonk_t := 0.0
var arrow: MeshInstance3D
var hit_zone_radius := 1.3


func setup(p_team: int, p_slot: int, p_entry: Dictionary, p_ball: Ball, p_director) -> void:
	team = p_team
	slot = p_slot
	entry = p_entry
	ball = p_ball
	director = p_director
	display_name = entry["name"]
	var st: Dictionary = entry.get("stats", {"speed": 1.0, "jump": 1.0, "power": 1.0})
	speed_mul = st["speed"]
	jump_mul = st["jump"]
	power_mul = st["power"]
	perk = "" if (Game.main != null and Game.main.dev.has("noperks")) else String(entry.get("perk", ""))
	yaw = 0.0 if team == 0 else PI
	rotation.y = yaw
	rig = CharacterRig.new()
	rig.hero = true
	add_child(rig)
	rig.build(entry, true)
	rig.clip_finished.connect(_on_clip_finished)
	_build_markers()


func _build_markers() -> void:
	var col := Color(0.2, 0.62, 1.0) if team == 0 else Color(1.0, 0.35, 0.62)
	# team coloured disc under the feet (subtle)
	team_disc = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 1.5)
	team_disc.mesh = q
	var dm := ShaderMaterial.new()
	dm.shader = load("res://shaders/ring.gdshader")
	dm.set_shader_parameter("ring_color", Color(col.r, col.g, col.b, 0.9))
	dm.set_shader_parameter("grad", load("res://assets/env/ring_gradient.png"))
	dm.set_shader_parameter("inner", 0.0)
	dm.set_shader_parameter("width", 0.07)
	dm.set_shader_parameter("fill_alpha", 0.18)
	dm.set_shader_parameter("rainbow", 0.0)
	team_disc.material_override = dm
	team_disc.rotation_degrees.x = -90
	team_disc.position.y = 0.014
	team_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(team_disc)

	# glowing hit-range ring (only visible on human players)
	ring = MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(hit_zone_radius * 2.2, hit_zone_radius * 2.2)
	ring.mesh = rq
	ring_mat = ShaderMaterial.new()
	ring_mat.shader = load("res://shaders/ring.gdshader")
	ring_mat.set_shader_parameter("ring_color", Color(col.r, col.g, col.b, 1.0))
	ring_mat.set_shader_parameter("grad", load("res://assets/env/ring_gradient.png"))
	ring_mat.set_shader_parameter("inner", 0.5)
	ring_mat.set_shader_parameter("width", 0.15)
	ring_mat.set_shader_parameter("halo_strength", 1.0)
	ring_mat.set_shader_parameter("core_white", 0.35)
	ring.material_override = ring_mat
	ring.rotation_degrees.x = -90
	ring.position.y = 0.02
	ring.visible = false
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

	# name tag
	tag = Label3D.new()
	tag.font = Fonts.body()
	tag.text = display_name
	tag.font_size = 40
	tag.pixel_size = 0.0036
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.render_priority = 5
	tag.outline_size = 12
	tag.outline_modulate = Color(0.05, 0.1, 0.25, 0.9)
	tag.modulate = Color(1, 1, 1)
	tag.position = Vector3(0, 2.25, 0)
	tag.fixed_size = false
	tag.visible = false                 # the HUD shows a P1 / P2 marker for humans instead
	add_child(tag)


func set_human(index: int) -> void:
	is_human = true
	player_index = index
	ring.visible = true
	var mh := MoveHint.new()
	add_child(mh)
	mh.setup(self)
	tag.text = "P%d  %s" % [index, display_name]
	tag.modulate = Color(1.0, 0.95, 0.45)


# ------------------------------------------------------------------ queries
func feet_y() -> float:
	return global_position.y


func chest() -> Vector3:
	return global_position + Vector3(0, 0.95, 0)


func forward() -> Vector3:
	return -global_transform.basis.z


func is_grounded() -> bool:
	return global_position.y <= 0.001 and vy <= 0.0


func is_busy() -> bool:
	return state in [S.ACTION, S.DIVE, S.GETUP, S.CELEB, S.SAD, S.LOCKED, S.STUMBLE, S.KNOCKED]


func can_move() -> bool:
	return state in [S.READY, S.SERVE_HOLD, S.SERVE_TOSS, S.AIR, S.ACTION]


func speed_xz() -> float:
	return vel.length()


## position of the hands for a given kind if the athlete stood at p facing d (xz)
func contact_point(kind: String, face: Vector2, at_feet_y := -1.0) -> Vector3:
	var k: Dictionary = KINDS[kind]
	var fy := global_position.y if at_feet_y < 0.0 else at_feet_y
	return Vector3(global_position.x + face.x * k["reach"], fy + k["ideal_y"], global_position.z + face.y * k["reach"])


func press_hit() -> void:
	_hit_buf = 0.2


func press_jump() -> void:
	_jump_buf = 0.14


func press_dive() -> void:
	_dive_buf = 0.14


# ------------------------------------------------------------------ main loop
func auto_walk_to(p: Vector3) -> void:
	_walk_target = Vector2(p.x, p.z)
	_walk_t = 5.0


func _auto_walk_active() -> bool:
	return _walk_target != null


func blocked_visual() -> void:
	ring_mat.set_shader_parameter("pulse", 1.0)


func _physics_process(dt: float) -> void:
	var _p0 := Prof.t0()
	if _walk_target != null:
		var to: Vector2 = (_walk_target as Vector2) - Vector2(global_position.x, global_position.z)
		_walk_t -= dt
		if to.length() < 0.18 or _walk_t <= 0.0:
			_walk_target = null
			cmd_move = Vector2.ZERO
		else:
			cmd_move = to.normalized() * clampf(to.length() * 1.2, 0.35, 0.85)
	elif brain != null and not locked:
		var _pb := Prof.t0()
		brain.think(self, dt)
		Prof.add("ai.think", _pb)
	else:
		cmd_move = Vector2.ZERO
	_hit_buf = maxf(_hit_buf - dt, 0.0)
	_jump_buf = maxf(_jump_buf - dt, 0.0)
	_dive_buf = maxf(_dive_buf - dt, 0.0)
	_dive_cd = maxf(_dive_cd - dt, 0.0)
	_jump_cd = maxf(_jump_cd - dt, 0.0)
	_bump_cd = maxf(_bump_cd - dt, 0.0)
	_step_dust(dt)
	_gale_t = maxf(_gale_t - dt, 0.0)
	if state != S.KNOCKED and _dizzy_fx != null:
		_end_dizzy_fx()

	match state:
		S.READY: _tick_ready(dt)
		S.SERVE_HOLD: _tick_serve_hold(dt)
		S.SERVE_TOSS: _tick_serve_toss(dt)
		S.ACTION: _tick_action(dt)
		S.AIR: _tick_air(dt)
		S.DIVE: _tick_dive(dt)
		S.GETUP: _tick_getup(dt)
		S.CELEB, S.SAD, S.LOCKED: _tick_idle_locked(dt)
		S.STUMBLE: _tick_stumble(dt)
		S.KNOCKED: _tick_knocked(dt)

	_apply_motion(dt)
	_update_facing(dt)
	var _p1 := Prof.t0()
	_update_visual_motion(dt)
	Prof.add("ath.visual", _p1)
	_update_ring(dt)
	Prof.add("ath.physics", _p0)


func _tick_ready(dt: float) -> void:
	_steer(dt, RUN_SPEED)
	if _jump_buf > 0.0 and _jump_cd <= 0.0:
		_start_jump()
		return
	if _dive_buf > 0.0 and _dive_cd <= 0.0 and director.phase_allows_play():
		_start_dive()
		return
	if _hit_buf > 0.0:
		_try_hit()


## hit on the head by something the umpire threw: the head snaps back, the hands fly up (the serve is not lost)
func bonk() -> void:
	_bonk_t = 1.15


func _tick_serve_hold(dt: float) -> void:
	if _bonk_t > 0.0:
		_bonk_t -= dt
		_steer(dt, RUN_SPEED * 0.2)
		rig.play_if("bonk", 0.06)
		return
	# the server may slide along the base line while holding the ball
	_steer(dt, RUN_SPEED * 0.55)
	rig_play_if("serve_ready", 0.15)
	if _hit_buf > 0.0:
		_hit_buf = 0.0
		director.server_toss(self)
	if _jump_buf > 0.0:
		_jump_buf = 0.0
		_pending_serve_jump = true
		director.server_toss(self)


func begin_serve_hold() -> void:
	state = S.SERVE_HOLD
	_pending_serve_jump = false
	rig.play("serve_ready", 0.15)
	ball.hold(rig.hand_l, Vector3(0.0, 0.16, 0.0))


func do_toss() -> void:
	## called by the director: the ball leaves the hand, going straight up
	state = S.SERVE_TOSS
	ball.release()
	ball.launch(Vector3(0.0, 6.4, 0.0) + Vector3(vel.x, 0, vel.y) * 0.3, 0.05, Vector3(0, 2, 0))
	rig.play("serve_toss", 0.08)
	_pending_serve_jump_t = 0.0
	tossed.emit(self)


func _tick_serve_toss(dt: float) -> void:
	_steer(dt, RUN_SPEED * 0.3)
	if _pending_serve_jump and is_grounded():
		# jump serve: take off a moment after the toss so the apex meets the ball
		_pending_serve_jump_t += dt
		if _pending_serve_jump_t >= 0.2:
			_pending_serve_jump = false
			_pending_serve_jump_t = 0.0
			_start_jump(true)
		return
	if _jump_buf > 0.0 and _jump_cd <= 0.0 and is_grounded():
		_jump_buf = 0.0
		_start_jump(true)
		return
	if _hit_buf > 0.0:
		_try_hit()


func _tick_action(dt: float) -> void:
	_action_t -= dt
	_steer(dt, RUN_SPEED * 0.4)
	if _jump_buf > 0.0 and _jump_cd <= 0.0 and _action_kind in ["bump", "set", "whiff"] and _action_t < 0.3:
		_start_jump()
		return
	if _action_t <= 0.0:
		state = S.READY
		_action_kind = ""


func _tick_air(dt: float) -> void:
	var accel_dir := cmd_move * 3.2
	vel = vel.move_toward(accel_dir, AIR_ACCEL * dt)
	if _hit_buf > 0.0:
		_try_hit()


func _tick_dive(dt: float) -> void:
	_dive_t -= dt
	vel = vel.move_toward(Vector2.ZERO, 7.0 * dt)
	if _hit_buf > 0.0:
		_try_hit()
	if _dive_t <= 0.0 and state == S.DIVE:
		state = S.GETUP
		_getup_t = 0.4 if perk == "agile" else 0.55
		rig.play("getup", 0.05)


func _tick_getup(dt: float) -> void:
	_getup_t -= dt
	vel = vel.move_toward(Vector2.ZERO, 12.0 * dt)
	if _getup_t <= 0.0:
		state = S.READY


func _tick_idle_locked(dt: float) -> void:
	vel = vel.move_toward(Vector2.ZERO, 14.0 * dt)


func _steer(dt: float, max_speed: float) -> void:
	var target := cmd_move * max_speed * speed_mul * (1.18 if _gale_t > 0.0 else 1.0)
	vel = vel.move_toward(target, ACCEL * dt)


# ------------------------------------------------------------------ motion
func _apply_motion(dt: float) -> void:
	var p := global_position
	p.x += vel.x * dt
	p.z += vel.y * dt
	# vertical
	if p.y > 0.0 or vy > 0.0:
		vy -= AGRAV * dt
		p.y += vy * dt
		if p.y <= 0.0:
			p.y = 0.0
			var was_air := state == S.AIR
			vy = 0.0
			if was_air:
				_on_land()
	global_position = _clamp_to_court(p)


## bounds: own half only
func _clamp_to_court(p: Vector3) -> Vector3:
	var sgn := Court.team_sign(team)
	if state != S.SERVE_HOLD and state != S.SERVE_TOSS:
		p.z = clampf(p.z * sgn, 0.55, Court.PLAYER_MAX_Z) * sgn
	else:
		p.z = clampf(p.z * sgn, 0.55, Court.PLAYER_MAX_Z + 1.0) * sgn
	p.x = clampf(p.x, -Court.PLAYER_MAX_X, Court.PLAYER_MAX_X)
	if absf(p.x - Referee.SPOT.x) < 0.95 and absf(p.z) < 1.05:      # the umpire's chair is solid
		p.z = sgn * 1.05
	return p


func _on_land() -> void:
	touched_down.emit(self)
	_block_pose = false
	_land_t = 0.3
	if state == S.AIR:
		state = S.ACTION
		_action_kind = "land"
		_action_t = 0.22
		rig.play("land", 0.04)
		Sfx.play("land", -6.0, 1.0, 0.08)
		director.vfx_dust(global_position)


func _update_facing(dt: float) -> void:
	var want := 0.0 if team == 0 else PI
	if not is_nan(facing_override):
		want = facing_override
	elif state == S.DIVE or state == S.KNOCKED:
		want = yaw
	elif state == S.READY:
		want = _turn_run_facing(want)
	# shortest turn
	var d := wrapf(want - yaw, -PI, PI)
	var rate := 14.0 if state != S.DIVE and state != S.KNOCKED else 0.0
	yaw += clampf(d, -rate * dt, rate * dt)
	rotation.y = yaw


## fast retreat (the ball is behind us): turn and run like a real player; face the net again once we slow down
func _turn_run_facing(net_yaw: float) -> float:
	var spd := vel.length()
	var face_dir := Vector2(0.0, -float(Court.team_sign(team)))
	var dir := vel / maxf(spd, 0.001)
	var d := dir.dot(face_dir)
	if not _turn_run:
		if spd > 3.4 and d < -0.5:
			_turn_run = true
	elif spd < 2.2 or d > -0.05:
		_turn_run = false
	if _turn_run:
		return atan2(-dir.x, -dir.y)
	return net_yaw


func face_toward(dir_xz: Vector2, snap := true) -> void:
	if dir_xz.length() < 0.001:
		return
	# forward is -Z: yaw such that (-sin(yaw), -cos(yaw)) == dir
	var y := atan2(-dir_xz.x, -dir_xz.y)
	if snap:
		_snap_yaw(y)
	else:
		facing_override = y


## yaw changes instantly in the simulation (hit direction, dive) - the body turns over a few frames
func _snap_yaw(new_yaw: float) -> void:
	_vis_yaw = wrapf(_vis_yaw + (yaw - new_yaw), -PI, PI)
	yaw = new_yaw
	rotation.y = yaw


## Feeds the AnimationTree: local velocity -> blend position, acceleration -> body lean, smoothed yaw.
func _update_visual_motion(dt: float) -> void:
	var inv := global_transform.basis.inverse()
	var lv3 := inv * Vector3(vel.x, 0.0, vel.y)
	var lv := Vector2(lv3.x, -lv3.z)                       # x = right, y = forward (m/s)
	rig.set_locomotion(lv, dt)
	# visual yaw offset decays quickly
	_vis_yaw *= exp(-dt * 0.693 / 0.055)
	rig.rotation.y = _vis_yaw
	# lean into the movement and into acceleration (only while the body is in its run / ready pose)
	var acc := (vel - _prev_vel) / maxf(dt, 0.0005)
	_prev_vel = vel
	_acc_s = _acc_s.lerp(acc, 1.0 - exp(-dt * 0.693 / 0.05))
	var a3 := inv * Vector3(_acc_s.x, 0.0, _acc_s.y)
	var lean := Vector2.ZERO
	if state == S.READY:
		lean = lv / RUN_SPEED * 0.5 + Vector2(a3.x, -a3.z) / ACCEL * 0.9
	elif state == S.STUMBLE:
		# the upper body lags behind the shove, then catches up
		var sl := inv * Vector3(_stagger.x, 0.0, _stagger.y)
		lean = -Vector2(sl.x, -sl.z) * 2.0 * clampf(_stun_t / maxf(_stun_total, 0.01), 0.0, 1.0)
	rig.set_lean_target(lean)
	rig.update_lean(dt)
	if state != S.READY:
		return
	rig.play_loco(0.14)
	var spd := vel.length()
	if spd < 0.5:
		_step_t = 0.0
		return
	_step_t -= dt * clampf(spd / 5.0, 0.6, 1.5)
	if _step_t <= 0.0:
		_step_t = 0.27
		if is_human:
			Sfx.play_step()


func rig_play_if(clip: String, blend := 0.12) -> void:
	rig.play_if(clip, blend)


func _on_clip_finished(_clip: String) -> void:
	pass


# ------------------------------------------------------------------ jump / dive
func _start_jump(serve := false) -> void:
	_jump_buf = 0.0
	_jump_cd = 0.5
	state = S.AIR
	vy = JUMP_V * jump_mul
	var near_net := absf(global_position.z) < 2.6
	# jumping at the net while the other team has the ball = block; otherwise it is an attack jump
	_block_pose = near_net and not serve and director.last_team == 1 - team
	if _block_pose:
		rig.play("block", 0.06)
	else:
		rig.play("air", 0.06)
	Sfx.play("jump", -4.0, 1.0, 0.06)
	jumped.emit(self)


func _start_dive() -> void:
	_dive_buf = 0.0
	_dive_cd = 1.1
	state = S.DIVE
	_dive_t = DIVE_TIME
	var dir := cmd_move
	if dir.length() < 0.2:
		# dive towards the ball if nothing is pressed
		var to_ball := Vector2(ball.global_position.x - global_position.x, ball.global_position.z - global_position.z)
		dir = to_ball.normalized() if to_ball.length() > 0.01 else Vector2(0, -Court.team_sign(team))
	dir = dir.normalized()
	vel = dir * DIVE_SPEED * (1.15 if perk == "agile" else 1.0)
	_snap_yaw(atan2(-dir.x, -dir.y))
	facing_override = NAN
	rig.play("dive", 0.04)
	Sfx.play("dive", -3.0)
	director.vfx_dust(global_position)
	dived.emit(self)


# ------------------------------------------------------------------ hitting
func _choose_kind() -> String:
	if director.is_serving_athlete(self):
		return "serve"
	if state == S.DIVE:
		return "dig"
	var rel_y := ball.global_position.y - global_position.y
	if state == S.AIR or global_position.y > 0.25:
		return "spike"
	if rel_y < 1.35:
		return "bump"
	return "set"


## horizontal direction we will face when hitting: aim stick > ball-to-net default
func _hit_face_dir(kind: String) -> Vector2:
	if aim_point != null:
		var a := Vector2((aim_point as Vector3).x - global_position.x, (aim_point as Vector3).z - global_position.z)
		if a.length() > 0.5:
			return a.normalized()
	# default: face the net / the side the ball should go
	return Vector2(0, -Court.team_sign(team))


func ideal_point(kind: String) -> Vector3:
	var face := _hit_face_dir(kind)
	# the ideal contact is on the side the ball comes from (so it never has to pass through the body)
	var to_ball := Vector2(ball.global_position.x - global_position.x, ball.global_position.z - global_position.z)
	var f := face
	if to_ball.length() > 0.2 and to_ball.normalized().dot(face) < 0.2:
		f = to_ball.normalized()
	return contact_point(kind, f)


func hit_distance(kind: String) -> float:
	var ip := ideal_point(kind)
	var b := ball.global_position
	var dh := Vector2(b.x - ip.x, b.z - ip.z).length()
	var dv := (b.y - ip.y) * 0.85
	return sqrt(dh * dh + dv * dv)


func _try_hit() -> void:
	if ball == null or not director.can_hit(self):
		_hit_buf = 0.0
		return
	var kind := _choose_kind()
	var d := hit_distance(kind)
	var zone: float = KINDS[kind]["zone"]
	if state == S.SERVE_TOSS and kind == "serve":
		zone = 1.6
	if Game.main != null and Game.main.dev.has("dbghit"):
		print("[try_hit] %s state=%d kind=%s d=%.2f zone=%.2f ball=%s feet=%s vy=%.1f" % [display_name, state, kind, d, zone, str(ball.global_position), str(global_position), ball.vel.y])
	if d > zone:
		# ball far above reach and close by: jump for it (single-button friendly)
		var rel_y := ball.global_position.y - global_position.y
		var dh := Vector2(ball.global_position.x - global_position.x, ball.global_position.z - global_position.z).length()
		if state == S.READY and rel_y > 2.3 and dh < 2.2 and _jump_cd <= 0.0 and ball.live and ball.vel.y < 6.0:
			_start_jump()
			_hit_buf = 0.55
			return
		# not in range: keep the press buffered if the ball is still coming closer
		var approaching := _ball_approaching(kind)
		if not approaching and is_human and _since_zone < 0.1 and d < zone * 1.5:
			_hit_buf = 0.0                  # coyote time: the ball slipped out of reach a blink ago - still counts (as a plain "ok")
			_perform_hit(kind, "ok", zone * 0.98)
			return
		if not approaching:
			_hit_buf = 0.0
			_whiff(kind)
		return
	# in range - wait a few frames for a better moment if the ball is still closing in and quality is poor
	var q := _quality_of(d)
	if q in ["ok"] and _ball_approaching(kind) and _hit_buf > 0.07 and d > 0.5 and not (state == S.SERVE_TOSS):
		return
	_hit_buf = 0.0
	_perform_hit(kind, q, d)


func _ball_approaching(kind: String) -> bool:
	var ip := ideal_point(kind)
	var b := ball.global_position
	var now := b.distance_to(ip)
	var later := (b + ball.vel * 0.08).distance_to(ip)
	return later < now - 0.002 and ball.live


func timing_window_scale() -> float:
	var s := 1.0
	if director != null and director.is_fever(team):
		s *= 1.35                            # fever time: a roomier timing window
	if perk == "eagle":
		s *= 1.2
	return s


func _quality_of(d: float) -> String:
	var w := timing_window_scale()
	if d < 0.36 * w:
		return "perfect"
	if d < 0.66 * w:
		return "good"
	return "ok"


func _whiff(kind: String) -> void:
	if Game.main != null and Game.main.dev.has("dbghit"):
		print("[whiff] %s kind=%s" % [display_name, kind])
	if state == S.READY or state == S.SERVE_TOSS:
		state = S.ACTION
		_action_kind = "whiff"
		_action_t = 0.4
		rig.play("whiff", 0.05)
		Sfx.play("swing_miss", -5.0, 1.0, 0.08)
	whiffed.emit(self)


func _perform_hit(kind: String, quality: String, d: float) -> void:
	var face := _hit_face_dir(kind)
	var k: Dictionary = KINDS[kind]
	var ip := ideal_point(kind)
	# snap the ball towards the hands first, so the planned trajectory starts exactly where the ball is
	var snap := 0.85 if quality != "ok" else 0.7
	var contact := ball.global_position.lerp(ip, snap)
	ball.global_position = contact
	var shot: Dictionary = director.plan_shot(self, kind, quality, face)
	if shot.is_empty():
		_whiff(kind)
		return
	# turn towards where the ball is going
	var out_dir := Vector2(shot["vel"].x, shot["vel"].z)
	if out_dir.length() > 0.5:
		face_toward(out_dir.normalized())
	ball.launch(shot["vel"], shot.get("power", 0.4), shot.get("spin", Vector3.ZERO))
	var early := _ball_approaching(kind)   # still closing in on the ideal point = we swung early, else late
	var info := {"kind": kind, "quality": quality, "power": shot.get("power", 0.4), "contact": contact, "early": early,
			"label": shot.get("label", ""), "target": shot.get("target", Vector3.ZERO), "dist": d}
	last_quality = quality
	if perk == "gale" and quality == "perfect":
		_gale_t = 2.0
	# animation
	if kind == "spike" or kind == "serve":
		Sfx.play("whoosh", -9.0, 1.0, 0.1)
	if kind == "serve" and global_position.y > 0.3:
		# jump serve: use the spike swing
		rig.play("spike", 0.03, 1.0, float(KINDS["spike"]["contact"]) - LEAD)
	elif kind == "dig":
		_action_t = 0.2
	else:
		rig.play(k["clip"], 0.04, 1.0, maxf(k["contact"] - LEAD, 0.0))
	if kind != "dig":
		if state != S.AIR:
			state = S.ACTION
			_action_kind = kind
			_action_t = float(k["lock"])
	hit_done.emit(self, info)
	director.on_hit(self, info)


# ------------------------------------------------------------------ body collisions
func mass() -> float:
	return pow(power_mul, 3.0) * (1.3 if perk == "iron" else 1.0)   # the power stat (0.92 .. 1.15) -> 0.78 .. 1.5


func entry_id() -> String:
	return String(rig.entry.get("id", ""))


## small puffs under the feet while sprinting (humans only: keeps the particle count down)
func _step_dust(dt: float) -> void:
	if not is_human or state != S.READY or global_position.y > 0.05 or vel.length() < 4.0:
		_step_dust_t = 0.0
		return
	_step_dust_t += dt
	if _step_dust_t >= 0.2:
		_step_dust_t = 0.0
		director.vfx_step_dust(global_position - Vector3(vel.x, 0.0, vel.y).normalized() * 0.25)


func is_down() -> bool:
	return state == S.KNOCKED


## can take part in a collision: grounded, not holding the ball
func collidable() -> bool:
	if friendly or state in [S.SERVE_HOLD, S.SERVE_TOSS]:          # the practice ball machine never bumps into itself
		return false
	return global_position.y < 0.5


func nudge_position(d: Vector2) -> void:
	global_position = _clamp_to_court(global_position + Vector3(d.x, 0.0, d.y))


## reaction to being hit by a team mate. push = direction we are shoved in. Returns 0 none, 1 brushed, 2 stumble, 3 knocked down.
func take_collision(push: Vector2, jolt: float) -> int:
	if _bump_cd > 0.0:
		return 0
	match state:
		S.KNOCKED, S.GETUP, S.CELEB, S.SAD, S.LOCKED, S.SERVE_HOLD, S.SERVE_TOSS, S.AIR:
			return 0
		S.ACTION:
			jolt *= 0.75            # braced for the ball
		S.DIVE:
			jolt *= 0.5             # low and sliding
		S.STUMBLE:
			jolt *= 1.25            # already off balance
	if jolt >= KNOCK_JOLT:
		_begin_knock(push, jolt)
		return 3
	if jolt >= STUMBLE_JOLT:
		_begin_stumble(push, jolt)
		return 2
	if jolt >= NUDGE_JOLT:
		_bump_cd = 0.15
		return 1
	return 0


func _begin_stumble(push: Vector2, jolt: float) -> void:
	_bump_cd = 1.2
	_stun_total = clampf(0.28 + 0.06 * jolt, 0.3, 0.55)
	_stun_t = _stun_total
	_stagger = push
	_pending_serve_jump = false
	_jump_buf = 0.0
	_dive_buf = 0.0
	state = S.STUMBLE
	_action_kind = ""
	rig.play("stumble", 0.05)


func _begin_knock(push: Vector2, jolt: float) -> void:
	_bump_cd = 4.0                      # no second knock-down while lying, getting up and for a moment after
	state = S.KNOCKED
	_ko_phase = 0
	_ko_t = 0.95
	_ko_landed = false
	_dizzy_time = clampf(0.5 + 0.1 * (jolt - KNOCK_JOLT), 0.5, 1.0)
	_stagger = push
	_hit_buf = 0.0
	_jump_buf = 0.0
	_dive_buf = 0.0
	_pending_serve_jump = false
	_action_kind = ""
	facing_override = NAN
	# fall backwards: the back points where we are shoved (we face the one who hit us)
	if push.length() > 0.01:
		face_toward(-push.normalized(), true)
	rig.play("knockdown", 0.05)


func _tick_stumble(dt: float) -> void:
	_stun_t -= dt
	vel = vel.move_toward(cmd_move * RUN_SPEED * speed_mul * 0.35, 10.0 * dt)
	if _stun_t < 0.12 and _hit_buf > 0.0:
		_try_hit()
		if state != S.STUMBLE:
			return
	if _stun_t <= 0.0:
		state = S.READY


func _tick_knocked(dt: float) -> void:
	_ko_t -= dt
	vel = vel.move_toward(Vector2.ZERO, 9.0 * dt)
	if _ko_phase == 0:
		if not _ko_landed and _ko_t <= 0.95 - 0.42:
			_ko_landed = true
			Sfx.play("land", -2.0, 0.75, 0.05)
			director.vfx_dust(global_position)
		if _ko_t <= 0.0:
			_ko_phase = 1
			_ko_t = _dizzy_time
			rig.play("dizzy", 0.05)
			_start_dizzy_fx()
	elif _ko_t <= 0.0:
		_end_dizzy_fx()
		state = S.GETUP
		_getup_t = 0.65
		rig.play("getup_sit", 0.05)


func _start_dizzy_fx() -> void:
	Sfx.play("dizzy", -5.0)
	if _dizzy_fx == null:
		_dizzy_fx = DizzyStars.new()
		add_child(_dizzy_fx)
		_dizzy_fx.setup(self)


func _end_dizzy_fx() -> void:
	if _dizzy_fx != null:
		if is_instance_valid(_dizzy_fx):
			_dizzy_fx.fade_out()
		_dizzy_fx = null


# ------------------------------------------------------------------ states set by the director
func celebrate() -> void:
	state = S.CELEB
	facing_override = NAN
	rig.play("cheer", 0.15)


func sad() -> void:
	state = S.SAD
	rig.play("sad", 0.2)


func reset_to_ready() -> void:
	state = S.READY
	vy = 0.0
	vel = Vector2.ZERO
	var p := global_position
	p.y = 0.0
	global_position = p
	facing_override = NAN
	_block_pose = false
	_hit_buf = 0.0
	_jump_buf = 0.0
	_vis_yaw = 0.0
	_stun_t = 0.0
	_bump_cd = 0.0
	_turn_run = false
	_end_dizzy_fx()
	rig.play("ready", 0.15)
	reset_physics_interpolation()


func teleport(p: Vector3) -> void:
	global_position = p
	vel = Vector2.ZERO
	reset_physics_interpolation()


func is_blocking() -> bool:
	return state == S.AIR and _block_pose


# ------------------------------------------------------------------ visuals
func _update_ring(dt: float) -> void:
	if ring == null:
		return
	if is_human:
		var ok := false
		in_perfect_zone = false
		if ball != null and director != null and state != S.KNOCKED and director.can_hit(self):
			var kind := _choose_kind()
			var dd := hit_distance(kind)
			ok = dd < KINDS[kind]["zone"]
			in_perfect_zone = dd < 0.4
		_since_zone = 0.0 if ok else _since_zone + dt
		ring_mat.set_shader_parameter("pulse", 0.9 if in_perfect_zone else (0.25 if ok else 0.0))
		ring_mat.set_shader_parameter("intensity", 1.0 if ok else 0.8)
		var s := 1.0 + (0.04 * sin(Time.get_ticks_msec() * 0.008))
		ring.scale = Vector3(s, s, 1)
	# keep rings flat on the floor even while jumping
	var gy := -global_position.y
	ring.position.y = gy + 0.02
	team_disc.position.y = gy + 0.014
	team_disc.visible = true
	var sc := clampf(1.0 - global_position.y * 0.18, 0.5, 1.0)
	team_disc.scale = Vector3(sc, sc, 1)

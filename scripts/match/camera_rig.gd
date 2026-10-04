class_name CameraRig
extends Node3D
## Match camera: low, wide "behind the baseline" view like Switch Sports, with gentle ball tracking,
## punch-in zoom on spikes / blocks, shake, slow-motion and a victory orbit.

var cam: Camera3D
var ball: Ball
var director: MatchDirector
var base_fov := 58.0
var _fov := 58.0
var _shake := 0.0
var _punch := 0.0           # fov reduction (degrees)
var _punch_target := 0.0
var _focus := Vector3(0, 1.2, -1.5)
var _pos := Vector3(0, 3.7, 12.4)
var _mode := "game"          # game | point | orbit | intro
var _mode_t := 0.0
var _point_focus := Vector3.ZERO
var _slow_tween: Tween
var follow_players: Array = []              # human athletes: the camera slides sideways with them (like the broadcast view of the reference game)
var _slowmo_until := 0.0
var _stop_active := false
var style := 1              # 0 far / 1 normal / 2 close
var _replay := {}
var _roll := 0.0               # camera roll kick (radians) on big hits, decays by itself


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = base_fov
	cam.near = 0.1
	cam.far = 400.0
	add_child(cam)
	cam.current = true
	_snap()


func set_style(s: int) -> void:
	style = clampi(s, 0, 2)


func game_pose() -> Dictionary:
	var h: float = [6.0, 4.2, 3.4][style]
	var z: float = [16.5, 13.0, 11.2][style]
	var f: float = [50.0, 54.0, 56.0][style]
	if Game.main != null and Game.main.dev.has("cam"):
		var p: PackedStringArray = String(Game.main.dev["cam"]).split(",")
		h = float(p[0]); z = float(p[1]); f = float(p[2])
	return {"h": h, "z": z, "fov": f}


func _snap() -> void:
	var g := game_pose()
	_pos = Vector3(0, g["h"], g["z"])
	_focus = Vector3(0, 1.2, -1.5)
	_apply(0.0)


func intro() -> void:
	_mode = "intro"
	_mode_t = 0.0


## side-on shot of the two teams for the VS card (a slow dolly keeps it alive)
## VS shot: the WHOLE court with the net, filmed from our half at a low diagonal angle (corner of our side line), with a slow dolly
## towards the net: our pair in the foreground, the opponents across the net in the distance. `--vscam=x0,y0,z0,x1,y1,z1,fx,fy,fz,fov`.
var _vs := {"a": Vector3(-6.2, 2.7, 11.6), "b": Vector3(-4.6, 2.2, 8.0), "fa": Vector3(0.6, 1.0, -0.2), "fb": Vector3(0.2, 1.1, -1.4), "fov": 44.0, "dur": 3.4}


func _vs_pose(t: float) -> Array:
	var c: Dictionary = _vs.duplicate()
	if Game.main != null and Game.main.dev.has("vscam"):
		var p: PackedStringArray = String(Game.main.dev["vscam"]).split(",")
		c["a"] = Vector3(float(p[0]), float(p[1]), float(p[2]))
		c["b"] = Vector3(float(p[3]), float(p[4]), float(p[5]))
		c["fa"] = Vector3(float(p[6]), float(p[7]), float(p[8]))
		c["fb"] = c["fa"]
		c["fov"] = float(p[9])
	var u := clampf(t / float(c["dur"]), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	return [(c["a"] as Vector3).lerp(c["b"], u), (c["fa"] as Vector3).lerp(c["fb"], u), float(c["fov"]) - 3.0 * u]


func start_vs() -> void:
	_mode = "vs"
	_mode_t = 0.0
	var v := _vs_pose(0.0)
	_pos = v[0]
	_focus = v[1]
	_fov = v[2]
	_apply(0.0)


func start_replay() -> void:
	_mode = "replay"
	_mode_t = 0.0
	_replay = {}


func set_replay_view(pos: Vector3, focus: Vector3, fov: float) -> void:
	_replay = {"pos": pos, "focus": focus, "fov": fov}


func end_replay() -> void:
	_mode = "game"
	_mode_t = 0.0
	_replay = {}
	_snap()


func set_game() -> void:
	_mode = "game"
	_mode_t = 0.0


func punch(fov_in: float, shake: float, dur := 0.35) -> void:
	_punch_target = fov_in
	_shake = maxf(_shake, shake)
	var t := create_tween()
	t.tween_property(self, "_punch", fov_in, 0.06)
	t.tween_interval(dur)
	t.tween_property(self, "_punch", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func shake(amount: float) -> void:
	if Game.settings["shake"]:
		_shake = maxf(_shake, amount)


## quick sideways roll of the picture (spikes): sign = direction, deg = size
func roll_kick(deg: float) -> void:
	if Game.settings["shake"]:
		_roll = deg_to_rad(deg)


func slowmo(scale: float, dur: float) -> void:
	_slowmo_until = float(Time.get_ticks_msec()) / 1000.0 + dur + 0.4
	if _slow_tween:
		_slow_tween.kill()
	Engine.time_scale = scale * Game.base_time_scale
	_slow_tween = create_tween()
	_slow_tween.set_ignore_time_scale(true)
	_slow_tween.tween_interval(dur)
	_slow_tween.tween_property(Engine, "time_scale", Game.base_time_scale, 0.25)


## a few frozen frames on a big hit (real time `dur`), skipped while a slow-motion replay moment is running
func hit_stop(dur: float) -> void:
	if _stop_active or float(Time.get_ticks_msec()) / 1000.0 < _slowmo_until or dur <= 0.0:
		return
	_stop_active = true
	Engine.time_scale = 0.03
	await get_tree().create_timer(dur, true, false, true).timeout
	if float(Time.get_ticks_msec()) / 1000.0 >= _slowmo_until:
		Engine.time_scale = Game.base_time_scale
	_stop_active = false


func point_focus(pos: Vector3, winner_team: int) -> void:
	_mode = "point"
	_mode_t = 0.0
	_point_focus = pos


func _physics_process(dt: float) -> void:
	var _p := Prof.t0()
	_physics_process_impl(dt)
	Prof.add("camera", _p)


func _physics_process_impl(dt: float) -> void:
	var rt := dt / maxf(Engine.time_scale, 0.05)    # real time step for smooth camera motion
	_mode_t += rt
	var g := game_pose()
	var want_pos := Vector3(0, g["h"], g["z"])
	var want_focus := Vector3(0, 1.2, -1.6)
	var want_fov: float = g["fov"]
	if ball != null:
		var b := ball.global_position
		# follow the player (and a little of the ball): sideways, with a lead in the running direction
		var px := b.x
		var lead := 0.0
		var wp := 0.28
		var wf := 0.5
		if not follow_players.is_empty():
			px = 0.0
			for fp in follow_players:
				px += (fp as Node3D).global_position.x
				lead += float((fp as Athlete).vel.x)
			px /= float(follow_players.size())
			lead /= float(follow_players.size())
			wp = 0.5
			wf = 0.42
			px = lerpf(px, b.x, 0.22) + lead * 0.14
		want_pos.x = clampf(px * wp, -3.0, 3.0)
		want_focus.x = clampf(px * wf + b.x * 0.22, -3.2, 3.2)
		if not follow_players.is_empty():
			# keep the player's feet in frame when they are deep in their own court (serve line / baseline digs)
			var pz := 0.0
			for fp in follow_players:
				pz += (fp as Node3D).global_position.z
			pz /= float(follow_players.size())
			var deep := maxf(pz, 0.0)
			want_focus.z += clampf((deep - 3.6) * 0.8, 0.0, 4.8)
			want_pos.z += clampf((deep - 6.0) * 0.5, 0.0, 1.8)
		want_focus.y = clampf(1.0 + b.y * 0.12, 1.0, 1.9)
		want_focus.z = -1.6 + clampf(b.z * 0.18, -1.6, 1.6)
	match _mode:
		"intro":
			var u := clampf(_mode_t / 2.2, 0.0, 1.0)
			var e := u * u * (3.0 - 2.0 * u)
			want_pos = Vector3(lerpf(-9.0, 0.0, e), lerpf(5.5, g["h"], e), lerpf(15.5, g["z"], e))
			want_focus = Vector3(lerpf(2.0, 0.0, e), 1.2, -1.5)
			want_fov = lerpf(46.0, g["fov"], e)
			if u >= 1.0:
				_mode = "game"
		"point":
			# stay on the broadcast view, drift slightly towards where the ball came down and zoom in a touch
			want_pos.x = clampf(_point_focus.x * 0.25, -1.6, 1.6)
			want_focus = Vector3(clampf(_point_focus.x * 0.55, -3.0, 3.0), 0.8, _point_focus.z * 0.55)
			want_fov = float(g["fov"]) - 7.0
			if _mode_t > 2.2:
				_mode = "game"
		"vs":
			var v := _vs_pose(_mode_t)
			want_pos = v[0]
			want_focus = v[1]
			want_fov = v[2]
		"replay":
			if not _replay.is_empty():
				want_pos = _replay["pos"]
				want_focus = _replay["focus"]
				want_fov = _replay["fov"]
				if _mode_t < 0.08:
					_pos = want_pos
					_focus = want_focus
					_fov = want_fov
		"orbit":
			var a := _mode_t * 0.5
			want_pos = Vector3(sin(a) * 7.5, 2.8, cos(a) * 7.5)
			want_focus = Vector3(0, 1.1, 0)
			want_fov = 52.0
	var k := 1.0 - exp(-4.5 * rt)
	var kf := 1.0 - exp(-6.0 * rt)
	if _mode == "replay":
		k = 1.0 - exp(-10.0 * rt)
		kf = 1.0 - exp(-14.0 * rt)
	elif _mode == "vs":
		k = 1.0 - exp(-18.0 * rt)                     # the pose is already a smooth path: follow it tightly
		kf = 1.0 - exp(-18.0 * rt)
	_pos = _pos.lerp(want_pos, k)
	_focus = _focus.lerp(want_focus, kf)
	_fov = lerpf(_fov, want_fov, 1.0 - exp(-3.0 * rt))
	_apply(rt)


func _apply(rt: float) -> void:
	var off := Vector3.ZERO
	if _shake > 0.001:
		off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-0.5, 0.5)) * _shake * 0.12
		_shake = move_toward(_shake, 0.0, rt * 2.2)
	cam.global_position = _pos + off
	var up := Vector3.UP
	if absf(_roll) > 0.0005:
		up = Vector3.UP.rotated((_focus - _pos).normalized(), _roll)
		_roll = move_toward(_roll, 0.0, rt * 0.35)
		_roll *= exp(-rt * 7.0)
	cam.look_at(_focus + off * 0.4, up)
	cam.fov = _fov - _punch

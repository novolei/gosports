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
var follow_player: Node3D = null
var _slowmo_until := 0.0
var _stop_active := false
var style := 1              # 0 far / 1 normal / 2 close


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
	var h: float = [6.2, 4.5, 3.7][style]
	var z: float = [17.0, 13.8, 12.0][style]
	var f: float = [48.0, 52.0, 54.0][style]
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
		# follow the ball a little: sideways + a bit of height
		want_pos.x = clampf(b.x * 0.28, -2.0, 2.0)
		want_focus.x = clampf(b.x * 0.5, -3.0, 3.0)
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
		"orbit":
			var a := _mode_t * 0.5
			want_pos = Vector3(sin(a) * 7.5, 2.8, cos(a) * 7.5)
			want_focus = Vector3(0, 1.1, 0)
			want_fov = 52.0
	var k := 1.0 - exp(-4.5 * rt)
	_pos = _pos.lerp(want_pos, k)
	_focus = _focus.lerp(want_focus, 1.0 - exp(-6.0 * rt))
	_fov = lerpf(_fov, want_fov, 1.0 - exp(-3.0 * rt))
	_apply(rt)


func _apply(rt: float) -> void:
	var off := Vector3.ZERO
	if _shake > 0.001:
		off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-0.5, 0.5)) * _shake * 0.12
		_shake = move_toward(_shake, 0.0, rt * 2.2)
	cam.global_position = _pos + off
	cam.look_at(_focus + off * 0.4, Vector3.UP)
	cam.fov = _fov - _punch

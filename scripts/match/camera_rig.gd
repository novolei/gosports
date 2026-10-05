class_name CameraRig
extends Node3D
## Match camera: low, wide "behind the baseline" view like Switch Sports (view 0), or the broadcast "main camera" from the side line (view 1,
## the court runs left / right so a landing spot reads on both axes; C = view, V = distance), with gentle ball tracking,
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
var style := 1              # camera distance: 0 far / 1 normal / 2 close (key V, settings "cam_zoom")
var view := 0               # 0 behind the end line / 1 the broadcast main camera on the +x side line (key C, settings "cam_view")
const VIEW_NAMES := ["后方视角", "侧面视角"]
const ZOOM_NAMES := ["镜头：远景", "镜头：中景", "镜头：近景"]
const SIDE_ZOOM := [1.12, 1.0, 0.84]        # side view: distance of the camera from its focus, relative to the normal pose
const SIDE_PAN := [0.5, 0.8, 1.6]           # side view: how far (m) the camera may slide along the court to follow the play (the whole court has to stay in the picture)
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


## the resting pose of the match camera for the current view / distance: {pos, focus, fov}
func game_pose() -> Dictionary:
	# the end-line camera of a broadcast: raised a little (was 6.0 / 4.2 / 3.4 m) so the far half of the court is no longer a thin strip behind the net
	# (the floor hidden behind the net top 14 m -> 8 m, far half 13 -> 18 px/m at 1600x900) - docs/DESIGN.md 38
	var h: float = [7.8, 6.0, 4.8][style]
	var z: float = [17.5, 14.0, 12.0][style]
	var f: float = [48.0, 52.0, 54.0][style]
	if Game.main != null and Game.main.dev.has("cam"):
		var p: PackedStringArray = String(Game.main.dev["cam"]).split(",")
		h = float(p[0]); z = float(p[1]); f = float(p[2])
	var pos := Vector3(0, h, z)
	var focus := Vector3(0, 1.2, -1.5)
	if view == 1:
		var sd := Court.CAM_SIDE_DIST
		var sh := Court.CAM_SIDE_H
		var sy := 0.3
		f = Court.CAM_SIDE_FOV
		if Game.main != null and Game.main.dev.has("sidecam"):               # dev: --sidecam=dist,height,fov[,focus_y]
			var q: PackedStringArray = String(Game.main.dev["sidecam"]).split(",")
			sd = float(q[0]); sh = float(q[1]); f = float(q[2])
			if q.size() > 3:
				sy = float(q[3])
		focus = Vector3(0.0, sy, 0.0)
		pos = focus + (Vector3(sd, sh, 0.0) - focus) * float(SIDE_ZOOM[style])
	return {"pos": pos, "focus": focus, "fov": f}


## C key: behind the end line <-> the side line (the umpire chair and the benches are on the far side line, like on TV).
## Only the normal match camera is switched: a replay / point shot / VS shot keeps running and the new view is used when it ends.
func set_view(v: int) -> void:
	view = clampi(v, 0, VIEW_NAMES.size() - 1)
	Game.settings["cam_view"] = view
	Game.save_settings()
	if _mode == "game" or _mode == "point":
		_mode = "game"
		_mode_t = 0.0


func cycle_view() -> void:
	set_view((view + 1) % VIEW_NAMES.size())


## V key: far / normal / close
func set_zoom(z: int) -> void:
	style = clampi(z, 0, 2)
	Game.settings["cam_zoom"] = style
	Game.save_settings()


func cycle_zoom() -> void:
	set_zoom((style + 1) % 3)


## screen directions in world xz for the controls: [right, down]. The move stick / the aim keys are interpreted relative to the SCREEN,
## so "right" always moves to the right of the picture, whichever camera is active.
static func input_basis(v: int) -> Array:
	if v == 1:
		return [Vector2(0.0, -1.0), Vector2(1.0, 0.0)]      # camera on the +x side: screen-right = -z, screen-down (towards the camera) = +x
	return [Vector2(1.0, 0.0), Vector2(0.0, 1.0)]


## the horizontal position of a world point on the screen, in metres (behind view: x, side view: -z): left < 0 < right
func screen_x(p: Vector3) -> float:
	return -p.z if view == 1 else p.x


func _snap() -> void:
	var g := game_pose()
	_pos = g["pos"]
	_focus = g["focus"]
	_fov = g["fov"]
	_apply(0.0)


func intro() -> void:
	if _mode == "vs":
		_intro_from = [_pos, _focus, _fov]                  # glide from the end of the broadcast shot to the match camera
	else:
		_intro_from = [Vector3(-9.0, 5.5, 15.5), Vector3(2.0, 1.2, -1.5), 46.0]
	_mode = "intro"
	_mode_t = 0.0


## side-on shot of the two teams for the VS card (a slow dolly keeps it alive)
## VS shot = a live-broadcast "team photo": both pairs stand in neat rows facing the +x side line, the camera starts low in front of the
## OPPONENTS (we meet them first), arcs over the court past the net and settles in front of OUR pair; the match camera then takes over
## from exactly that pose (see intro()). `--vscam=phi0,phi1,radius,height,fov` (degrees) tunes the arc.
const VS_DUR := 4.4
var _vs_cfg := {"phi0": -48.0, "phi1": 34.0, "radius": 10.6, "h0": 1.9, "h1": 2.5, "fov0": 38.0, "fov1": 40.0}
var _intro_from := [Vector3(-9.0, 5.5, 15.5), Vector3(2.0, 1.2, -1.5), 46.0]


func _vs_pose(t: float) -> Array:
	var c: Dictionary = _vs_cfg.duplicate()
	if Game.main != null and Game.main.dev.has("vscam"):
		var p: PackedStringArray = String(Game.main.dev["vscam"]).split(",")
		c["phi0"] = float(p[0]); c["phi1"] = float(p[1]); c["radius"] = float(p[2]); c["h0"] = float(p[3]); c["h1"] = float(p[3]); c["fov0"] = float(p[4]); c["fov1"] = float(p[4])
	var x := clampf(t / VS_DUR, 0.0, 1.0)
	var u := x * x * x * (x * (x * 6.0 - 15.0) + 10.0)                       # smootherstep: lingers on both teams, sweeps in between
	var phi := deg_to_rad(lerpf(float(c["phi0"]), float(c["phi1"]), u))
	var r := float(c["radius"]) - 0.6 * sin(u * PI)                          # a little closer to the net mid-sweep
	var h := lerpf(float(c["h0"]), float(c["h1"]), u) + 0.5 * sin(u * PI)    # and a gentle crane lift
	var pos := Vector3(r * cos(phi), h, r * sin(phi))
	var focus := Vector3(0.0, 1.1, lerpf(-4.3, 4.4, u))                      # look at the row we are introducing
	return [pos, focus, lerpf(float(c["fov0"]), float(c["fov1"]), u)]


var _free: Array = [Vector3(0, 3, 8), Vector3.ZERO, 40.0]


## dev: a fixed camera (--refcam=px,py,pz,fx,fy,fz,fov)
func set_free(pos: Vector3, focus: Vector3, fov: float) -> void:
	_mode = "free"
	_mode_t = 0.0
	_free = [pos, focus, fov]
	_pos = pos
	_focus = focus
	_fov = fov


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


## the net smash's impact: a hard freeze for `freeze` real seconds (hit-stop), then a short slow motion that eases back to full speed.
## It claims the time scale first, so the generic hit_stop of the same hit is skipped and nothing cancels the freeze early.
func smash_stop(freeze: float, slow: float, slow_dur: float) -> void:
	if _stop_active:
		return
	_stop_active = true
	_slowmo_until = float(Time.get_ticks_msec()) / 1000.0 + freeze + slow_dur + 0.4
	if _slow_tween:
		_slow_tween.kill()
	Engine.time_scale = 0.02
	await get_tree().create_timer(freeze, true, false, true).timeout
	Engine.time_scale = slow * Game.base_time_scale
	_slow_tween = create_tween()
	_slow_tween.set_ignore_time_scale(true)
	_slow_tween.tween_interval(slow_dur)
	_slow_tween.tween_property(Engine, "time_scale", Game.base_time_scale, 0.25)
	_stop_active = false


func point_focus(pos: Vector3, winner_team: int) -> void:
	if _mode == "free":                  # (dev fixed camera: leave it alone)
		return
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
	var want_pos: Vector3 = g["pos"]
	var want_focus := Vector3(0, 1.2, -1.6)
	var want_fov: float = g["fov"]
	var pan: float = float(SIDE_PAN[style])
	if view == 1 and ball != null:
		# the broadcast main camera: a static shot that only breathes with the play - it slides a little along the court towards the ball /
		# the human players and tilts up for a high ball (the whole court and the servers stay in the picture, see SIDE_PAN)
		var b := ball.global_position
		var along := b.z
		if not follow_players.is_empty():
			var pz := 0.0
			for fp in follow_players:
				pz += (fp as Node3D).global_position.z
			along = lerpf(pz / float(follow_players.size()), b.z, 0.4)
		want_pos.z += clampf(along * 0.2, -pan, pan)
		want_focus = Vector3(0.0, clampf(float(g["focus"].y) + b.y * 0.15, 0.3, 1.5), clampf(along * 0.28, -pan * 1.4, pan * 1.4))
	elif view == 1:
		want_focus = g["focus"]
	elif ball != null:
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
			var from_pos: Vector3 = _intro_from[0]
			var from_focus: Vector3 = _intro_from[1]
			want_pos = from_pos.lerp(g["pos"], e)
			want_focus = from_focus.lerp(g["focus"], e)
			want_fov = lerpf(float(_intro_from[2]), g["fov"], e)
			if u >= 1.0:
				_mode = "game"
		"point":
			# stay on the broadcast view, drift slightly towards where the ball came down and zoom in a touch
			if view == 1:
				want_pos = g["pos"]
				want_pos.z += clampf(_point_focus.z * 0.15, -pan, pan)
				want_focus = Vector3(0.0, 0.5, clampf(_point_focus.z * 0.3, -2.0, 2.0))
				want_fov = float(g["fov"]) - 4.0
			else:
				want_pos.x = clampf(_point_focus.x * 0.25, -1.6, 1.6)
				want_focus = Vector3(clampf(_point_focus.x * 0.55, -3.0, 3.0), 0.8, _point_focus.z * 0.55)
				want_fov = float(g["fov"]) - 7.0
			if _mode_t > 2.2:
				_mode = "game"
		"free":
			want_pos = _free[0]
			want_focus = _free[1]
			want_fov = _free[2]
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

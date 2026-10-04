class_name ReplaySystem
extends Node
## Instant replay like the reference game: the last seconds of a rally are recorded (ball + every athlete's skeleton
## pose at 30 Hz) and played back in slow motion from a side-on tracking camera, with a "Replay" label, a progress line
## and a skip prompt. Playback uses ghost copies of the four characters; the real ball is driven by the recording
## (its own physics is switched off meanwhile) so the speed-coloured ribbon behaves exactly as in the live game.

signal finished

const HZ := 30.0
const KEEP := 7.0                        # seconds of history that are kept
const CLIP := 3.8                        # seconds of the end of the rally that are replayed

var ms: MatchScene
var recording := true
var playing := false
var _frames: Array = []
var _acc := 0.0
var _t := 0.0
var _ghosts: Array = []                  # CharacterRig per athlete
var _play_t := 0.0
var _t_start := 0.0
var _t_end := 0.0
var _hold := 0.0
var _side := 1.0
var _started_ms := 0
var _skip := false
var _overlay: Control = null
var _shots_done := 0


func setup(scene: MatchScene) -> void:
	ms = scene
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 20           # after every athlete / the ball moved this tick


# ------------------------------------------------------------------ recording
func _physics_process(dt: float) -> void:
	if playing:
		_play_tick(dt)
		return
	if not recording or ms == null or ms.ball == null:
		return
	_t += dt
	_acc += dt
	if _acc < 1.0 / HZ:
		return
	_acc -= 1.0 / HZ
	_capture()


func _capture() -> void:
	var b := ms.ball
	var rb := b.ribbon
	var f := {"t": _t, "bp": b.global_position, "bv": b.vel, "br": b._rot.orthonormalized(), "live": b.live,
			"rib": rb.active, "boost": rb.boost, "oc": rb.override_col, "style": rb.style, "team": rb.team(), "ath": []}
	for a in ms.athletes:
		var r: CharacterRig = a.rig
		var bones: Array = []
		var sk := r.skeleton
		for i in sk.get_bone_count():
			bones.append(sk.get_bone_pose(i))
		(f["ath"] as Array).append({"xf": r.global_transform, "lean": r.lean_pivot.transform, "bones": bones})
	_frames.append(f)
	while _frames.size() > 2 and float(_frames[_frames.size() - 1]["t"]) - float(_frames[0]["t"]) > KEEP:
		_frames.pop_front()


func has_clip() -> bool:
	return _frames.size() > int(HZ)


func can_play() -> bool:
	return has_clip() and not playing


func clear() -> void:
	_frames.clear()


# ------------------------------------------------------------------ playback
## starts playing the end of the recording (call can_play() first; `finished` fires when it is over or skipped).
## hold = seconds to linger on the last frame
func start(hold := 0.7) -> void:
	if playing or not has_clip():
		return
	var hud = ms.hud
	var ov: Control = hud.replay_overlay if hud != null else null
	_overlay = ov
	playing = true
	_skip = false
	_hold = hold
	_t_end = float(_frames[_frames.size() - 1]["t"])
	_t_start = maxf(float(_frames[0]["t"]), _t_end - CLIP)
	_play_t = _t_start
	var last_ball: Vector3 = _frames[_frames.size() - 1]["bp"]
	_side = 1.0 if last_ball.x < 0.5 else -1.0
	_started_ms = Time.get_ticks_msec()
	# wipe in: cover the screen, swap to the replay while it is covered, then reveal
	if ov != null:
		await ov.cover()
	_enter()
	if ov != null:
		ov.begin()
		ov.reveal()


func _enter() -> void:
	for a in ms.athletes:
		a.visible = false
	_build_ghosts()
	ms.ball.set_physics_process(false)
	ms.ball.reset_physics_interpolation()
	ms.hud.replay_mode = true
	ms.cam_rig.start_replay()
	_apply(_play_t)


func _build_ghosts() -> void:
	_free_ghosts()
	for a in ms.athletes:
		var g := CharacterRig.new()
		add_child(g)
		g.build(a.rig.entry, false)
		g.anim.active = false
		g.anim.stop()
		_ghosts.append(g)


func _free_ghosts() -> void:
	for g in _ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_ghosts.clear()


func _speed(u: float) -> float:
	# the last second before the end is played slower (the winning hit and the landing)
	var left := (_t_end - _play_t)
	return lerpf(0.35, 0.85, smoothstep(0.6, 1.8, left))


func _play_tick(dt: float) -> void:
	if _ghosts.is_empty():
		return
	var u := clampf((_play_t - _t_start) / maxf(_t_end - _t_start, 0.01), 0.0, 1.0)
	if _play_t < _t_end:
		_play_t = minf(_play_t + dt * _speed(u), _t_end)
	else:
		_hold -= dt
	_apply(_play_t)
	if _overlay != null:
		_overlay.set_progress(u)
	_dev_shots(u)
	var held_ms := Time.get_ticks_msec() - _started_ms
	if _skip or (_play_t >= _t_end and _hold <= 0.0) or held_ms > 14000:
		_leave()


func _apply(tp: float) -> void:
	# find the surrounding frames
	var n := _frames.size()
	var i := 0
	while i < n - 2 and float(_frames[i + 1]["t"]) <= tp:
		i += 1
	var f0: Dictionary = _frames[i]
	var f1: Dictionary = _frames[mini(i + 1, n - 1)]
	var span := float(f1["t"]) - float(f0["t"])
	var u := clampf((tp - float(f0["t"])) / span, 0.0, 1.0) if span > 0.0001 else 0.0
	# ball
	var b := ms.ball
	var bp: Vector3 = (f0["bp"] as Vector3).lerp(f1["bp"], u)
	b.global_position = bp
	b.vel = (f0["bv"] as Vector3).lerp(f1["bv"], u)
	b.live = bool(f0["live"])
	b.mesh.basis = (f0["br"] as Basis).slerp(f1["br"], u).orthonormalized() * Basis.from_scale(b.mesh.scale)
	b._update_shadow()
	var rb := b.ribbon
	if rb.active != bool(f0["rib"]) or rb.boost != int(f0["boost"]):
		rb.style = String(f0["style"])
		rb.set_mode(bool(f0["rib"]), int(f0["boost"]), f0["oc"], int(f0["team"]))
	# athletes
	for k in _ghosts.size():
		var g: CharacterRig = _ghosts[k]
		var a0: Dictionary = (f0["ath"] as Array)[k]
		var a1: Dictionary = (f1["ath"] as Array)[k]
		g.global_transform = (a0["xf"] as Transform3D).interpolate_with(a1["xf"], u)
		g.lean_pivot.transform = (a0["lean"] as Transform3D).interpolate_with(a1["lean"], u)
		var s0: Array = a0["bones"]
		var s1: Array = a1["bones"]
		var sk := g.skeleton
		for j in mini(sk.get_bone_count(), s0.size()):
			sk.set_bone_pose(j, (s0[j] as Transform3D).interpolate_with(s1[j], u))
	_camera(float(_play_t - _t_start) / maxf(_t_end - _t_start, 0.01), bp)


## side-on tracking shot along the net with a slow push-in
func _camera(u: float, bp: Vector3) -> void:
	var d := lerpf(13.0, 10.0, u)
	var pos := Vector3(_side * d, lerpf(2.9, 2.3, u), clampf(bp.z * 0.85, -6.0, 6.0))
	var focus := Vector3(bp.x * 0.4, clampf(bp.y * 0.7 + 0.35, 0.9, 3.2), clampf(bp.z * 0.95, -6.5, 6.5))
	ms.cam_rig.set_replay_view(pos, focus, lerpf(42.0, 36.0, u))


## dev: --replayshot=<prefix> saves three frames of the first replay and quits
func _dev_shots(u: float) -> void:
	if Game.main == null or not Game.main.dev.has("replayshot"):
		return
	var marks := [0.15, 0.5, 0.92]
	if _shots_done < marks.size() and u >= float(marks[_shots_done]):
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [Game.main.dev["replayshot"], _shots_done])
		_shots_done += 1
		if _shots_done >= marks.size():
			print("replay shots saved")
			get_tree().quit()


func skip() -> void:
	if playing and Time.get_ticks_msec() - _started_ms > 450:
		_skip = true


func _input(event: InputEvent) -> void:
	if not playing:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed) or (event is InputEventJoypadButton and event.pressed):
		skip()


func _leave() -> void:
	if not playing:
		return
	playing = false
	var ov := _overlay
	if ov != null:
		await ov.cover()
		ov.end()
	_free_ghosts()
	for a in ms.athletes:
		a.visible = true
	ms.ball.set_physics_process(true)
	ms.ball.reset_physics_interpolation()
	ms.hud.replay_mode = false
	ms.cam_rig.end_replay()
	if ov != null:
		ov.reveal()
	clear()
	_t = 0.0
	finished.emit()

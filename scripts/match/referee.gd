class_name Referee
extends Node3D
## The umpire: a random cartoon animal on a high chair beside the net post. Follows the ball with its whole body, whistles
## at the serve, points to the side that scored, signals "out", and reacts to the match with small gags (shaking its head,
## sighing, wiping its brow, yawning, even dozing off when nothing happens for a long time).
##
## Everything is cheap: one rig with a plain AnimationPlayer (clips are baked in scripts/rig/clip_defs.gd, "ref_*") and one
## merged vertex-coloured chair mesh.

const SEAT_H := 1.62                         # seat surface height
const SPOT := Vector3(-6.6, 0.0, 0.0)        # outside the left side line, level with the net post
const GAGS := ["ref_yawn", "ref_wipe", "ref_shrug", "ref_sigh", "ref_wave", "ref_nod"]

var rig: CharacterRig
var entry: Dictionary = {}
var director: MatchDirector
var ball: Node3D
var cam: Camera3D

var _prio := 0
var _busy := 0.0
var _quiet := 0.0                            # seconds since anything happened
var _next_gag := 11.0
var _sleeping := false
var _wow_cd := 0.0                           # surprise is rare, so it stays funny
var _look := 0.0                             # current extra yaw of the rig (radians, relative to the chair)
var _rng := RandomNumberGenerator.new()
var scene: MatchScene
var _gaze: Variant = null                    # Vector3: look at this spot instead of the ball (the server being scolded)
var _gaze_until := 0.0
var _dev_clip := ""                          # dev: --refclip=<clip> replays one clip forever


## `look` = the venue look (Arena.LOOKS[...]) so the chair matches the boards
func build(p_director: MatchDirector, p_ball: Node3D, look: Dictionary, p_scene: MatchScene = null) -> void:
	director = p_director
	ball = p_ball
	scene = p_scene
	_rng.randomize()
	position = SPOT
	rotation.y = -PI * 0.5                    # the rig and the chair face -Z locally: this turns them to +x (towards the court)
	_build_chair(look)
	entry = _pick_animal()
	rig = CharacterRig.new()
	add_child(rig)
	rig.build(entry)
	rig.scale *= 1.2                         # the umpire is a size up from the players: easier to read from the broadcast camera
	var leg: float = rig.info.hips_rest.y * rig.scale.y
	rig.position = Vector3(0.0, SEAT_H - 0.5 * leg, 0.02)
	rig.play("ref_idle", 0.0)
	rig.anim.seek(_rng.randf() * 3.0, true)
	if Game.main != null and Game.main.dev.has("refclip"):
		_dev_clip = String(Game.main.dev["refclip"])
	director.rally_event.connect(_on_rally)
	director.point_scored.connect(_on_point)
	director.match_over.connect(func(_w): _react("ref_cheer", 6))
	director.serve_started.connect(func(_s): _react("ref_whistle", 2))


func _pick_animal() -> Dictionary:
	var pool: Array[Dictionary] = []
	for e in Roster.all():
		if e["kind"] == "cube" and not String(e["model"]).ends_with("/Human.fbx"):
			pool.append(e)
	if Game.main != null and Game.main.dev.has("ref"):
		for e in Roster.all():
			if e["id"] == String(Game.main.dev["ref"]):
				return e
	return pool[_rng.randi() % pool.size()]


# ------------------------------------------------------------------ chair
func _build_chair(look: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var frame := Color(0.78, 0.8, 0.84)
	var dark: Color = (look["plinth"] as Color).lightened(0.12)
	var cush: Color = look["cap"]
	var w := 0.62                              # half width of the stand (x)
	var d := 0.55                              # half depth (z)
	# legs, slightly splayed outwards at the bottom (a tall ladder-like frame)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var top := Vector3(sx * (w - 0.08), SEAT_H - 0.06, sz * (d - 0.08))
			var bot := Vector3(sx * (w + 0.12), 0.0, sz * (d + 0.14))
			_bar(st, bot, top, 0.07, frame)
	# braces
	for h in [0.45, 0.95]:
		for sz in [-1.0, 1.0]:
			_bar(st, Vector3(-w - 0.04, h, sz * (d + 0.07)), Vector3(w + 0.04, h, sz * (d + 0.07)), 0.045, frame)
		for sx in [-1.0, 1.0]:
			_bar(st, Vector3(sx * (w + 0.06), h, -d - 0.07), Vector3(sx * (w + 0.06), h, d + 0.07), 0.045, frame)
	_bar(st, Vector3(-w, 0.3, d + 0.08), Vector3(w, 1.2, d + 0.08), 0.04, frame)
	_bar(st, Vector3(w, 0.3, d + 0.08), Vector3(-w, 1.2, d + 0.08), 0.04, frame)
	# seat (a cushion on a plate) and the back rest, arm rails
	_box(st, Vector3(0, SEAT_H - 0.04, 0), Vector3(w * 2.0 + 0.1, 0.07, d * 2.0 + 0.1), dark)
	_box(st, Vector3(0, SEAT_H + 0.02, 0), Vector3(w * 2.0 - 0.1, 0.06, d * 2.0 - 0.1), cush)
	_box(st, Vector3(0, SEAT_H + 0.4, d - 0.02), Vector3(w * 2.0 - 0.1, 0.62, 0.07), cush)
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * (w - 0.02), SEAT_H + 0.3, 0.0), Vector3(0.07, 0.07, d * 2.0 - 0.12), frame)
		_box(st, Vector3(sx * (w - 0.02), SEAT_H + 0.17, d - 0.16), Vector3(0.07, 0.3, 0.07), frame)
	# a footrest bar in front, a small step on the back (the ladder)
	_box(st, Vector3(0, SEAT_H - 0.55, -d - 0.06), Vector3(w * 1.6, 0.06, 0.1), frame)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.5
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## a thin box between two points (square section)
func _bar(st: SurfaceTool, a: Vector3, b: Vector3, th: float, col: Color) -> void:
	var dir := b - a
	var len := dir.length()
	var y := dir / len
	var x := y.cross(Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.UP).normalized()
	var z := x.cross(y).normalized()
	_box(st, (a + b) * 0.5, Vector3(th, len, th), col, Basis(x, y, z))


func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var f := [
		[Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)],
		[Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z)],
		[Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)],
		[Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)],
		[Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)],
		[Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)],
	]
	for q in f:
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.add_vertex(c + basis * (q[i] as Vector3))


# ------------------------------------------------------------------ behaviour
func _process(dt: float) -> void:
	if rig == null:
		return
	# follow the ball with the whole upper body (the ball is hidden during the VS shot: look at the net then)
	var target := 0.0
	var watch: Variant = null
	if _gaze != null and float(Time.get_ticks_msec()) / 1000.0 < _gaze_until:
		watch = _gaze
	elif ball != null and ball.visible:
		watch = ball.global_position
	if watch != null:
		var to := (watch as Vector3) - (global_position + Vector3(0, 0, 0))
		# local yaw: the chair faces +x (global); atan2 of the ball offset along the chair's right (+z) vs forward (+x)
		target = clampf(atan2(to.z, maxf(to.x, 0.5)), -1.05, 1.05)
	if _busy > 0.0 or _sleeping:
		target *= 0.35                               # reactions mostly look at the court
	_look = lerp_angle(_look, target, 1.0 - exp(-dt / 0.14))
	rig.rotation.y = -_look                          # chair-local right = +z global = -local... (rig yaw about the local up axis)
	_quiet += dt
	_wow_cd = maxf(_wow_cd - dt, 0.0)
	if _dev_clip != "":
		if not rig.anim.is_playing() or rig.anim.current_animation != _dev_clip:
			rig.play(_dev_clip, 0.1)
		return
	if _busy > 0.0:
		_busy -= dt
		if _busy <= 0.0 and not _sleeping:
			_prio = 0
			rig.play("ref_idle", 0.3)
		return
	if _sleeping:
		return
	var in_rally := director != null and director.phase == MatchDirector.P.RALLY
	if _quiet > 34.0 and not in_rally:
		_sleeping = true
		rig.play("ref_sleep", 0.8)
		return
	_next_gag -= dt
	if _next_gag <= 0.0:
		_next_gag = _rng.randf_range(10.0, 18.0)
		if not in_rally and director != null and director.phase != MatchDirector.P.INTRO:
			_react(GAGS[_rng.randi() % GAGS.size()], 1)


func _react(clip: String, prio: int, force := false) -> void:
	if rig == null or not rig.anim.has_animation(clip):
		return
	if _sleeping:
		_sleeping = false
		clip = "ref_wow"                                # woken up by the action
		prio = 5
	if not force and _busy > 0.0 and prio < _prio:
		return
	_prio = prio
	_busy = rig.anim.get_animation(clip).length
	if Game.main != null and Game.main.dev.has("log"):
		print("[ref] ", entry["name"], " ", clip)
	_quiet = 0.0
	rig.play(clip, 0.14)


func _on_rally(ev: String, data: Dictionary) -> void:
	match ev:
		"net":
			_wow(0.25)
		"block":
			if data.get("kill", false):
				_wow(0.4)
		"hit":
			var info: Dictionary = data.get("info", {})
			if String(info.get("kind", "")) == "spike" and float(info.get("power", 0.0)) > 0.8:
				_wow(0.14)
		"close_call":
			_react("ref_think", 3)
		"match_point":
			_react("ref_nod", 2)
		"vs_end":
			_react("ref_wave", 2)
		"serve_warn":
			_throw(data["athlete"] as Athlete, int(data["n"]))


func _wow(chance: float) -> void:
	if _wow_cd <= 0.0 and _rng.randf() < chance:
		_wow_cd = 9.0
		_react("ref_wow", 2)


func _on_point(team: int, reason: String, _pos: Vector3) -> void:
	var rally := 0
	if director != null and not director.rally_history.is_empty():
		rally = int(director.rally_history[director.rally_history.size() - 1].get("len", 0))
	var clip := "ref_point_r" if team == 0 else "ref_point_l"     # the umpire's right hand points to +z = team 0's half
	match reason:
		"出界":
			clip = "ref_out"
		"触网":
			clip = "ref_shake"
		"发球失误":
			clip = "ref_shrug"
		"发球超时":
			clip = "ref_stern"
		"ACE!":
			clip = "ref_cheer"
	_react(clip, 4, true)
	if rally >= 9:
		_after(2.2, "ref_wipe")                          # a long rally: phew
	elif _rng.randf() < 0.12:
		_after(1.9, GAGS[_rng.randi() % GAGS.size()])


func _after(delay: float, clip: String) -> void:
	await get_tree().create_timer(delay).timeout
	if is_inside_tree() and _busy < 0.3:
		_react(clip, 1)


# ------------------------------------------------------------------ scolding a dawdling server (the funny bit)
## warning 1: something small (pencil stub / eraser / paper ball / paper plane); warning 2: something bigger (rubber duck / score book)
func _throw(a: Athlete, tier: int) -> void:
	if rig == null or a == null:
		return
	_sleeping = false
	var right := a.global_position.z >= 0.0                     # the umpire's right hand reaches +z (team 0's baseline)
	var clip := "ref_throw_r" if right else "ref_throw_l"
	_gaze = a.global_position
	_gaze_until = float(Time.get_ticks_msec()) / 1000.0 + 2.6
	Sfx.play("whistle_short", -3.0)
	_react(clip, 7, true)
	await get_tree().create_timer(0.44).timeout                # the release frame of the clip
	if not is_inside_tree() or not is_instance_valid(a):
		return
	var from := rig.hand_world("r" if right else "l")
	_launch(a, ThrowProp.random_id(tier), tier, from)


func _launch(a: Athlete, id: String, tier: int, from: Vector3) -> void:
	var prop := ThrowProp.make(id, 2.6 if tier <= 1 else 3.2)       # (cartoon-sized so it reads from the broadcast camera)
	get_parent().add_child(prop)
	prop.global_position = from
	var spin := Vector3(_rng.randf_range(2.0, 4.0), _rng.randf_range(2.0, 5.0), 0.0) * TAU * (1.0 if _rng.randf() < 0.5 else -1.0)
	var dur := 0.66
	Sfx.play("whoosh", -6.0, 1.2)
	var tw := prop.create_tween()
	tw.tween_method(func(u: float):
		if not is_instance_valid(a):
			return
		var to := a.rig.head_world() + Vector3(0, 0.04, 0)
		prop.global_position = from.lerp(to, u) + Vector3(0, 0.55 * 4.0 * u * (1.0 - u), 0)
		prop.rotation = spin * u, 0.0, 1.0, dur)
	tw.tween_callback(func(): _prop_hit(a, prop, tier, from))


func _prop_hit(a: Athlete, prop: MeshInstance3D, tier: int, from_pos := Vector3.ZERO) -> void:
	if not is_instance_valid(a):
		prop.queue_free()
		return
	a.bonk()
	var head_y: float = a.rig.head_world().y - a.global_position.y + 0.3        # (bone centre -> top of the head)
	AlertMark.spawn_over(a, head_y, 1.4)
	Sfx.play("body_bump", -1.0, 0.9)
	Sfx.play("ui_confirm", -4.0, 1.7)
	if prop.has_meta("id") and (String(prop.get_meta("id")) == "fish" or String(prop.get_meta("id")) == "slipper"):
		Sfx.play("hit_bump", -3.0, 1.4)                           # the "slap"
	if scene != null:
		scene.cam_rig.shake(0.18 if tier <= 1 else 0.3)
		scene.vfx.hit_burst(prop.global_position, "good", 0.35)
	if Game.main != null and Game.main.dev.has("log"):
		print("[ref] prop hit ", a.display_name, " tier ", tier)
	# it bounces off the head (back towards where it came from, and up), falls and bounces on the floor a few times, then shrinks away
	var base_scale := prop.scale
	var dir := (prop.global_position - from_pos).normalized() if from_pos != Vector3.ZERO else Vector3(1, 0, 0)
	var side := Vector3(-dir.z, 0, dir.x) * _rng.randf_range(-0.7, 0.7)
	var launch := Vector3(-dir.x, 0.0, -dir.z) * _rng.randf_range(0.9, 1.6) + side + Vector3(0, _rng.randf_range(2.6, 3.4), 0)
	var spin := Vector3(_rng.randf_range(-9.0, 9.0), _rng.randf_range(-7.0, 7.0), _rng.randf_range(-9.0, 9.0))
	var floor_y := 0.055
	var bounce := func(k: float):
		if Game.main != null and Game.main.dev.has("log"):
			print("[propbounce] strength=%.2f y=%.2f" % [k, prop.global_position.y])
		Sfx.play("bounce", -13.0 + 7.0 * k, _rng.randf_range(1.5, 1.9))
		var sq := prop.create_tween()
		sq.tween_property(prop, "scale", base_scale * Vector3(1.0 + 0.18 * k, 1.0 - 0.22 * k, 1.0 + 0.18 * k), 0.04)
		sq.tween_property(prop, "scale", base_scale, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if scene != null and k > 0.45:
			scene.vfx.hit_burst(Vector3(prop.global_position.x, 0.05, prop.global_position.z), "good", 0.12)
	var tw := ThrowProp.tumble(prop, launch, spin, floor_y, bounce)
	tw.tween_interval(1.5)
	tw.tween_property(prop, "scale", Vector3.ZERO, 0.3)
	tw.tween_callback(prop.queue_free)

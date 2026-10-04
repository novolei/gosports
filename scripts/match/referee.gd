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
	ThrowProp.launch_at(get_parent(), scene, a, id, tier, from)

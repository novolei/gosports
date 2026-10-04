class_name Stage
extends Node3D
## 3D backdrop for menus / results: the arena with a slowly moving camera and a few display characters.

var arena: Arena
var cam: Camera3D
var _t := 0.0
var focus := Vector3(0, 1.0, 0)
var cam_pos := Vector3(0, 3.0, 11.0)
var _want_pos := Vector3(0, 3.0, 11.0)
var _want_focus := Vector3(0, 1.0, 0)
var sway := 1.0
var rigs: Array[CharacterRig] = []
var show_court_chars := true


func _ready() -> void:
	arena = Arena.new()
	add_child(arena)
	arena.build(max(Game.settings["quality"] - 1, 0))
	cam = Camera3D.new()
	cam.fov = 48
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved from _process
	add_child(cam)
	cam.current = true
	cam_pos = _want_pos
	focus = _want_focus
	_apply()


func look(pos: Vector3, tgt: Vector3, snap := false) -> void:
	_want_pos = pos
	_want_focus = tgt
	if snap:
		cam_pos = pos
		focus = tgt
		_apply()


func add_rig(entry: Dictionary, pos: Vector3, yaw := 0.0, clip := "ready") -> CharacterRig:
	var r := CharacterRig.new()
	add_child(r)
	r.build(entry)
	r.position = pos
	r.rotation.y = yaw
	r.play(clip, 0.0)
	rigs.append(r)
	return r


func clear_rigs() -> void:
	for r in rigs:
		if is_instance_valid(r):
			r.queue_free()
	rigs.clear()


func _process(dt: float) -> void:
	_t += dt
	cam_pos = cam_pos.lerp(_want_pos, 1.0 - exp(-3.0 * dt))
	focus = focus.lerp(_want_focus, 1.0 - exp(-3.0 * dt))
	_apply()


func _apply() -> void:
	var sw := Vector3(sin(_t * 0.35) * 0.35 * sway, sin(_t * 0.27) * 0.12 * sway, 0)
	cam.global_position = cam_pos + sw
	cam.look_at(focus, Vector3.UP)

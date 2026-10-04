class_name Confetti
extends MultiMeshInstance3D
## Cheap, deterministic confetti burst: one MultiMesh of small coloured quads integrated on the CPU.

const COLORS := [Color(1.0, 0.3, 0.5), Color(0.3, 0.7, 1.0), Color(1.0, 0.85, 0.2), Color(0.4, 0.95, 0.5), Color(0.8, 0.5, 1.0), Color(1.0, 0.6, 0.2)]

var _pos: PackedVector3Array
var _vel: PackedVector3Array
var _rot: PackedVector3Array
var _spin: PackedVector3Array
var _col: PackedColorArray
var _t := 0.0
var _life := 3.0
var count := 90


func start(center: Vector3, p_count := 90, spread := 2.4, height := 4.2) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # updated every rendered frame
	count = p_count
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(0.13, 0.08)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	q.material = m
	mm.mesh = q
	mm.instance_count = count
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pos.resize(count)
	_vel.resize(count)
	_rot.resize(count)
	_spin.resize(count)
	_col.resize(count)
	for i in count:
		_pos[i] = center + Vector3(randf_range(-spread, spread), height + randf_range(-0.5, 1.0), randf_range(-spread, spread))
		_vel[i] = Vector3(randf_range(-1.2, 1.2), randf_range(-0.5, 2.2), randf_range(-1.2, 1.2))
		_rot[i] = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		_spin[i] = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
		_col[i] = COLORS[randi() % COLORS.size()]
	_update(0.0)


func _process(dt: float) -> void:
	_t += dt
	if _t >= _life:
		queue_free()
		return
	_update(dt)


func _update(dt: float) -> void:
	var fade := clampf((_life - _t) / 0.6, 0.0, 1.0)
	for i in count:
		_vel[i].y -= 3.2 * dt
		_vel[i] *= 1.0 - 0.9 * dt        # air drag: flutters down slowly
		_pos[i] += _vel[i] * dt
		_rot[i] += _spin[i] * dt
		if _pos[i].y < 0.04:
			_pos[i].y = 0.04
			_vel[i] = Vector3.ZERO
			_spin[i] = Vector3.ZERO
		var b := Basis.from_euler(_rot[i]) * Basis.from_scale(Vector3.ONE * fade)
		multimesh.set_instance_transform(i, Transform3D(b, _pos[i]))
		multimesh.set_instance_color(i, _col[i])

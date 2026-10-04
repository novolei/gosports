class_name DizzyStars
extends Node3D
## Little stars circling a dazed athlete's head (cartoon "seeing stars"). Follows the head bone, fades out on request.

const STAR := "res://core/assets/gfx/star.png"
const COUNT := 5

var ath: Node3D                       # any athlete-like node with `.rig.head_world()` (core must not name a sport's Athlete class)
var _stars: Array[MeshInstance3D] = []
var _t := 0.0
var _fade := 1.0
var _fading := false


func setup(a: Node3D) -> void:
	ath = a
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var tex: Texture2D = load(STAR)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(1.0, 0.9, 0.35)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	mat.render_priority = 6
	var quad := QuadMesh.new()
	quad.size = Vector2(0.24, 0.24)
	quad.material = mat
	for i in COUNT:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_stars.append(mi)
	_follow()
	_place(0.0)


func fade_out() -> void:
	_fading = true


func _follow() -> void:
	if ath != null and is_instance_valid(ath):
		global_position = ath.rig.head_world() + Vector3(0.0, 0.3, 0.0)


func _place(dt: float) -> void:
	for i in _stars.size():
		var ang := _t * 4.2 + float(i) * TAU / float(COUNT)
		var bob := sin(_t * 7.0 + float(i) * 1.7) * 0.035
		_stars[i].position = Vector3(cos(ang) * 0.36, bob, sin(ang) * 0.3)
		var pulse := 0.85 + 0.25 * sin(_t * 9.0 + float(i) * 2.1)
		_stars[i].scale = Vector3.ONE * pulse * _fade


func _process(dt: float) -> void:
	_t += dt
	if _fading:
		_fade -= dt * 4.0
		if _fade <= 0.0:
			queue_free()
			return
	_follow()
	_place(dt)

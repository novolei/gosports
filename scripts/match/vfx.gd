class_name Vfx
extends Node3D
## Particles and floor markers: hit sparkles, dust puffs, confetti, landing marker, aim marker.

const STAR := "res://assets/env/star.png"
const SOFT := "res://assets/env/soft_circle.png"
const RING_SHADER := "res://shaders/ring.gdshader"

var ball: Ball
var landing: MeshInstance3D
var landing_mat: ShaderMaterial
var aim: MeshInstance3D
var aim_mat: ShaderMaterial
var _star_tex: Texture2D
var _soft_tex: Texture2D
var show_landing := true


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # markers / particles move in _process
	_star_tex = load(STAR)
	_soft_tex = load(SOFT)
	var grad: Texture2D = load("res://assets/env/ring_gradient.png")
	landing = _make_ring(Color(1.0, 1.0, 1.0, 0.95), 0.0, grad)
	landing_mat = landing.material_override
	landing_mat.set_shader_parameter("inner", 0.45)
	landing_mat.set_shader_parameter("rainbow", 0.0)
	landing_mat.set_shader_parameter("fill_alpha", 0.2)
	landing.visible = false
	add_child(landing)
	aim = _make_ring(Color(1.0, 0.82, 0.2, 1.0), 0.0, grad)
	aim_mat = aim.material_override
	aim_mat.set_shader_parameter("inner", 0.3)
	aim_mat.set_shader_parameter("rainbow", 0.0)
	aim_mat.set_shader_parameter("fill_alpha", 0.28)
	aim.visible = false
	add_child(aim)


func _make_ring(col: Color, pulse: float, grad: Texture2D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	m.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = load(RING_SHADER)
	sm.set_shader_parameter("ring_color", col)
	sm.set_shader_parameter("grad", grad)
	m.material_override = sm
	m.rotation_degrees.x = -90
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


func _process(_dt: float) -> void:
	var _p := Prof.t0()
	_process_impl(_dt)
	Prof.add("vfx", _p)


func _process_impl(_dt: float) -> void:
	# predicted landing circle
	if ball != null and show_landing and ball.live and not ball.floor_touched:
		var l := ball.predict_landing()
		if not l.is_empty():
			var p: Vector3 = l["pos"]
			landing.visible = true
			landing.global_position = Vector3(p.x, 0.025, p.z)
			var s := 0.95 + 0.08 * sin(Time.get_ticks_msec() * 0.012)
			var tl: float = l["t"]
			landing.scale = Vector3(s, s, 1.0) * (1.0 + clampf(tl, 0.0, 2.0) * 0.18)
			var inside := Court.in_court(p, 0.0)
			landing_mat.set_shader_parameter("ring_color", Color(1, 1, 1, 0.9) if inside else Color(1.0, 0.45, 0.35, 0.9))
		else:
			landing.visible = false
	else:
		landing.visible = false


func show_aim(p) -> void:
	if p == null:
		aim.visible = false
		return
	aim.visible = true
	var pp: Vector3 = p
	aim.global_position = Vector3(pp.x, 0.03, pp.z)
	var s := 0.8 + 0.06 * sin(Time.get_ticks_msec() * 0.01)
	aim.scale = Vector3(s, s, 1)


# ------------------------------------------------------------------ bursts
func _burst(pos: Vector3, tex: Texture2D, amount: int, life: float, vel_min: float, vel_max: float, size: float,
		grav: float, col: Color, spread := 180.0, dir := Vector3.UP, additive := true) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = vel_min
	p.initial_velocity_max = vel_max
	p.gravity = Vector3(0, -grav, 0)
	p.scale_amount_min = size * 0.7
	p.scale_amount_max = size * 1.2
	p.color = col
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	p.mesh = q
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.4).timeout.connect(p.queue_free)
	return p


func hit_burst(pos: Vector3, quality: String, power: float) -> void:
	match quality:
		"perfect":
			_burst(pos, _star_tex, 12, 0.55, 2.0, 4.5, 0.2, 2.0, Color(1.0, 0.92, 0.4))
			_burst(pos, _soft_tex, 3, 0.28, 0.3, 0.9, 0.55, 0.0, Color(1, 1, 0.8, 0.55))
		"good":
			_burst(pos, _star_tex, 6, 0.4, 1.5, 3.2, 0.15, 3.0, Color(1.0, 0.95, 0.7))
		_:
			_burst(pos, _soft_tex, 3, 0.25, 0.6, 1.2, 0.28, 0.0, Color(1, 1, 1, 0.5))


func dust(pos: Vector3) -> void:
	_burst(Vector3(pos.x, 0.08, pos.z), _soft_tex, 7, 0.55, 0.6, 1.8, 0.65, -0.5, Color(0.95, 0.9, 0.82, 0.55), 70.0, Vector3.UP, false)


func step_dust(pos: Vector3) -> void:
	_burst(Vector3(pos.x, 0.06, pos.z), _soft_tex, 3, 0.4, 0.25, 0.8, 0.34, -0.2, Color(0.95, 0.92, 0.85, 0.38), 60.0, Vector3.UP, false)


func floor_impact(pos: Vector3) -> void:
	_burst(Vector3(pos.x, 0.05, pos.z), _soft_tex, 6, 0.4, 0.5, 1.4, 0.5, 0.0, Color(1, 1, 1, 0.5), 80.0, Vector3.UP, false)
	# expanding ring
	var grad: Texture2D = load("res://assets/env/ring_gradient.png")
	var r := _make_ring(Color(1, 1, 1, 1), 0.0, grad)
	r.material_override.set_shader_parameter("inner", 0.0)
	r.material_override.set_shader_parameter("rainbow", 0.0)
	r.material_override.set_shader_parameter("fill_alpha", 0.0)
	r.material_override.set_shader_parameter("width", 0.08)
	add_child(r)
	r.global_position = Vector3(pos.x, 0.03, pos.z)
	r.scale = Vector3(0.4, 0.4, 1)
	var t := create_tween().set_parallel(true)
	t.tween_property(r, "scale", Vector3(2.4, 2.4, 1), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_method(func(v: float): r.material_override.set_shader_parameter("intensity", v), 1.0, 0.0, 0.5)
	t.chain().tween_callback(r.queue_free)


func confetti(center: Vector3, amount := 70) -> void:
	var c := Confetti.new()
	add_child(c)
	c.start(center, amount)


func ring_pulse(pos: Vector3, col: Color) -> void:
	var grad: Texture2D = load("res://assets/env/ring_gradient.png")
	var r := _make_ring(col, 0.0, grad)
	r.material_override.set_shader_parameter("inner", 0.0)
	r.material_override.set_shader_parameter("rainbow", 0.0)
	r.material_override.set_shader_parameter("fill_alpha", 0.0)
	add_child(r)
	r.global_position = Vector3(pos.x, 0.03, pos.z)
	r.scale = Vector3(0.5, 0.5, 1)
	var t := create_tween().set_parallel(true)
	t.tween_property(r, "scale", Vector3(3.2, 3.2, 1), 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_method(func(v: float): r.material_override.set_shader_parameter("intensity", v), 1.0, 0.0, 0.7)
	t.chain().tween_callback(r.queue_free)

# ------------------------------------------------------------------ body collisions
## level 1 = brushed, 2 = stumble, 3 = knock-down
func body_hit(pos: Vector3, level: int) -> void:
	var ground := Vector3(pos.x, 0.0, pos.z)
	match level:
		1:
			_burst(pos, _soft_tex, 3, 0.3, 0.4, 1.0, 0.35, 0.0, Color(1, 1, 1, 0.45))
		2:
			dust(ground)
			_burst(pos, _star_tex, 7, 0.45, 1.8, 3.6, 0.17, 3.0, Color(1.0, 0.95, 0.75))
			ring_pulse(ground, Color(1, 1, 1, 0.9))
		_:
			dust(ground)
			floor_impact(ground)
			_burst(pos, _star_tex, 16, 0.65, 2.5, 6.0, 0.24, 2.5, Color(1.0, 0.82, 0.3))
			_burst(pos, _soft_tex, 4, 0.3, 0.3, 1.0, 0.8, 0.0, Color(1, 1, 0.85, 0.7))
			ring_pulse(ground, Color(1.0, 0.85, 0.35, 1.0))
			bonk_icon(pos + Vector3(0.0, 0.55, 0.0))


## cartoon "bonk" emblem (dazed face + bump) that pops in, wobbles, rises and fades
func bonk_icon(pos: Vector3) -> void:
	var sp := Sprite3D.new()
	sp.texture = load("res://assets/env/bonk_icon.png")
	sp.pixel_size = 0.0029
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.double_sided = true
	sp.no_depth_test = true
	sp.render_priority = 8
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	add_child(sp)
	sp.global_position = pos
	sp.scale = Vector3.ONE * 0.1
	var t := create_tween()
	t.tween_property(sp, "scale", Vector3.ONE * 1.25, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(sp, "scale", Vector3.ONE, 0.1)
	t.set_parallel(true)
	# a little cartoon wobble, then drift up and fade
	t.tween_method(func(v: float): sp.rotation.z = sin(v * 18.0) * 0.16 * (1.0 - v), 0.0, 1.0, 0.7).set_delay(0.1)
	t.tween_property(sp, "global_position:y", pos.y + 0.6, 0.7).set_delay(0.1)
	t.tween_property(sp, "modulate:a", 0.0, 0.3).set_delay(0.55)
	t.chain().tween_callback(sp.queue_free)

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
var director: MatchDirector = null
var humans: Array = []                  # human athletes: each gets their own "where to stand" marker
var _mark_shot_done := false
var _marks := {}                        # Athlete -> {"node": MeshInstance3D, "mat": ShaderMaterial, "a": float}


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
	landing.visible = false              # (the old always-on landing circle is replaced by the per-player markers below)
	_update_marks(_dt)


## "where to stand" marker, designed to carry as little information as possible (see docs section 22):
##  - only for a ball that is coming down on the human's own half, from the moment it is hit until ~0.1 s before contact
##  - the player who is meant to take the ball gets the full marker (a fixed ring + a ring that closes in on it = time left),
##    a team mate's ball only gets a faint ring so nobody runs into the wrong spot
##  - red when the ball will land outside the court; nothing at all for balls going to the other half
func _update_marks(dt: float) -> void:
	var level := int(Game.settings.get("landing_hint", 1))
	# newcomers get the full version for their first matches unless they picked a level themselves
	if not bool(Game.settings.get("landing_hint_set", false)) and Game.profile != null and not Game.profile.flags.get("tutorial_done", false) 			and int(Game.profile.stats.get("matches", 0)) < 3:
		level = 2
	if Game.main != null and Game.main.dev.has("hintlevel"):
		level = int(Game.main.dev["hintlevel"])
	for h in humans:
		var m := _mark(h)
		var want := 0.0
		var pos := Vector3.ZERO
		var tleft := 99.0
		var mine := false
		var out := false
		if level > 0 and director != null and ball != null and ball.live and not ball.floor_touched 				and director.phase == MatchDirector.P.RALLY and ball.age > 0.08:
			var plan: Dictionary = director.plans[h.team]
			if plan.get("mode") == "play" and plan.get("who") != null:
				mine = plan["who"] == h
				pos = plan["pos"]
				tleft = float(plan["t"])
				if mine or level == 2:
					want = 1.0 if mine else 0.38
				if tleft < 0.1:
					want = 0.0
				var l := ball.predict_landing()
				if not l.is_empty():
					out = not Court.in_court(l["pos"], 0.0)
		m["a"] = move_toward(float(m["a"]), want, dt * (7.0 if want > 0.0 else 12.0))
		var node: MeshInstance3D = m["node"]
		var mat: ShaderMaterial = m["mat"]
		var a: float = m["a"]
		node.visible = a > 0.01
		if not node.visible:
			continue
		node.global_position = Vector3(pos.x, 0.026, pos.z)
		if mine and not _mark_shot_done and Game.main != null and Game.main.dev.has("markshot") and a > 0.95 				and Vector2(pos.x - h.global_position.x, pos.z - h.global_position.z).length() > 2.2:
			_mark_shot_done = true
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(str(Game.main.dev["markshot"]))
			get_tree().quit()
		var base := 1.7 if mine else 1.25
		node.scale = Vector3(base, base, 1.0)
		var col := Color(1.0, 0.46, 0.38) if out else (Color(1, 1, 1) if mine else Color(0.85, 0.95, 1.0))
		mat.set_shader_parameter("ring_color", Color(col.r, col.g, col.b, a * (0.95 if mine else 0.8)))
		# the inner ring closes in on the target as the ball comes down (1.2 s -> contact)
		var closing := clampf(tleft / 1.2, 0.0, 1.0)
		mat.set_shader_parameter("inner", lerpf(0.3, 0.86, closing) if (mine and level == 2) else 2.0)
		mat.set_shader_parameter("fill_alpha", 0.16 if mine else 0.06)


func _mark(h: Athlete) -> Dictionary:
	if not _marks.has(h):
		var grad: Texture2D = load("res://assets/env/ring_gradient.png")
		var n := _make_ring(Color(1, 1, 1, 0.9), 0.0, grad)
		var mat: ShaderMaterial = n.material_override
		mat.set_shader_parameter("rainbow", 0.0)
		mat.set_shader_parameter("width", 0.12)
		mat.set_shader_parameter("halo_strength", 0.8)
		n.visible = false
		add_child(n)
		_marks[h] = {"node": n, "mat": mat, "a": 0.0}
	return _marks[h]


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

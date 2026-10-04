class_name Ball
extends Node3D
## The volleyball. Custom ballistic simulation (exact, predictable trajectories for aiming / AI / landing
## markers) instead of rigid-body physics. Hits are scripted by the Athletes through launch().

signal floor_contact(pos: Vector3)            # first time the ball touches the floor after a launch
signal net_contact(pos: Vector3)
signal crossed_net(to_team: int)

const MODEL := "res://assets/ball/volleyball.fbx"
const TEX := "res://assets/ball/volleyball_color.png"

var vel := Vector3.ZERO
var spin := Vector3.ZERO        # rad/s (cosmetic)
var live := false               # flying under physics
var held_by: Node3D = null      # serve hold
var hold_offset := Vector3.ZERO
var floor_touched := false
var net_touched_at := -1.0
var age := 0.0                  # seconds since the last launch
var combo := false              # power spike (bump-set-spike all perfect): pink trail, not killable by a block
var power := 0.0                # 0..1, how violent the last hit was (trail / sfx intensity)
var side := 0                   # which half the ball is in
var mesh: MeshInstance3D
var pivot: Node3D                # squash & stretch happens here (world aligned with the flight direction)
var _shape_t := 0.0
var _shape_s := 0.0
const SHAPE_DUR := 0.2
var trail: GPUParticles3D
var ribbon: BallRibbon
var halo: MeshInstance3D
var shadow: MeshInstance3D
var _trail_mat: ParticleProcessMaterial
var _rot := Basis.IDENTITY
var _glow := 0.0
var trail_color := Color(1.0, 0.85, 0.2)


var skin_tint := Color.WHITE          # equipped ball skin (set by MatchScene before add_child)
var trail_style := "speed"            # equipped ribbon style for the human team's hits

func _ready() -> void:
	_build_visual()
	side = 0


func _build_visual() -> void:
	var scn: PackedScene = load(MODEL)
	var m: Node3D = scn.instantiate()
	pivot = Node3D.new()
	add_child(pivot)
	mesh = MeshInstance3D.new()
	pivot.add_child(mesh)
	# the FBX mesh is 1.5 units across (+ node scale); fit it to the ball radius
	var src := m.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	mesh.mesh = src.mesh
	var bb := src.mesh.get_aabb()
	var s := (Court.BALL_R * 2.0) / maxf(bb.size.x, 0.0001)
	mesh.scale = Vector3.ONE * s
	m.free()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(TEX)
	mat.roughness = 0.42
	mat.metallic_specular = 0.55
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	mat.rim_enabled = true
	mat.rim = 0.3
	mat.rim_tint = 0.5
	mat.albedo_color = skin_tint
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# soft halo (billboard) - makes the ball readable against busy backgrounds
	halo = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.62, 0.62)
	halo.mesh = q
	var hm := StandardMaterial3D.new()
	hm.albedo_texture = load("res://assets/env/soft_circle.png")
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.albedo_color = Color(1, 0.95, 0.7, 0.0)
	hm.no_depth_test = false
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo.material_override = hm
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)

	# trail
	trail = GPUParticles3D.new()
	trail.amount = 28
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.emitting = false
	trail.draw_order = GPUParticles3D.DRAW_ORDER_LIFETIME
	trail.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 30, 60))
	_trail_mat = ParticleProcessMaterial.new()
	_trail_mat.direction = Vector3.ZERO
	_trail_mat.gravity = Vector3.ZERO
	_trail_mat.initial_velocity_min = 0.0
	_trail_mat.initial_velocity_max = 0.0
	_trail_mat.scale_min = 0.9
	_trail_mat.scale_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(1, 0))
	var sct := CurveTexture.new()
	sct.curve = sc
	_trail_mat.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.9))
	grad.set_color(1, Color(1, 0.7, 0.1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	_trail_mat.color_ramp = gt
	trail.process_material = _trail_mat
	var tq := QuadMesh.new()
	tq.size = Vector2(0.32, 0.32)
	var tm := StandardMaterial3D.new()
	tm.albedo_texture = load("res://assets/env/soft_circle.png")
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	tm.vertex_color_use_as_albedo = true
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.albedo_color = Color(1, 1, 1, 1)
	tq.material = tm
	trail.draw_pass_1 = tq
	add_child(trail)
	trail.top_level = false
	ribbon = BallRibbon.new()
	add_child(ribbon)
	ribbon.setup(self)

	# ground shadow blob
	shadow = MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(0.7, 0.7)
	shadow.mesh = sq
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = load("res://assets/env/soft_circle.png")
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.05, 0.05, 0.15, 0.55)
	shadow.material_override = sm
	shadow.rotation_degrees.x = -90
	shadow.top_level = true
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)


# ------------------------------------------------------------------ control
func place(p: Vector3) -> void:
	global_position = p
	vel = Vector3.ZERO
	live = false
	floor_touched = false
	reset_physics_interpolation()
	_update_shadow()


func hold(by: Node3D, offset: Vector3) -> void:
	held_by = by
	hold_offset = offset
	live = false
	vel = Vector3.ZERO
	floor_touched = false


func release() -> void:
	held_by = null


func launch(v: Vector3, p_power := 0.3, p_spin := Vector3.ZERO) -> void:
	held_by = null
	vel = v
	live = true
	age = 0.0
	power = p_power
	spin = p_spin if p_spin != Vector3.ZERO else Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-6, 6)) * (0.5 + p_power)
	floor_touched = false
	net_touched_at = -1.0


## squash on contact, stretch along the new flight direction, then settle (strength ~0.3 .. 1.2)
func punch_shape(strength: float) -> void:
	_shape_t = SHAPE_DUR
	_shape_s = strength


func _update_shape(dt: float) -> void:
	if _shape_t <= 0.0:
		if pivot.basis != Basis.IDENTITY:
			pivot.basis = Basis.IDENTITY
		return
	# real time (the hit-stop freezes the game clock, the squash must still be visible)
	_shape_t = maxf(_shape_t - dt / maxf(Engine.time_scale, 0.02), 0.0)
	var u := 1.0 - _shape_t / SHAPE_DUR
	var k := 1.0 + _shape_s * (-0.26 * smoothstep(0.0, 0.18, u) * (1.0 - smoothstep(0.18, 0.34, u)) + 0.36 * smoothstep(0.3, 0.42, u) * (1.0 - smoothstep(0.45, 1.0, u)))
	var dir := vel.normalized() if vel.length() > 0.5 else Vector3.UP
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var w := 1.0 / sqrt(k)
	pivot.basis = Basis.looking_at(dir, up) * Basis.from_scale(Vector3(w, w, k))


## ribbon streak behind the ball, coloured by its speed. boost: 1 = "Nice!" hit, 2 = power spike (override_col = pink)
func set_trail(on: bool, boost := 0, override_col := Color(0, 0, 0, 0), team := -1) -> void:
	ribbon.style = trail_style if team == 0 else "speed"
	ribbon.set_mode(on, boost, override_col, team)


func flash(strength := 1.0) -> void:
	_glow = strength


# ------------------------------------------------------------------ prediction helpers
## where (and when) the ball centre is at height h while descending (null if it never gets there)
func predict_at_height(h: float) -> Dictionary:
	var t := Court.time_to_height(global_position.y, vel.y, h)
	if t < 0.0:
		return {}
	return {"t": t, "pos": Court.pos_at(global_position, vel, t)}


func predict_landing() -> Dictionary:
	return predict_at_height(Court.BALL_R)


# ------------------------------------------------------------------ simulation
func _physics_process(dt: float) -> void:
	var _p := Prof.t0()
	_physics_process_impl(dt)
	Prof.add("ball.phys", _p)


func _physics_process_impl(dt: float) -> void:
	if held_by != null:
		global_position = held_by.global_position + hold_offset
		_update_shadow()
		return
	if not live:
		_update_shadow()
		return
	age += dt
	var steps := 2
	var h := dt / steps
	for i in steps:
		_step(h)
	_spin_visual(dt)
	_update_shadow()


func _step(h: float) -> void:
	var p0 := global_position
	vel.y -= Court.GRAVITY * h
	var p1 := p0 + vel * h
	# --- net (a vertical plane at z = 0)
	if (p0.z > 0.0) != (p1.z > 0.0) and absf(vel.z) > 0.0001:
		var t := -p0.z / vel.z
		var y := p0.y + vel.y * t
		var x := p0.x + vel.x * t
		if absf(x) <= Court.NET_X:
			if y < Court.NET_TOP + 0.03 and y > 0.02:
				# hits the net: bounce back, lose most energy
				var back := signf(p0.z)
				p1 = Vector3(x, y, back * (Court.BALL_R + 0.02))
				vel = Vector3(vel.x * 0.4, vel.y * 0.35, -vel.z * 0.22)
				net_touched_at = age
				net_contact.emit(p1)
			else:
				crossed_net.emit(0 if p1.z > 0.0 else 1)
		else:
			crossed_net.emit(0 if p1.z > 0.0 else 1)
	# --- floor
	if p1.y - Court.BALL_R <= 0.0 and vel.y < 0.0:
		p1.y = Court.BALL_R
		if not floor_touched:
			floor_touched = true
			global_position = p1
			floor_contact.emit(p1)
		vel.y = -vel.y * Court.FLOOR_BOUNCE
		vel.x *= 0.88
		vel.z *= 0.88
		if absf(vel.y) < 1.6:
			vel.y = 0.0
	# ground roll friction
	if p1.y <= Court.BALL_R + 0.001 and vel.y == 0.0:
		vel.x = move_toward(vel.x, 0.0, 2.0 * h)
		vel.z = move_toward(vel.z, 0.0, 2.0 * h)
	# keep it from flying away when nobody picks it up
	p1.x = clampf(p1.x, -40.0, 40.0)
	p1.z = clampf(p1.z, -40.0, 40.0)
	global_position = p1
	side = 0 if p1.z >= 0.0 else 1


func _spin_visual(dt: float) -> void:
	var w := spin
	if w.length() > 0.001:
		_rot = Basis(w.normalized(), w.length() * dt) * _rot
		mesh.basis = _rot.orthonormalized() * Basis.from_scale(mesh.scale)
	spin *= 0.992


func _process(dt: float) -> void:
	var _p := Prof.t0()
	_process_impl(dt)
	Prof.add("ball.proc", _p)


func _process_impl(dt: float) -> void:
	# halo + glow follow
	_glow = move_toward(_glow, 0.0, dt * 1.6)
	_update_shape(dt)
	var hm := halo.material_override as StandardMaterial3D
	var near_net := clampf(1.0 - absf(global_position.z) / 2.2, 0.0, 1.0)
	var a := clampf(_glow * 0.45 + near_net * 0.25 * (1.0 if live else 0.0), 0.0, 0.6)
	var hc := Color(1, 0.95, 0.75)
	if ribbon != null and ribbon.active and ribbon.head_color.a > 0.05 and live:
		# the glow around the ball takes the colour of the streak
		hc = Color(ribbon.head_color.r, ribbon.head_color.g, ribbon.head_color.b)
		a = maxf(a, 0.3 * ribbon.head_color.a)
	hm.albedo_color = Color(hc.r, hc.g, hc.b, a)
	halo.scale = Vector3.ONE * (1.0 + _glow * 0.35)


func _update_shadow() -> void:
	var p := global_position
	shadow.global_position = Vector3(p.x, 0.012, p.z)
	var k := clampf(1.0 - p.y / 9.0, 0.25, 1.0)
	shadow.scale = Vector3.ONE * (0.55 + 0.5 * k)
	(shadow.material_override as StandardMaterial3D).albedo_color.a = 0.5 * k

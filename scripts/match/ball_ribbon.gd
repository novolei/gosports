class_name BallRibbon
extends MeshInstance3D
## Camera-facing ribbon behind the flying ball. The colour follows the ball's SPEED, point by point, so the streak
## shifts hue as the ball slows down: cyan (lob) -> mint -> yellow -> orange -> hot pink (smash).
## It tapers to a point and fades along its length. `boost` (a "Nice!" hit) makes it wider and brighter, an
## override colour (the bump-set-spike power spike) replaces the speed ramp with a thick pink band.

const MAX_POINTS := 90
const STEP := 0.09                  # max distance between two ribbon points (fast balls are subdivided)
## ball speed (m/s) -> colour
const RAMP := [
	[6.0, Color(0.5, 0.88, 1.0)],
	[8.5, Color(0.42, 0.98, 0.78)],
	[11.0, Color(0.5, 1.0, 0.45)],
	[13.5, Color(1.0, 0.93, 0.32)],
	[16.5, Color(1.0, 0.62, 0.22)],
	[20.0, Color(1.0, 0.3, 0.62)],
]

var ball: Ball
var active := false
var boost := 0                      # 0 normal, 1 "Nice!", 2 power spike
var override_col := Color(0, 0, 0, 0)
var life := 0.42
var head_color := Color(1, 1, 1, 0)
var style := "speed"                 # equipped trail style of the human team (see Profile.TRAILS)
var _team := -1
var _pts: Array = []                # {p: Vector3, age: float, spd: float}
var _mat: StandardMaterial3D


static func speed_color(v: float) -> Color:
	if v <= RAMP[0][0]:
		return RAMP[0][1]
	for i in range(1, RAMP.size()):
		if v <= RAMP[i][0]:
			var t: float = inverse_lerp(RAMP[i - 1][0], RAMP[i][0], v)
			return (RAMP[i - 1][1] as Color).lerp(RAMP[i][1], t)
	return RAMP[RAMP.size() - 1][1]


func setup(b: Ball) -> void:
	ball = b
	top_level = true
	global_transform = Transform3D.IDENTITY     # vertices are in world space; top_level keeps the old global offset
	mesh = ArrayMesh.new()
	custom_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 40, 80))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.disable_receive_shadows = true
	material_override = _mat
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## on: trail while the ball flies. boost 0..2 (see above). override_color: Color(0,0,0,0) = use the speed ramp.
func set_mode(on: bool, p_boost := 0, p_override := Color(0, 0, 0, 0), p_team := -1) -> void:
	active = on
	_team = p_team
	boost = p_boost
	override_col = p_override
	life = 0.42 + 0.08 * float(p_boost)
	if not on:
		head_color.a = 0.0


func clear() -> void:
	_pts.clear()
	active = false
	(mesh as ArrayMesh).clear_surfaces()


func _process(dt: float) -> void:
	var _p := Prof.t0()
	_process_impl(dt)
	Prof.add("ribbon", _p)


func _process_impl(dt: float) -> void:
	if ball == null:
		return
	for e in _pts:
		e["age"] = float(e["age"]) + dt
	if active and ball.live:
		var p := ball.get_global_transform_interpolated().origin
		var spd := ball.vel.length()
		if _pts.is_empty():
			_pts.push_front({"p": p, "age": 0.0, "spd": spd})
		else:
			var prev: Dictionary = _pts[0]
			var pp: Vector3 = prev["p"]
			var dist := pp.distance_to(p)
			if dist > 0.02:
				# subdivide long steps so the band stays smooth at smash speed
				var n := maxi(int(ceil(dist / STEP)), 1)
				var prev_age: float = prev["age"]
				var prev_spd: float = prev["spd"]
				for j in range(1, n + 1):
					var t := float(j) / float(n)
					_pts.push_front({"p": pp.lerp(p, t), "age": prev_age * (1.0 - t), "spd": lerpf(prev_spd, spd, t)})
				while _pts.size() > MAX_POINTS:
					_pts.pop_back()
	while not _pts.is_empty() and float(_pts[_pts.size() - 1]["age"]) > life:
		_pts.pop_back()
	_build()


func _style_color(u: float) -> Color:
	var t := float(Time.get_ticks_msec()) / 1000.0
	match style:
		"star":
			return Color(1.0, 0.93, 0.6).lerp(Color(1.0, 1.0, 0.95), 0.5 + 0.5 * sin(u * 38.0 - t * 18.0))
		"team":
			return Color(0.2, 0.62, 1.0) if _team == 0 else Color(1.0, 0.35, 0.62)
		"sakura":
			return Color(1.0, 0.68, 0.85).lerp(Color(1.0, 1.0, 1.0), u)
		"rainbow":
			return Color.from_hsv(fmod(u * 0.85 + t * 0.6, 1.0), 0.62, 1.0)
		"fire":
			return Color(1.0, 0.86, 0.25).lerp(Color(1.0, 0.25, 0.1), clampf(u * 1.4, 0.0, 1.0))
		"ice":
			return Color(0.95, 1.0, 1.0).lerp(Color(0.4, 0.78, 1.0), clampf(u * 1.3, 0.0, 1.0))
	return Color.WHITE


func _point_color(spd: float, u: float) -> Color:
	var c: Color = override_col if override_col.a > 0.0 else (speed_color(spd) if style == "speed" else _style_color(u))
	# bright core near the head, solid colour in the body, transparent tail
	var core := c.lightened(0.5 + 0.1 * float(boost))
	var col := core.lerp(c, clampf(u / 0.28, 0.0, 1.0))
	var fade := (1.0 - smoothstep(0.25, 1.0, u)) * (0.45 + 0.55 * smoothstep(0.0, 0.07, u))
	col.a = clampf(0.92 * fade, 0.0, 1.0)
	# slow lobs get a fainter streak
	col.a *= clampf(inverse_lerp(4.5, 8.0, spd), 0.25, 1.0)
	return col


func _build() -> void:
	var am := mesh as ArrayMesh
	am.clear_surfaces()
	var n := _pts.size()
	if n < 2:
		head_color.a = 0.0
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cpos := cam.global_position
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n * 2)
	cols.resize(n * 2)
	var wmul := 1.0 + 0.28 * float(mini(boost, 1)) + (0.7 if boost >= 2 else 0.0)
	for i in n:
		var p: Vector3 = _pts[i]["p"]
		var spd: float = _pts[i]["spd"]
		var u: float = clampf(float(_pts[i]["age"]) / life, 0.0, 1.0)
		var dir: Vector3
		if i < n - 1:
			dir = (_pts[i]["p"] as Vector3) - (_pts[i + 1]["p"] as Vector3)
		else:
			dir = (_pts[i - 1]["p"] as Vector3) - p
		var side := dir.cross(cpos - p)
		side = side.normalized() if side.length() > 0.0001 else Vector3.UP
		# faster ball = a slightly fatter streak
		var w := (0.12 + clampf(spd, 0.0, 22.0) * 0.0052) * wmul * 0.5 * pow(1.0 - u, 0.8) * (0.7 + 0.3 * smoothstep(0.0, 0.06, u))
		var c := _point_color(spd, u)
		verts[i * 2] = p + side * w
		verts[i * 2 + 1] = p - side * w
		cols[i * 2] = c
		cols[i * 2 + 1] = c
		if i == 0:
			head_color = c
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)

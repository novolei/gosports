extends SceneTree
## Dev tool: the speed-coloured ball ribbon. Launches balls side by side at different speeds and saves a frame.
##   godot --path . --rendering-driver opengl3 -s tools/preview_trail.gd -- out.png [boost 0|1|2] [styles]

var out_path := ""
var frames := 0
var balls: Array[Ball] = []
var cam: Camera3D
const SPEEDS := [6.0, 8.5, 11.0, 14.0, 17.5, 22.0]
const STYLES := ["speed", "star", "team", "sakura", "rainbow", "fire", "ice"]


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out_path = a[0]
	var boost := int(a[1]) if a.size() > 1 else 0
	root.size = Vector2i(1600, 700)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.68, 0.75)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.95)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var floor_m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 30)
	floor_m.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.93, 0.62, 0.55)
	floor_m.material_override = fm
	root.add_child(floor_m)
	var n := STYLES.size() if a.size() > 2 and a[2] == "styles" else SPEEDS.size()
	for i in n:
		var b := Ball.new()
		root.add_child(b)
		b.position = Vector3(-6.0, 2.4, -float(i) * 1.1 + 2.2)
		balls.append(b)
	cam = Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0.5, 3.0, 9.5), Vector3(0.5, 2.2, 0.0))
	cam.current = true
	_go.call_deferred(boost)


func _go(boost: int) -> void:
	for i in balls.size():
		var b := balls[i]
		# horizontal flight at speed v with a gentle arc so gravity does not dominate the picture
		b.launch(Vector3(SPEEDS[mini(i, SPEEDS.size() - 1)] if balls.size() <= SPEEDS.size() else 14.0, 1.5, 0.0), 0.5, Vector3.ZERO)
		if balls.size() > SPEEDS.size():
			b.trail_style = STYLES[i]
			b.set_trail(true, 0, Color(0, 0, 0, 0), 0)
		elif boost >= 2:
			b.set_trail(true, 2, Color(1.0, 0.36, 0.68))
		else:
			b.set_trail(true, boost)


func _process(_dt: float) -> bool:
	frames += 1
	if frames == 26:
		var b5: Ball = balls[balls.size() - 1]
		print("screen: ball ", cam.unproject_position(b5.get_global_transform_interpolated().origin), " first ", cam.unproject_position(b5.ribbon._pts[0]["p"]), " last ", cam.unproject_position(b5.ribbon._pts[b5.ribbon._pts.size() - 1]["p"]))
		var am: ArrayMesh = b5.ribbon.mesh
		print("ribbon xform ", b5.ribbon.global_transform, " top_level ", b5.ribbon.top_level, " surfaces ", am.get_surface_count(), " aabb ", am.get_aabb())
		var arr := am.surface_get_arrays(0)
		var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		print("verts ", vv.size(), " v0 ", vv[0], " v1 ", vv[1], " vlast ", vv[vv.size() - 1])
		for b in balls:
			var pts: Array = b.ribbon._pts
			print("ball ", b.global_position, " interp ", b.get_global_transform_interpolated().origin, " pts=", pts.size(),
					" first=", (pts[0]["p"] if pts.size() > 0 else null), " last=", (pts[pts.size() - 1]["p"] if pts.size() > 0 else null), " active=", b.ribbon.active, " vel=", b.vel)
		root.get_viewport().get_texture().get_image().save_png(out_path)
		print("saved ", out_path)
		quit()
	return false

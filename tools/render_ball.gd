extends SceneTree
## Renders the real in-game volleyball (mesh + texture + dark outline hull) to a transparent PNG for the logo / app icon.
##   godot --path . --resolution 512x512 -s tools/render_ball.gd -- [yaw] [pitch] [roll] [out.png]
## (needs a window: do not pass --headless). tools/make_logo.py composes the icon from the result.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var yaw := float(args[0]) if args.size() > 0 else 20.0
	var pitch := float(args[1]) if args.size() > 1 else -25.0
	var roll := float(args[2]) if args.size() > 2 else 12.0
	var out := String(args[3]) if args.size() > 3 else "res://art_src/brand/ball_render.png"
	var vp := SubViewport.new()
	vp.size = Vector2i(2048, 2048)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.88, 1.0)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.16
	cam.position = Vector3(0, 0, 5)
	vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -42, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.97, 0.9)
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(25, 140, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.7, 0.82, 1.0)
	vp.add_child(fill)
	var pivot := Node3D.new()
	vp.add_child(pivot)
	var scn: PackedScene = load("res://assets/ball/volleyball.fbx")
	var m: Node3D = scn.instantiate()
	var src := m.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var bb := src.mesh.get_aabb()
	var s := 2.0 / maxf(bb.size.x, 0.0001)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/ball/volleyball_vivid.png")
	mat.roughness = 0.38
	mat.metallic_specular = 0.5
	mat.rim_enabled = true
	mat.rim = 0.15
	var ball := MeshInstance3D.new()
	ball.mesh = src.mesh
	ball.material_override = mat
	ball.scale = Vector3.ONE * s
	ball.position = -bb.get_center() * s
	var holder := Node3D.new()
	pivot.add_child(holder)
	holder.add_child(ball)
	var om := StandardMaterial3D.new()
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.cull_mode = BaseMaterial3D.CULL_FRONT
	om.albedo_color = Color(0.05, 0.12, 0.3)
	var ring := MeshInstance3D.new()
	ring.mesh = src.mesh
	ring.material_override = om
	ring.scale = Vector3.ONE * s * 1.045
	ring.position = ball.position * 1.045
	holder.add_child(ring)
	m.free()
	pivot.rotation_degrees = Vector3(pitch, yaw, roll)
	for i in 6:
		await process_frame
	var img := vp.get_texture().get_image()
	var path := out
	if path.begins_with("res://"):
		path = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("saved ", path, " ", img.get_size())
	quit()

extends SceneTree
## Dev tool: does the ball sit in the hands at the contact frame? Renders side + front views per hit kind.
## godot --path . -s tools/preview_contact.gd -- out.png character_id

var out_path := ""
var frames := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out_path = a[0]
	var id: String = a[1] if a.size() > 1 else "m"
	root.size = Vector2i(1800, 900)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.78, 0.88, 0.97)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.87, 0.97)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	root.add_child(sun)
	var kinds := [["bump", 0.0], ["set", 0.0], ["spike", 1.0], ["serve", 0.0]]
	var entry := Roster.by_id(id)
	var i := 0
	for k in kinds:
		var kind: String = k[0]
		var feet_y: float = k[1]
		for view in 2:
			var holder := Node3D.new()
			holder.position = Vector3((i % 4) * 3.2 - 4.8, 0, -(i / 4) * 3.6)
			root.add_child(holder)
			var rig := CharacterRig.new()
			holder.add_child(rig)
			rig.build(entry)
			var spec: Dictionary = {
				"bump": {"clip": "bump", "contact": 0.20, "ideal_y": 0.85, "reach": 0.45},
				"set": {"clip": "set", "contact": 0.20, "ideal_y": 1.45, "reach": 0.28},
				"spike": {"clip": "spike", "contact": 0.26, "ideal_y": 1.5, "reach": 0.42},
				"serve": {"clip": "serve_hit", "contact": 0.30, "ideal_y": 1.55, "reach": 0.35},
			}[kind]
			var clip: String = spec["clip"]
			rig.play(clip, 0.0)
			rig.anim.seek(float(spec["contact"]), true)
			rig.anim.pause()
			rig.position.y = feet_y
			holder.rotation.y = 0.0 if view == 0 else deg_to_rad(-90)   # front-ish (facing -Z) vs side
			# ball at the ideal contact point (in -Z, in front of the chest)
			var bp := Vector3(0, feet_y + float(spec["ideal_y"]), -float(spec["reach"]))
			var ball := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.14
			sm.height = 0.28
			ball.mesh = sm
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(1, 0.6, 0.1)
			ball.material_override = m
			ball.position = bp
			holder.add_child(ball)
			var lb := Label3D.new()
			lb.text = "%s %s" % [kind, "back" if view == 0 else "side"]
			lb.pixel_size = 0.005
			lb.font_size = 40
			lb.position = Vector3(0, -0.2, 0.3)
			holder.add_child(lb)
			i += 1
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 4.2, 11.0), Vector3(0, 1.2, -2.0))
	cam.current = true


func _process(_dt: float) -> bool:
	frames += 1
	if frames == 14:
		root.get_viewport().get_texture().get_image().save_png(out_path)
		print("saved ", out_path)
		quit()
	return false


extends SceneTree
## Dev tool: render the whole roster (or a subset) with CharacterRig.
## godot --path . -s tools/preview_cast.gd -- out.png cols clip [from_index count] [yaw]

var out_path := ""
var frames := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out_path = a[0]
	var cols := int(a[1])
	var clip: String = a[2]
	var from_i := int(a[3]) if a.size() > 3 else 0
	var count := int(a[4]) if a.size() > 4 else 99
	var yaw := float(a[5]) if a.size() > 5 else 0.0
	root.size = Vector2i(1800, 1000)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.7, 0.85, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.84, 0.95)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	root.add_child(sun)
	var all := Roster.all()
	var list: Array = []
	for i in range(from_i, mini(from_i + count, all.size())):
		list.append(all[i])
	var rows := int(ceil(list.size() / float(cols)))
	for i in list.size():
		var rig := CharacterRig.new()
		root.add_child(rig)
		rig.build(list[i])
		rig.position = Vector3(((i % cols) - (cols - 1) * 0.5) * 1.5, 0, -(i / cols) * 1.9)
		rig.rotation_degrees.y = yaw
		if clip == "none":
			rig.anim.stop()
			rig.skeleton.reset_bone_poses()
		else:
			rig.play(clip, 0.0)
		if OS.get_environment("PV_PLAIN") != "":
			for mi in rig.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				for s in m.mesh.get_surface_count():
					var om := m.get_surface_override_material(s)
					if om is StandardMaterial3D:
						var pm := StandardMaterial3D.new()
						pm.albedo_texture = (om as StandardMaterial3D).albedo_texture
						pm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
						m.set_surface_override_material(s, pm)
		var lb := Label3D.new()
		lb.text = list[i]["name"]
		lb.pixel_size = 0.004
		lb.font_size = 48
		lb.position = rig.position + Vector3(0, 0, 0.55)
		lb.rotation_degrees.x = -40
		root.add_child(lb)
	var cam := Camera3D.new()
	cam.fov = 38
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 3.2 + rows * 0.9, 6.5 + rows * 1.7), Vector3(0, 0.8, -(rows - 1) * 0.95))
	cam.current = true


func _process(_dt: float) -> bool:
	frames += 1
	if frames == 12:
		root.get_viewport().get_texture().get_image().save_png(out_path)
		print("saved ", out_path)
		quit()
	return false

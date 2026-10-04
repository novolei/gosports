extends SceneTree
## Dev tool: grid preview of arbitrary models, each normalised to ~2 units.
## godot --path . -s tools/preview_models.gd -- out.png cols  res://a.fbx|res://tex.png  res://b.fbx|  ...

var out_path := ""
var frames := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out_path = a[0]
	var cols := int(a[1])
	root.size = Vector2i(1800, 1000)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.8, 0.88, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	root.add_child(sun)
	var items: Array = []
	for i in range(2, a.size()):
		items.append(a[i])
	var rows := int(ceil(items.size() / float(cols)))
	for i in items.size():
		var parts: PackedStringArray = (items[i] as String).split("|")
		var scn: PackedScene = load(parts[0])
		if scn == null:
			continue
		var inst: Node3D = scn.instantiate()
		var holder := Node3D.new()
		root.add_child(holder)
		holder.add_child(inst)
		if parts.size() > 1 and parts[1] != "":
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = load(parts[1])
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			for mi in _meshes(inst):
				mi.material_override = mat
		var box := _aabb(inst)
		var s := 2.4 / maxf(box.size.x, maxf(box.size.y, box.size.z))
		holder.scale = Vector3.ONE * s
		holder.position = Vector3(((i % cols) - (cols - 1) * 0.5) * 3.0, 0, -(i / cols) * 3.0) - box.get_center() * s
		print(parts[0].get_file(), " size=", box.size, " center=", box.get_center())
		var lb := Label3D.new()
		lb.text = parts[0].get_file()
		lb.pixel_size = 0.006
		lb.font_size = 40
		lb.position = Vector3(((i % cols) - (cols - 1) * 0.5) * 3.0, -1.5, -(i / cols) * 3.0 + 1.0)
		root.add_child(lb)
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 5 + rows, 9 + rows * 2.0), Vector3(0, 0, -(rows - 1) * 1.5))
	cam.current = true


func _process(_dt: float) -> bool:
	frames += 1
	if frames == 6:
		root.get_viewport().get_texture().get_image().save_png(out_path)
		print("saved ", out_path)
		quit()
	return false


func _meshes(n: Node) -> Array:
	var r := []
	if n is MeshInstance3D:
		r.append(n)
	for c in n.get_children():
		r.append_array(_meshes(c))
	return r


func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(n):
		var m := mi as MeshInstance3D
		var local := _xf(m, n) * m.get_aabb() if false else _xf_aabb(m, n)
		if first:
			out = local
			first = false
		else:
			out = out.merge(local)
	return out


func _xf_aabb(m: MeshInstance3D, top: Node3D) -> AABB:
	var xf := Transform3D.IDENTITY
	var n: Node = m
	while n != null and n != top:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf * m.get_aabb()


func _xf(_a, _b) -> Transform3D:
	return Transform3D.IDENTITY

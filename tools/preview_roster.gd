extends SceneTree
## Dev tool: render a grid of "Model:Texture" pairs to a PNG for casting decisions.
## Usage: godot --path . -s tools/preview_roster.gd -- out.png cols Human:Tex_Human_A Bear:Tex_Bear_A ...
## (windowed run - needs a real renderer)

var pairs: Array = []
var out_path := ""
var cols := 6
var frames := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out_path = a[0]
	cols = int(a[1])
	for i in range(2, a.size()):
		pairs.append(a[i])
	var win := root
	win.size = Vector2i(1800, 1000)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.85, 0.9, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	root.add_child(sun)
	var rows := int(ceil(pairs.size() / float(cols)))
	var sp := 2.0
	for i in pairs.size():
		var parts: PackedStringArray = (pairs[i] as String).split(":")
		var scn: PackedScene = load("res://assets/characters/cube/models/%s.fbx" % parts[0])
		if scn == null:
			continue
		var inst: Node3D = scn.instantiate()
		var tex: Texture2D = load("res://assets/characters/cube/textures/%s.png" % parts[1])
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		for mi in _meshes(inst):
			mi.material_override = mat
		var col := i % cols
		var row := i / cols
		inst.position = Vector3((col - (cols - 1) * 0.5) * sp, 0, -row * 2.4)
		inst.scale = Vector3.ONE * 0.6
		root.add_child(inst)
		var lb := Label3D.new()
		lb.text = (pairs[i] as String).replace("Tex_", "")
		lb.pixel_size = 0.004
		lb.font_size = 40
		lb.position = inst.position + Vector3(0, -0.12, 0.8)
		lb.rotation_degrees.x = -30
		root.add_child(lb)
	var cam := Camera3D.new()
	cam.fov = 38
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 6.5 + rows * 0.8, 9.0 + rows * 1.2), Vector3(0, 1.0, -(rows - 1) * 1.2))
	cam.current = true


func _process(_dt: float) -> bool:
	frames += 1
	if frames == 6:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out_path)
		print("saved ", out_path, " ", img.get_size())
		quit()
	return false


func _meshes(n: Node) -> Array:
	var r := []
	if n is MeshInstance3D:
		r.append(n)
	for c in n.get_children():
		r.append_array(_meshes(c))
	return r

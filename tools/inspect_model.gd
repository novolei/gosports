extends SceneTree
## Dev tool: print skeleton / mesh / animation info for imported models.
## Usage: godot --headless --path . -s tools/inspect_model.gd -- res://path/model.fbx [more...]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for p in args:
		_inspect(p)
	quit()


func _inspect(path: String) -> void:
	print("=================== ", path)
	var res = load(path)
	if res == null:
		print("  !! cannot load")
		return
	var root: Node = res.instantiate()
	_dump(root, 0)
	var sk := _find(root, "Skeleton3D") as Skeleton3D
	if sk:
		print("-- bones (", sk.get_bone_count(), ")")
		for i in sk.get_bone_count():
			var rest := sk.get_bone_rest(i)
			print("  [%d] %s parent=%d pos=%s" % [i, sk.get_bone_name(i), sk.get_bone_parent(i), str(rest.origin).substr(0, 40)])
	var ap := _find(root, "AnimationPlayer") as AnimationPlayer
	if ap:
		print("-- animations")
		for n in ap.get_animation_list():
			var a := ap.get_animation(n)
			print("  %s  len=%.2f tracks=%d loop=%d" % [n, a.length, a.get_track_count(), a.loop_mode])
	root.free()


func _dump(n: Node, d: int) -> void:
	var extra := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			extra = " mesh surfaces=%d aabb=%s" % [mi.mesh.get_surface_count(), str(mi.mesh.get_aabb())]
	if n is Node3D:
		var n3 := n as Node3D
		extra += " pos=%s rot=%s scale=%s" % [str(n3.position), str(n3.rotation_degrees), str(n3.scale)]
	print("  ".repeat(d), n.name, " (", n.get_class(), ")", extra)
	for c in n.get_children():
		_dump(c, d + 1)


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null

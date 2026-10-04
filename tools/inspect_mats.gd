extends SceneTree
## Dev tool: print surface/material names + vertex formats of imported models.

func _initialize() -> void:
	for p in OS.get_cmdline_user_args():
		print("=== ", p)
		var scn: PackedScene = load(p)
		var inst := scn.instantiate()
		_walk(inst)
		inst.free()
	quit()


func _walk(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var m := mi.mesh
		print(" mesh ", n.name, " skin=", mi.skin != null, " surfaces=", m.get_surface_count())
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			var arr := m.surface_get_arrays(s)
			print("   surf ", s, " mat=", mat.resource_name if mat else "null", " verts=", (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), " hasBones=", arr[Mesh.ARRAY_BONES] != null and (arr[Mesh.ARRAY_BONES] as PackedInt32Array).size() > 0, " hasUV=", arr[Mesh.ARRAY_TEX_UV] != null)
	for c in n.get_children():
		_walk(c)

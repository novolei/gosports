extends SceneTree
## Dev tool: how many MeshInstances / surfaces / shadow casters the arena + crowd cost (draw calls ~ surfaces x passes).
##   godot --headless --path . -s tools/count_draws.gd -- [quality=1]
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var q := 1
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		q = int(a[0])
	var arena := Arena.new()
	root.add_child(arena)
	arena.build(q)
	var groups := {}
	var total_mi := 0
	var total_surf := 0
	var casters := 0
	var uniq_mesh := {}
	var uniq_mat := {}
	var multis := 0
	for n in arena.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		total_mi += 1
		var sc := mi.mesh.get_surface_count()
		total_surf += sc
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			casters += sc
		uniq_mesh[mi.mesh] = true
		for s in sc:
			var m := mi.get_active_material(s)
			uniq_mat[m] = true
		# group by the top-level child of the arena it lives under
		var top: Node = mi
		while top.get_parent() != null and top.get_parent() != arena:
			top = top.get_parent()
		var k := String(top.name)
		var e: Dictionary = groups.get(k, {"mi": 0, "surf": 0})
		e["mi"] += 1
		e["surf"] += sc
		groups[k] = e
	for n in arena.find_children("*", "MultiMeshInstance3D", true, false):
		multis += 1
	print("quality=%d  MeshInstance3D=%d  surfaces=%d  shadow-casting surfaces=%d  unique meshes=%d  unique materials=%d  MultiMesh=%d" % [q, total_mi, total_surf, casters, uniq_mesh.size(), uniq_mat.size(), multis])
	var keys := groups.keys()
	keys.sort_custom(func(x, y): return groups[x]["surf"] > groups[y]["surf"])
	for k in keys.slice(0, 14):
		print("   %-28s nodes=%-4d surfaces=%d" % [k, groups[k]["mi"], groups[k]["surf"]])
	quit()
